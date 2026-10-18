// SPDX-License-Identifier: MIT
#import "ServiceClient.h"
#import "ServiceIdentity.h"
#import <xpc/xpc.h>
#import "packet.h"
#import "usb.h"
#import "capture.h"
#include <fcntl.h>
#include <unistd.h>

@interface DSClientJob : NSObject
@property(atomic) BOOL cancelled;
@property(strong) xpc_connection_t connection;
@end
@implementation DSClientJob
@end

static DSClientJob *active;
static NSObject *lock;

static void initializeLock(void) {
    static dispatch_once_t once;dispatch_once(&once,^{lock=[NSObject new];});
}
static xpc_object_t request(const char *operation,DSClientJob *job,NSError **error) {
    xpc_connection_t connection=xpc_connection_create_mach_service(DS_SERVICE,NULL,XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);
    NSString *rule=ds_requirement(ds_signing_team(),YES);
    if(!rule || xpc_connection_set_peer_code_signing_requirement(connection,rule.UTF8String))return nil;
    xpc_connection_set_event_handler(connection,^(xpc_object_t event){if(xpc_get_type(event)==XPC_TYPE_ERROR)job.cancelled=YES;});
    job.connection=connection;
    xpc_connection_resume(connection);
    xpc_object_t message=xpc_dictionary_create(NULL,NULL,0);
    xpc_dictionary_set_string(message,"operation",operation);
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    __block xpc_object_t reply=nil;
    xpc_connection_send_message_with_reply(connection,message,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(xpc_object_t item){reply=item;dispatch_semaphore_signal(done);});
    BOOL timeout=dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))!=0;
    if(!job)xpc_connection_cancel(connection);
    if(timeout || !reply || xpc_get_type(reply)!=XPC_TYPE_DICTIONARY || xpc_dictionary_get_string(reply,"error")) {
        const char *text=reply && xpc_get_type(reply)==XPC_TYPE_DICTIONARY?xpc_dictionary_get_string(reply,"error"):NULL;
        if(error)*error=[NSError errorWithDomain:@"DS720D.Service" code:1 userInfo:@{NSLocalizedDescriptionKey:text?@(text):@"Le service du pilote est indisponible. Installe le paquet DS-720D Scanner puis réessaie."}];
        return nil;
    }
    return reply;
}
static void finish(DSClientJob *job) {
    if(job.connection) {
        xpc_object_t message=xpc_dictionary_create(NULL,NULL,0);
        xpc_dictionary_set_string(message,"operation","release");
        dispatch_semaphore_t done=dispatch_semaphore_create(0);
        xpc_connection_send_message_with_reply(job.connection,message,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(xpc_object_t reply){(void)reply;dispatch_semaphore_signal(done);});
        dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC));
        xpc_connection_cancel(job.connection);job.connection=nil;
    }
    @synchronized(lock){if(active==job)active=nil;}
}
static DSClientJob *prepare(NSError **error) {
    initializeLock();DSClientJob *job=[DSClientJob new];
    @synchronized(lock) {
        if(active){if(error)*error=[NSError errorWithDomain:@"DS720D.Service" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Scanner busy."}];return nil;}
        active=job;
    }
    xpc_object_t reply=request("prepare",job,error);
    if(!reply || !xpc_dictionary_get_bool(reply,"prepared") || job.cancelled){finish(job);return nil;}
    return job;
}
NSData *ds_service_capture(NSError **error) {
    DSClientJob *job=prepare(error);if(!job)return nil;
    NSMutableData *raw=[NSMutableData data];__block NSString *failure=nil;
    int status=ds_acquire(^(NSDictionary *item){
        if([item[@"event"] isEqual:@"frame"]) {
            NSData *part=[[NSData alloc] initWithBase64EncodedString:item[@"data"] options:0];
            if(!part || raw.length+part.length>80000000){failure=@"Image exceeds acquisition bounds.";job.cancelled=YES;}
            else [raw appendData:part];
        } else if([item[@"event"] isEqual:@"error"])failure=item[@"message"];
    },^{return job.cancelled;});
    BOOL ok=!status && !failure && !job.cancelled && raw.length && raw.length%DS_NATIVE_BPL==0;
    finish(job);
    if(!ok) {
        if(error)*error=[NSError errorWithDomain:@"DS720D.Capture" code:1 userInfo:@{NSLocalizedDescriptionKey:failure?:@"Acquisition interrupted or incomplete."}];return nil;
    }
    return raw;
}
BOOL ds_service_ping(NSError **error){return request("ping",nil,error)!=nil;}
BOOL ds_service_probe(NSError **error){
    DSClientJob *job=prepare(error);if(!job)return NO;
    DSUSB *usb=job.cancelled?nil:[DSUSB openScanner:error];BOOL ok=usb!=nil;
    [usb close];finish(job);return ok;
}
void ds_service_cancel(void) {
    if(!lock)return;
    @synchronized(lock){active.cancelled=YES;}
}

NSURL *ds_service_capture_file(NSURL *folder,NSError **error) {
    if(!ds_service_ping(error))return nil;
    if(![NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error])return nil;
    NSURL *path=[folder URLByAppendingPathComponent:[NSString stringWithFormat:@"DS720D-%@.jsonl",NSUUID.UUID.UUIDString]];
    int fd=open(path.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if(fd<0){if(error)*error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];return nil;}
    NSData *raw=ds_service_capture(error);
    if(!raw){close(fd);unlink(path.fileSystemRepresentation);return nil;}
    __block BOOL success=YES;
    void (^line)(NSDictionary *)=^(NSDictionary *item){
        NSMutableData *data=[[NSJSONSerialization dataWithJSONObject:item options:0 error:NULL] mutableCopy];
        [data appendBytes:"\n" length:1];
        size_t offset=0;
        while(offset<data.length){ssize_t count=write(fd,(const uint8_t *)data.bytes+offset,data.length-offset);if(count<0 && errno==EINTR)continue;if(count<=0){success=NO;break;}offset+=(size_t)count;}
    };
    line(@{@"event":@"configured",@"dpi":@300,@"bytesPerLine":@(DS_NATIVE_BPL),@"channels":@3,@"stripeRows":@80,@"imagePath":@"memory",@"layout":@"line-planar-rgb"});
    NSUInteger frames=0;
    for(NSUInteger offset=0;offset<raw.length && success;) {
        NSUInteger size=MIN(DS_NATIVE_BPL*DS_STRIPE_ROWS,raw.length-offset);
        NSData *part=[raw subdataWithRange:NSMakeRange(offset,size)];
        line(@{@"event":@"frame",@"words":@[@1,@0,@0,@(DS_NATIVE_WIDTH),@(size/DS_NATIVE_WIDTH),@0],@"status":@0,@"data":[part base64EncodedStringWithOptions:0]});
        frames++;offset+=size;
    }
    line(@{@"event":@"frame",@"words":@[@3,@0,@0,@0,@0,@0],@"status":@0,@"data":@""});frames++;
    line(@{@"event":@"done",@"success":@YES,@"frames":@(frames),@"bytes":@(raw.length)});
    if(close(fd))success=NO;
    if(!success){unlink(path.fileSystemRepresentation);if(error)*error=[NSError errorWithDomain:@"DS720D.Output" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Impossible d’enregistrer la capture."}];return nil;}
    return path;
}

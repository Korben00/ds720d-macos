// SPDX-License-Identifier: MIT
#import "ServiceClient.h"
#import "ServiceIdentity.h"
#import <xpc/xpc.h>
#import "packet.h"
#include <fcntl.h>
#include <unistd.h>

static xpc_connection_t active;
static NSObject *lock;

static xpc_object_t request(BOOL capture,NSError **error) {
    static dispatch_once_t once;dispatch_once(&once,^{lock=[NSObject new];});
    xpc_connection_t connection=xpc_connection_create_mach_service(DS_SERVICE,NULL,XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);
    NSString *rule=ds_requirement(ds_signing_team(),YES);
    if(!rule || xpc_connection_set_peer_code_signing_requirement(connection,rule.UTF8String))return nil;
    xpc_connection_set_event_handler(connection,^(xpc_object_t event){(void)event;});
    @synchronized(lock){if(capture)active=connection;}
    xpc_connection_resume(connection);
    xpc_object_t message=xpc_dictionary_create(NULL,NULL,0);
    xpc_dictionary_set_string(message,"operation",capture?"capture":"ping");
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    __block xpc_object_t reply=nil;
    xpc_connection_send_message_with_reply(connection,message,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(xpc_object_t item){reply=item;dispatch_semaphore_signal(done);});
    BOOL timeout=dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,(capture?210:5)*NSEC_PER_SEC))!=0;
    @synchronized(lock){if(capture && active==connection)active=nil;}
    xpc_connection_cancel(connection);
    if(timeout || !reply || xpc_get_type(reply)!=XPC_TYPE_DICTIONARY || xpc_dictionary_get_string(reply,"error")) {
        const char *text=reply && xpc_get_type(reply)==XPC_TYPE_DICTIONARY?xpc_dictionary_get_string(reply,"error"):NULL;
        if(error)*error=[NSError errorWithDomain:@"DS720D.Service" code:1 userInfo:@{NSLocalizedDescriptionKey:text?@(text):@"Le service du pilote est indisponible. Installe le paquet DS-720D Scanner puis réessaie."}];
        return nil;
    }
    return reply;
}
NSData *ds_service_capture(NSError **error) {
    xpc_object_t reply=request(YES,error);if(!reply)return nil;
    size_t length=0;const void *bytes=xpc_dictionary_get_data(reply,"pixels",&length);
    if(!bytes || !length || length>80000000 || length%DS_NATIVE_BPL) {
        if(error)*error=[NSError errorWithDomain:@"DS720D.Service" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Invalid image from scanner service."}];return nil;
    }
    return [NSData dataWithBytes:bytes length:length];
}
BOOL ds_service_ping(NSError **error){return request(NO,error)!=nil;}
void ds_service_cancel(void) {
    if(!lock)return;
    @synchronized(lock){if(active){xpc_object_t message=xpc_dictionary_create(NULL,NULL,0);xpc_dictionary_set_string(message,"operation","cancel");xpc_connection_send_message(active,message);}}
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

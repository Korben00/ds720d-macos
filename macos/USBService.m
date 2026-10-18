// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import <xpc/xpc.h>
#import "ServiceIdentity.h"
#import "capture.h"
#include <stdatomic.h>
#include <unistd.h>

@interface DSJob : NSObject
@property(atomic) BOOL cancelled;
@end
@implementation DSJob
@end

static atomic_bool busy=false;
static dispatch_queue_t worker;
static SecRequirementRef requirement;

static BOOL authenticated(xpc_object_t message) {
    SecCodeRef sender=NULL;
    if(SecCodeCreateWithXPCMessage(message,kSecCSDefaultFlags,&sender)!=errSecSuccess)return NO;
    OSStatus status=SecCodeCheckValidity(sender,kSecCSStrictValidate,requirement);
    CFRelease(sender);return status==errSecSuccess;
}

static void replyError(xpc_connection_t peer,xpc_object_t message,const char *text) {
    xpc_object_t reply=xpc_dictionary_create_reply(message);
    if(!reply)return;
    xpc_dictionary_set_string(reply,"error",text);
    xpc_connection_send_message(peer,reply);
}

static void acceptPeer(xpc_connection_t peer) {
    DSJob *job=[DSJob new];
    xpc_connection_set_event_handler(peer,^(xpc_object_t message){@autoreleasepool {
        if(xpc_get_type(message)!=XPC_TYPE_DICTIONARY){job.cancelled=YES;return;}
        // Check the audit token on EVERY message, including after an exec().
        if(!authenticated(message)){xpc_connection_cancel(peer);job.cancelled=YES;return;}
        const char *operation=xpc_dictionary_get_string(message,"operation");
        if(!operation){replyError(peer,message,"Missing operation.");return;}
        if(!strcmp(operation,"ping") || !strcmp(operation,"cancel")) {
            if(!strcmp(operation,"cancel"))job.cancelled=YES;
            xpc_object_t reply=xpc_dictionary_create_reply(message);
            if(reply){xpc_dictionary_set_int64(reply,"protocol",1);xpc_connection_send_message(peer,reply);}
            return;
        }
        if(strcmp(operation,"capture")){replyError(peer,message,"Unsupported operation.");return;}
        bool expected=false;
        if(!atomic_compare_exchange_strong(&busy,&expected,true)){replyError(peer,message,"Scanner busy.");return;}
        xpc_object_t reply=xpc_dictionary_create_reply(message);
        if(!reply){atomic_store(&busy,false);return;}
        job.cancelled=NO;
        dispatch_async(worker,^{@autoreleasepool {
            NSMutableData *raw=[NSMutableData data];__block NSString *failure=nil;
            int status=ds_acquire(^(NSDictionary *item){
                if([item[@"event"] isEqual:@"frame"]) {
                    NSData *part=[[NSData alloc] initWithBase64EncodedString:item[@"data"] options:0];
                    if(!part || raw.length+part.length>80000000){failure=@"Image exceeds acquisition bounds.";job.cancelled=YES;}
                    else [raw appendData:part];
                } else if([item[@"event"] isEqual:@"error"])failure=item[@"message"];
            },^{return job.cancelled;});
            if(status || job.cancelled || failure)xpc_dictionary_set_string(reply,"error",(failure?:@"Acquisition interrupted.").UTF8String);
            else xpc_dictionary_set_data(reply,"pixels",raw.bytes,raw.length);
            // No filesystem writes, arbitrary commands, paths or USB RPCs.
            xpc_connection_send_message(peer,reply);
            atomic_store(&busy,false);
        }});
    }});
    xpc_connection_resume(peer);
}

int main(void) {
    @autoreleasepool {
        if(geteuid()!=0)return 77;
        NSString *rule=ds_requirement(ds_signing_team(),NO);
        if(!rule || SecRequirementCreateWithString((__bridge CFStringRef)rule,kSecCSDefaultFlags,&requirement))return 78;
        worker=dispatch_queue_create("info.korben.ds720d.acquisition",DISPATCH_QUEUE_SERIAL);
        xpc_connection_t listener=xpc_connection_create_mach_service(DS_SERVICE,NULL,XPC_CONNECTION_MACH_SERVICE_LISTENER);
        if(!listener)return 78;
        xpc_connection_set_event_handler(listener,^(xpc_object_t peer){
            if(xpc_get_type(peer)==XPC_TYPE_CONNECTION)acceptPeer(peer);
        });
        xpc_connection_resume(listener);dispatch_main();
    }
}

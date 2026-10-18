// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import <xpc/xpc.h>
#import <os/log.h>
#import "ServiceIdentity.h"
#import "usb.h"
#include <unistd.h>

@interface DSLease : NSObject
@end
@implementation DSLease
@end

static dispatch_queue_t worker;
static SecRequirementRef requirement;
// Only worker accesses owner. Keep the lease until disconnect or expiry so
// another client cannot reconfigure USB in the middle of an acquisition.
static DSLease *owner;

static BOOL authenticated(xpc_object_t message) {
    SecCodeRef sender=NULL;
    if(SecCodeCreateWithXPCMessage(message,kSecCSDefaultFlags,&sender)!=errSecSuccess)return NO;
    OSStatus status=SecCodeCheckValidity(sender,kSecCSStrictValidate,requirement);
    CFRelease(sender);return status==errSecSuccess;
}

static void replyError(xpc_connection_t peer,xpc_object_t message,const char *text) {
    xpc_object_t reply=xpc_dictionary_create_reply(message);
    if(!reply)return;
    xpc_dictionary_set_string(reply,"error",text);xpc_connection_send_message(peer,reply);
}

static void acceptPeer(xpc_connection_t peer) {
    DSLease *lease=[DSLease new];
    xpc_connection_set_event_handler(peer,^(xpc_object_t message){@autoreleasepool {
        if(xpc_get_type(message)!=XPC_TYPE_DICTIONARY){
            dispatch_async(worker,^{if(owner==lease)owner=nil;});return;
        }
        // Validate the audit token on EVERY message, including after exec().
        if(!authenticated(message)){xpc_connection_cancel(peer);return;}
        const char *operation=xpc_dictionary_get_string(message,"operation");
        if(!operation){replyError(peer,message,"Missing operation.");return;}
        if(!strcmp(operation,"ping")) {
            xpc_object_t reply=xpc_dictionary_create_reply(message);
            if(reply){xpc_dictionary_set_int64(reply,"protocol",2);xpc_connection_send_message(peer,reply);}return;
        }
        BOOL release=!strcmp(operation,"release");
        if(!release && strcmp(operation,"prepare")){replyError(peer,message,"Unsupported operation.");return;}
        xpc_object_t reply=xpc_dictionary_create_reply(message);if(!reply)return;
        dispatch_async(worker,^{@autoreleasepool {
            if(release){if(owner==lease)owner=nil;xpc_dictionary_set_bool(reply,"released",true);xpc_connection_send_message(peer,reply);return;}
            if(owner && owner!=lease){xpc_dictionary_set_string(reply,"error","Scanner busy.");xpc_connection_send_message(peer,reply);return;}
            BOOL existing=owner==lease;
            owner=lease;NSError *error=nil;
            if(!existing && ![DSUSB prepareScanner:&error]) {
                owner=nil;os_log_error(OS_LOG_DEFAULT,"DS720D preparation failed: %{public}@",error);
                xpc_dictionary_set_string(reply,"error",error.description.UTF8String?:"USB preparation failed.");
            } else {
                xpc_dictionary_set_bool(reply,"prepared",true);
                if(!existing)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,180*NSEC_PER_SEC),worker,^{
                    if(owner==lease){owner=nil;xpc_connection_cancel(peer);}
                });
            }
            // No interface open, scanner commands, image bytes, file access,
            // caller-controlled paths, addresses or executable code in root.
            xpc_connection_send_message(peer,reply);
        }});
    }});
    xpc_connection_resume(peer);
}

int main(void) {@autoreleasepool {
    if(geteuid()!=0)return 77;
    NSString *rule=ds_requirement(ds_signing_team(),NO);
    if(!rule || SecRequirementCreateWithString((__bridge CFStringRef)rule,kSecCSDefaultFlags,&requirement))return 78;
    worker=dispatch_queue_create("info.korben.ds720d.preparation",DISPATCH_QUEUE_SERIAL);
    xpc_connection_t listener=xpc_connection_create_mach_service(DS_SERVICE,NULL,XPC_CONNECTION_MACH_SERVICE_LISTENER);
    if(!listener)return 78;
    xpc_connection_set_event_handler(listener,^(xpc_object_t peer){if(xpc_get_type(peer)==XPC_TYPE_CONNECTION)acceptPeer(peer);});
    xpc_connection_resume(listener);dispatch_main();
}}

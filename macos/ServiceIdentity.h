// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import <Security/Security.h>

#define DS_SERVICE "info.korben.ds720d.usb"
#define DS_HELPER_ID "info.korben.ds720d.usb"

// The team is read from our own sealed signature, never from an IPC request.
static NSString *ds_signing_team(void) {
    SecCodeRef code=NULL;CFDictionaryRef info=NULL;
    if(SecCodeCopySelf(kSecCSDefaultFlags,&code)!=errSecSuccess)return nil;
    OSStatus status=SecCodeCopySigningInformation(code,kSecCSSigningInformation,&info);
    CFRelease(code);
    NSDictionary *dictionary=CFBridgingRelease(info);
    id team=dictionary[(__bridge NSString *)kSecCodeInfoTeamIdentifier];
    if(status || ![team isKindOfClass:NSString.class] || [team length]!=10)return nil;
    NSCharacterSet *invalid=[[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"] invertedSet];
    return [team rangeOfCharacterFromSet:invalid].location==NSNotFound?team:nil;
}

static NSString *ds_requirement(NSString *team,BOOL server) {
    if(!team)return nil;
    NSString *identity=server?@"identifier \"info.korben.ds720d.usb\"":
        @"(identifier \"info.korben.ds720d\" or identifier \"info.korben.ds720d.ica\" or identifier \"info.korben.ds720d.cli\")";
    return [NSString stringWithFormat:@"anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"%@\" and %@",team,identity];
}

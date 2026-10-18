// SPDX-License-Identifier: MIT
// Development-only, one-shot diagnostic authorization. No helper is installed.
#import "authorize.h"
#import <Foundation/Foundation.h>
#import <Security/Authorization.h>
#include <limits.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>

static int authorize(const char *executable, BOOL scan, BOOL inspect, NSString *destination) {
    char binary[PATH_MAX];
    if (!realpath(executable, binary)) return 1;
    AuthorizationRef authorization = NULL;
    OSStatus status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
        kAuthorizationFlagDefaults, &authorization);
    FILE *output = NULL;
    // Only one fixed diagnostic or one bounded duplex capture; no external commands.
    char *arguments[] = {scan ? "capture" : inspect ? "inspect" : "probe", NULL};
    FILE *capture=NULL;
    if(scan) {
        NSString *project=[[@(binary) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        NSString *directory=destination?:[project stringByAppendingPathComponent:@"captures"];
        NSError *error=nil;
        if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error])return 1;
        NSString *name=[NSString stringWithFormat:@"duplex-%.0f-%d.jsonl",NSDate.date.timeIntervalSince1970,getpid()];
        NSString *path=[directory stringByAppendingPathComponent:name];
        int fd=open(path.fileSystemRepresentation,O_CREAT|O_EXCL|O_WRONLY,0600);
        if(fd<0)return 1;
        capture=fdopen(fd,"w");
        if(!capture){close(fd);return 1;}
        printf("CAPTURE %s\n",path.fileSystemRepresentation);fflush(stdout);
        NSData *location=[NSJSONSerialization dataWithJSONObject:@{@"event":@"capture-file",@"path":path} options:0 error:NULL];
        fwrite(location.bytes,1,location.length,stdout);putchar('\n');fflush(stdout);
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (status == errAuthorizationSuccess)
        status = AuthorizationExecuteWithPrivileges(authorization, binary,
            kAuthorizationFlagDefaults, arguments, &output);
#pragma clang diagnostic pop
    BOOL success=NO;
    if (status != errAuthorizationSuccess)
        fprintf(stderr, "macOS diagnostic authorization failed (%d).\n", (int)status);
    else {
        char *line=NULL;size_t capacity=0;ssize_t n;
        while ((n = getline(&line,&capacity,output)) > 0) {
            if(capture) {
                fwrite(line,1,(size_t)n,capture);fflush(capture);
                NSData *data=[NSData dataWithBytes:line length:(NSUInteger)n];
                NSDictionary *entry=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                if([entry[@"event"] isEqual:@"frame"]) {
                    NSArray *w=entry[@"words"];
                    printf("FRAME state=%u componentBytes=%u componentRows=%u address=0x%08x status=%u\n",[w[0] unsignedIntValue],[w[3] unsignedIntValue],[w[4] unsignedIntValue],[w[5] unsignedIntValue],[entry[@"status"] unsignedIntValue]);
                }
                else {fwrite(line,1,(size_t)n,stdout);if([entry[@"event"] isEqual:@"done"])success=[entry[@"success"] boolValue];}
            } else {fwrite(line,1,(size_t)n,stdout);if(strstr(line,"Scanner identity: BROTHER DS-720D"))success=YES;}
            fflush(stdout);
        }
        free(line);
        fclose(output);
    }
    if(capture)fclose(capture);
    if (authorization) AuthorizationFree(authorization, kAuthorizationFlagDefaults);
    return status == errAuthorizationSuccess && success ? 0 : 1;
}

int ds_authorize_probe(const char *executable) { return authorize(executable,NO,NO,nil); }
int ds_authorize_scan(const char *executable) { return authorize(executable,YES,NO,nil); }
int ds_authorize_scan_to(const char *executable,const char *directory) {
    NSString *path=[[NSString alloc] initWithUTF8String:directory];
    if(!path.isAbsolutePath){fprintf(stderr,"Capture directory must be an absolute path.\n");return 64;}
    return authorize(executable,YES,NO,path);
}
int ds_authorize_inspect(const char *executable) { return authorize(executable,NO,YES,nil); }

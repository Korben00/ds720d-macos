// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import "capture.h"
#import "usb.h"
#import "bridge.h"
#import "packet.h"
#include <unistd.h>

static void event(NSDictionary *object) {
    NSData *json=[NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
    fwrite(json.bytes,1,json.length,stdout);putchar('\n');fflush(stdout);
}

static NSData *command(uint8_t opcode) {
    uint8_t bytes[10]={opcode};return [NSData dataWithBytes:bytes length:10];
}

static NSData *nativeWindow(void) {
    uint8_t bytes[79];
    ds_native_window(bytes);
    return [NSData dataWithBytes:bytes length:sizeof bytes];
}

int ds_inspect(void) {
    alarm(90);
    setvbuf(stdout,NULL,_IOLBF,0);
    NSError *error=nil;
    DSUSB *usb=[DSUSB openScanner:&error];
    if(!usb){fprintf(stderr,"%s\n",error.description.UTF8String);return 1;}
    DSBridge *bridge=[[DSBridge alloc] initWithTransport:usb];
    if(![bridge identifyTransport:&error]){fprintf(stderr,"%s\n",error.description.UTF8String);[usb close];return 1;}
    NSData *identity=[bridge inquiry:&error];
    if(identity.length<36 || memcmp((const uint8_t *)identity.bytes+8,"BROTHER DS-720D",14)) {[usb close];return 1;}
    printf("Scanner identity: BROTHER DS-720D\n");
    for(NSUInteger i=0;i<identity.length;i++)printf("%02x%s",((const uint8_t *)identity.bytes)[i],(i+1)%16?" ":"\n");puts("");
    NSData *ready=[bridge scannerCommand:command(0) inputLength:0 output:nil error:&error];
    printf("Test unit ready: %s\n",ready?"accepted":error.description.UTF8String);
    NSData *light=[bridge prepareLight:&error];
    printf("Illumination before preparation: %s\n",light?light.description.UTF8String:error.description.UTF8String);
    uint8_t format[10]={0x28,0,0x60,0,0x0a,0x0d,0,0,32,0};
    NSData *calibration=[bridge scannerCommand:[NSData dataWithBytes:format length:10] inputLength:32 output:nil error:&error];
    printf("Calibration format: ");
    if(calibration)for(NSUInteger i=0;i<calibration.length;i++)printf("%02x ",((const uint8_t *)calibration.bytes)[i]);
    else printf("%s",error.description.UTF8String);
    puts("");
    NSDictionary *memory=[bridge imageMemoryDiagnostic:&error];
    printf("Image ring without service lock: %s\n",memory?memory.description.UTF8String:error.description.UTF8String);
    printf("Retained image metadata: %s\n",[[bridge imageMetadata:&error] description].UTF8String);
    uint8_t sense[10]={3,0,0,0,22};
    NSData *before=[bridge scannerCommand:[NSData dataWithBytes:sense length:10] inputLength:22 output:nil error:&error];
    printf("Sense before set window: %s\n",before?before.description.UTF8String:error.description.UTF8String);
    [usb close];return before?0:1;
}

int ds_capture(void) {
    alarm(180);
    NSError *error=nil;
    DSUSB *usb=[DSUSB openScanner:&error];
    if(!usb){event(@{@"event":@"error",@"message":error.description});return 1;}
    DSBridge *bridge=[[DSBridge alloc] initWithTransport:usb];
    if(![bridge identifyTransport:&error]){event(@{@"event":@"error",@"message":error.description});[usb close];return 1;}
    NSData *identity=[bridge inquiry:&error];
    if(!identity || identity.length<36 || memcmp((const uint8_t *)identity.bytes+8,"BROTHER ",8) ||
        memcmp((const uint8_t *)identity.bytes+16,"DS-720D",7)) {
        event(@{@"event":@"error",@"message":error.description?:@"Unexpected scanner identity."});[usb close];return 1;
    }
    BOOL reserved=NO,started=NO,success=NO;
    NSUInteger frames=0,total=0;
    @try {
        if(![bridge scannerCommand:command(0) inputLength:0 output:nil error:&error])return 1;
        NSData *light=[bridge prepareLight:&error];
        if(!light)return 1;
        event(@{@"event":@"illumination",@"previous":[light description]});
        uint8_t format[10]={0x28,0,0x60,0,0x0a,0x0d,0,0,32,0};
        NSData *calibration=[bridge scannerCommand:[NSData dataWithBytes:format length:10] inputLength:32 output:nil error:&error];
        if(!calibration)return 1;
        if((((const uint8_t *)calibration.bytes)[4]&3)!=3) {
            error=[NSError errorWithDomain:@"DS720D.Capture" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Scanner requires calibration; capture was not started."}];return 1;
        }
        NSData *window=nativeWindow();
        uint8_t setup[10]={0x24};setup[8]=(uint8_t)window.length;
        if(![bridge scannerCommand:[NSData dataWithBytes:setup length:10] inputLength:0 output:window error:&error])return 1;
        // This model's memory acquisition path uses host-side color processing.
        event(@{@"event":@"configured",@"dpi":@(DS_NATIVE_DPI),@"bytesPerLine":@(DS_NATIVE_BPL),@"channels":@3,@"stripeRows":@(DS_STRIPE_ROWS),@"imagePath":@"memory",@"layout":@"line-planar-rgb"});
        if(![bridge scannerCommand:command(0x16) inputLength:0 output:nil error:&error])return 1;
        reserved=YES;
        uint8_t start[10]={0x1b,0,0,0,0,0xc0};
        if(![bridge scannerCommand:[NSData dataWithBytes:start length:10] inputLength:0 output:nil error:&error])return 1;
        started=YES;
        NSTimeInterval deadline=NSProcessInfo.processInfo.systemUptime+120;
        while(frames<256 && total<80000000 && NSProcessInfo.processInfo.systemUptime<deadline) {
            @autoreleasepool {
                uint8_t read[10]={0x28,0,0,0,0x0a,0x0d};
                uint32_t amount=DS_NATIVE_BPL*DS_STRIPE_ROWS;
                read[6]=(uint8_t)(amount>>16);read[7]=(uint8_t)(amount>>8);read[8]=(uint8_t)amount;
                NSDictionary *block=[bridge imageBlock:[NSData dataWithBytes:read length:10] error:&error];
                if(!block)break;
                NSData *data=block[@"data"];
                uint32_t status=[block[@"status"] unsignedIntValue];
                NSArray *words=block[@"words"];
                BOOL end=[words[0] unsignedIntValue]==3;
                total+=data.length;frames++;
                event(@{@"event":@"frame",@"words":words,@"status":@(status),@"data":[data base64EncodedStringWithOptions:0]});
                if(status && !end) {
                    error=[NSError errorWithDomain:@"DS720D.Capture" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Scanner image read returned an error status."}];break;
                }
                if(end){success=total>0;break;}
            }
        }
        if(!success && !error)error=[NSError errorWithDomain:@"DS720D.Capture" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Capture reached its safety limit before the scanner reported end of page."}];
    } @finally {
        NSError *cleanup=nil;
        if(error) {
            uint8_t request[10]={3,0,0,0,22};
            NSData *sense=[bridge scannerCommand:[NSData dataWithBytes:request length:10] inputLength:22 output:nil error:&cleanup];
            if(sense)event(@{@"event":@"sense",@"bytes":[sense description]});
        }
        if(started)[bridge scannerCommand:command(0x1b) inputLength:0 output:nil error:&cleanup];
        if(reserved)[bridge scannerCommand:command(0x17) inputLength:0 output:nil error:&cleanup];
        [usb close];
        if(error)event(@{@"event":@"error",@"message":error.description});
        event(@{@"event":@"done",@"success":@(success),@"frames":@(frames),@"bytes":@(total)});
    }
    return success?0:1;
}


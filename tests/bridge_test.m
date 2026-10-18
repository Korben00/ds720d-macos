// SPDX-License-Identifier: MIT
#import "bridge.h"
#import "packet.h"
#include <assert.h>

// A small firmware emulator enforces the transaction boundaries independently of
// the client. It returns synthetic device data; it cannot exercise real hardware.
@interface Firmware : NSObject <DSCommandTransport>
@property BOOL locked;
@property BOOL busy;
@property BOOL malformed;
@property uint32_t status;
@property unsigned claims;
@property unsigned releases;
@property NSUInteger requested;
@property NSUInteger stagedLength;
@property uint8_t stagedChannel;
@property uint32_t imageWidth;
@property uint32_t imageRows;
@property uint32_t imageState;
@property uint32_t imageAddress;
@property unsigned memoryReads;
@end

@implementation Firmware
- (NSData *)executeCDB:(NSData *)cdb inputLength:(NSUInteger)read output:(NSData *)output error:(NSError **)error {
    (void)error;
    assert(cdb.length == 16);
    const uint8_t *b = cdb.bytes;
    if(b[0]==0xc3) {
        assert(!self.locked && cdb.length==16 && read<=65536 && !output);
        uint32_t address=((uint32_t)b[2]<<24)|((uint32_t)b[3]<<16)|((uint32_t)b[4]<<8)|b[5];
        assert(address>=self.imageAddress);
        NSMutableData *image=[NSMutableData dataWithLength:read];
        uint8_t *pixels=image.mutableBytes;
        for(NSUInteger i=0;i<read;i++)pixels[i]=(uint8_t)((address-self.imageAddress+i)%251);
        self.memoryReads++;
        return image;
    }
    assert(b[0] == 0xc5 && b[1] == 7);
    uint32_t length = ((uint32_t)b[6] << 24) | ((uint32_t)b[7] << 16) | ((uint32_t)b[8] << 8) | b[9];
    assert(length == (read ? read : output.length));
    if (b[10] == 0xff) {
        assert(read == 16 && output == nil);
        NSMutableData *reply = [NSMutableData dataWithLength:16];
        uint8_t *out = reply.mutableBytes;
        out[0] = self.malformed ? 15 : 16;
        switch (b[11]) {
            case 3: out[8] = self.locked; break;
            case 4: out[8] = !self.busy; break;
            case 5: assert(!self.locked); self.locked = YES; self.claims++; out[8] = 1; break;
            case 6: assert(self.locked); self.locked = NO; self.releases++; out[8] = 1; break;
            default: assert(!"Unknown service request");
        }
        return reply;
    }
    assert(b[10] == 2 && self.locked);
    if (b[11] == 3) {
        assert(!read && output.length == 10);
        const uint8_t *cmd = output.bytes;
        assert(cmd[0] == 0x12 || cmd[0]==0x28);
        self.requested = cmd[0]==0x12?cmd[4]:((NSUInteger)cmd[6]<<16)|((NSUInteger)cmd[7]<<8)|cmd[8];
        return [NSData data];
    }
    assert(read > 0 && !output);
    NSMutableData *reply = [NSMutableData dataWithLength:read];
    if (b[11] == 1) {
        self.stagedChannel = b[12]; self.stagedLength = read;
        return reply;
    }
    assert(b[11] == 2 && b[12] == self.stagedChannel && read == self.stagedLength);
    uint8_t *out = reply.mutableBytes;
    if (b[12] == 1) {
        assert(read == 4);
        for (unsigned i = 0; i < 4; i++) out[i] = (uint8_t)(self.status >> (i * 8));
    } else if(b[12]==2) {
        assert(read==24);
        uint32_t words[]={self.imageState,0,0,self.imageWidth,self.imageRows,self.imageAddress};
        for(unsigned w=0;w<6;w++)for(unsigned i=0;i<4;i++)out[4*w+i]=(uint8_t)(words[w]>>(i*8));
    } else {
        assert(b[12] == 0 && read == self.requested);
        out[0] = 6; out[4] = 160;
        if (read >= 36) memcpy(out + 8, "BROTHER DS-720D         0.27", 27);
    }
    return reply;
}
@end

int main(void) {
    @autoreleasepool {
        Firmware *firmware = [Firmware new];
        DSBridge *bridge = [[DSBridge alloc] initWithTransport:firmware];
        NSError *error = nil;
        NSData *identity = [bridge inquiry:&error];
        assert(identity.length == 165 && error == nil);
        assert(!memcmp((const uint8_t *)identity.bytes + 8, "BROTHER", 7));
        assert(firmware.claims == 6 && firmware.releases == 6 && !firmware.locked);

        firmware.status = 0x1234;
        assert([bridge inquiry:&error] == nil && error.code == 0x1234);
        assert(firmware.claims == firmware.releases && !firmware.locked);
        firmware.status = 0; error = nil;

        firmware.locked = YES;
        unsigned claims = firmware.claims, releases = firmware.releases;
        assert([bridge inquiry:&error] == nil && error.code == 4);
        assert(firmware.claims == claims && firmware.releases == releases && firmware.locked);
        assert([bridge inquiry:NULL] == nil);
        firmware.locked = NO; error = nil;

        firmware.malformed = YES;
        assert([bridge inquiry:&error] == nil && error.code == 2);
        assert(firmware.claims == claims && firmware.releases == releases);
        firmware.malformed = NO; error = nil;

        firmware.busy = YES;
        bridge.readyTimeout = 0.02;
        NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
        assert([bridge inquiry:&error] == nil && error.code == 3);
        assert(NSProcessInfo.processInfo.systemUptime - start < 0.5);
        assert(firmware.claims == claims);

        uint8_t oversized[11] = {0};
        error = nil;
        assert([bridge scannerCommand:[NSData dataWithBytes:oversized length:11] inputLength:0 output:nil error:&error] == nil);
        assert(error.code == 7 && firmware.claims == claims);
        Firmware *images=[Firmware new];
        images.imageWidth=1700;images.imageRows=160;images.imageState=1;images.imageAddress=0x10000000;
        DSBridge *imageBridge=[[DSBridge alloc] initWithTransport:images];
        uint8_t readCommand[]={0x28,0,0,0,0x0a,0x0d,4,0x26,0x80,0};
        NSData *read=[NSData dataWithBytes:readCommand length:10];
        error=nil;
        NSDictionary *block=[imageBridge imageBlock:read error:&error];
        NSData *pixels=block[@"data"];
        assert(pixels.length==272000 && error==nil && images.memoryReads==5);
        const uint8_t *p=pixels.bytes;
        for(NSUInteger i=0;i<pixels.length;i++)assert(p[i]==i%251);
        assert(!images.locked && images.claims==images.releases);
        images.imageRows=161;error=nil;
        assert([imageBridge imageBlock:read error:&error]==nil && error.code==13);
        assert(images.memoryReads==5 && !images.locked);
        images.imageRows=160;images.imageAddress=UINT32_MAX-3;error=nil;
        assert([imageBridge imageBlock:read error:&error]==nil && error.code==9);
        assert(images.memoryReads==5 && !images.locked);
        images.imageRows=0;images.imageState=3;images.imageAddress=0;error=nil;
        assert([imageBridge imageBlock:read error:&error]!=nil && images.memoryReads==5);
        puts("Bridge state machine: all checks passed (synthetic firmware).");
    }
    return 0;
}

// SPDX-License-Identifier: MIT
#import "bridge.h"
#import "packet.h"

static NSError *bridgeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"DS720D.Bridge" code:code
        userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setError(NSError **target, NSError *value) {
    if (target) *target = value;
}

@implementation DSBridge {
    id<DSCommandTransport> _transport;
}

- (instancetype)initWithTransport:(id<DSCommandTransport>)transport {
    if ((self = [super init])) { _transport = transport; _readyTimeout = 5; }
    return self;
}

- (NSData *)exchangeGroup:(uint8_t)group action:(uint8_t)action channel:(uint8_t)channel
                    read:(NSUInteger)read output:(NSData *)output error:(NSError **)error {
    if(self.cancelled && self.cancelled()) {
        setError(error,bridgeError(16,@"Acquisition cancelled or timed out."));return nil;
    }
    uint8_t cdb[16];
    ds_novatek_cdb(cdb, group, action, channel, (uint32_t)(read ? read : output.length));
    NSData *reply = [_transport executeCDB:[NSData dataWithBytes:cdb length:16]
        inputLength:read output:output error:error];
    if (reply && read && reply.length != read) {
        setError(error, bridgeError(1, @"Truncated bridge response.")); return nil;
    }
    return reply;
}

- (BOOL)service:(uint8_t)action value:(BOOL *)value error:(NSError **)error {
    NSData *reply = [self exchangeGroup:0xff action:action channel:0 read:16 output:nil error:error];
    if (!reply) return NO;
    const uint8_t *bytes = reply.bytes;
    if (ds_read_le32(bytes) != 16) {
        setError(error, bridgeError(2, @"Invalid bridge service reply size.")); return NO;
    }
    *value = ds_read_le32(bytes + 8) != 0;
    return YES;
}

- (BOOL)waitReady:(NSError **)error {
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + self.readyTimeout;
    do {
        BOOL ready = NO;
        if (![self service:4 value:&ready error:error]) return NO;
        if (ready) return YES;
        [NSThread sleepForTimeInterval:0.01];
    } while (NSProcessInfo.processInfo.systemUptime < deadline);
    setError(error, bridgeError(3, @"Timed out waiting for the scanner bridge."));
    return NO;
}

- (BOOL)claim:(NSError **)error {
    BOOL value = NO;
    if (![self waitReady:error] || ![self service:3 value:&value error:error]) return NO;
    if (value) { setError(error, bridgeError(4, @"Scanner firmware is already locked.")); return NO; }
    if (![self service:5 value:&value error:error]) return NO;
    if (!value) { setError(error, bridgeError(5, @"Scanner firmware refused its transaction lock.")); return NO; }
    return YES;
}

- (BOOL)releaseClaim:(NSError **)error {
    BOOL (^cancelled)(void)=self.cancelled;
    self.cancelled=nil;
    BOOL value = NO;
    BOOL success=[self waitReady:error] && [self service:6 value:&value error:error];
    self.cancelled=cancelled;
    if(!success)return NO;
    if (!value) { setError(error, bridgeError(6, @"Scanner firmware refused to release its transaction lock.")); return NO; }
    return YES;
}

- (BOOL)writeChannel:(uint8_t)channel data:(NSData *)data error:(NSError **)error {
    if (![self claim:error]) return NO;
    NSData *result = [self exchangeGroup:2 action:3 channel:channel read:0 output:data error:error];
    NSError *releaseError = nil;
    BOOL released = [self releaseClaim:&releaseError];
    if (!result) return NO;
    if (!released) { setError(error, releaseError); return NO; }
    return YES;
}

- (NSData *)readChannel:(uint8_t)channel length:(NSUInteger)length error:(NSError **)error {
    if (![self claim:error]) return nil;
    NSData *setup = [self exchangeGroup:2 action:1 channel:channel read:length output:nil error:error];
    NSData *result = setup && [self waitReady:error]
        ? [self exchangeGroup:2 action:2 channel:channel read:length output:nil error:error] : nil;
    NSError *releaseError = nil;
    BOOL released = [self releaseClaim:&releaseError];
    if (!result) return nil;
    if (!released) { setError(error, releaseError); return nil; }
    return result;
}

- (NSDictionary *)scannerResponse:(NSData *)command inputLength:(NSUInteger)inputLength
                    output:(NSData *)output error:(NSError **)error {
    if (command.length != 10 || inputLength > 65536 || output.length > 65526 ||
        (inputLength && output.length)) {
        setError(error, bridgeError(7, @"Invalid scanner command or transfer length.")); return nil;
    }
    NSMutableData *packet = [command mutableCopy];
    if (output.length) [packet appendData:output];
    if (![self writeChannel:0 data:packet error:error]) return nil;
    NSData *reply = inputLength ? [self readChannel:0 length:inputLength error:error] : [NSData data];
    if (!reply) return nil;
    NSData *status = [self readChannel:1 length:4 error:error];
    if (!status) return nil;
    return @{@"data":reply,@"status":@(ds_read_le32(status.bytes))};
}

- (NSData *)scannerCommand:(NSData *)command inputLength:(NSUInteger)inputLength
                    output:(NSData *)output error:(NSError **)error {
    NSDictionary *response=[self scannerResponse:command inputLength:inputLength output:output error:error];
    if(!response)return nil;
    uint32_t code=[response[@"status"] unsignedIntValue];
    if (code && ((const uint8_t *)command.bytes)[0]!=0x03) {
        setError(error, bridgeError(code, [NSString stringWithFormat:@"Scanner command returned status 0x%08x.", code]));
        return nil;
    }
    return response[@"data"];
}

- (BOOL)identifyTransport:(NSError **)error {
    NSData *magic=[self exchangeGroup:0xff action:2 channel:0 read:4 output:nil error:error];
    if(!magic)return NO;
    NSData *vendor=[self readChannel:3 length:2 error:error];
    NSData *product=vendor?[self readChannel:4 length:2 error:error]:nil;
    const uint8_t expectedVendor[]={0x04,0xf9},expectedProduct[]={0x60,0xe2};
    if(!product)return NO;
    if(memcmp(magic.bytes,"NOVA",4) || memcmp(vendor.bytes,expectedVendor,2) || memcmp(product.bytes,expectedProduct,2)) {
        setError(error,bridgeError(14,@"Unexpected scanner bridge identity."));return NO;
    }
    return YES;
}

- (NSData *)prepareLight:(NSError **)error {
    uint8_t read[10]={0x28,0,0xa0,0,0x0a,0x0d,0,0,2,0};
    NSData *state=[self scannerCommand:[NSData dataWithBytes:read length:10] inputLength:2 output:nil error:error];
    if(!state)return nil;
    if(((const uint8_t *)state.bytes)[0]==0) {
        uint8_t send[10]={0x2a,0,0xa0,0,0,0,0,0,1,0},on=1;
        if(![self scannerCommand:[NSData dataWithBytes:send length:10] inputLength:0 output:[NSData dataWithBytes:&on length:1] error:error])return nil;
    } else if(((const uint8_t *)state.bytes)[0]!=1) {
        setError(error,bridgeError(15,@"Scanner illumination is not ready."));return nil;
    }
    return state;
}

- (NSData *)inquiry:(NSError **)error {
    uint8_t command[10] = {0x12, 0, 0, 0, 5, 0, 0, 0, 0, 0};
    NSData *header = [self scannerCommand:[NSData dataWithBytes:command length:10] inputLength:5 output:nil error:error];
    if (!header) return nil;
    const uint8_t *bytes = header.bytes;
    NSUInteger size = MIN((NSUInteger)bytes[4] + 5, (NSUInteger)255);
    if (size < 36) { setError(error, bridgeError(8, @"Scanner inquiry is too short to identify the device.")); return nil; }
    command[4] = (uint8_t)size;
    return [self scannerCommand:[NSData dataWithBytes:command length:10] inputLength:size output:nil error:error];
}

- (NSData *)readImageMemory:(uint32_t)address length:(uint32_t)length error:(NSError **)error {
    if (!length) return [NSData data];
    if ((address & 3) || (length & 3) || address > UINT32_MAX - length || length > 1048576) {
        setError(error, bridgeError(9, @"Invalid image buffer address, alignment or length.")); return nil;
    }
    NSMutableData *result = [NSMutableData dataWithCapacity:length];
    BOOL success = YES;
    for (uint32_t offset=0; offset<length;) {
        if(self.cancelled && self.cancelled()) {
            setError(error,bridgeError(16,@"Acquisition cancelled or timed out."));return nil;
        }
        uint32_t chunk = MIN(65536u, length-offset);
        uint8_t cdb[16] = {0xc3,7};
        ds_write_be32(cdb+2,address+offset); ds_write_be32(cdb+6,chunk);
        NSData *data = [_transport executeCDB:[NSData dataWithBytes:cdb length:16]
            inputLength:chunk output:nil error:error];
        if (!data || data.length!=chunk) { success=NO; break; }
        [result appendData:data]; offset+=chunk;
    }
    if (!success) { if(!error || !*error)setError(error,bridgeError(10,@"Short image memory transfer.")); return nil; }
    return result;
}

- (NSDictionary *)imageMemoryDiagnostic:(NSError **)error {
    // Read only the already-observed image ring; return counts, never document pixels.
    NSData *data=[self readImageMemory:0x42e200 length:2592*80 error:error];
    if(!data)return nil;
    const uint8_t *p=data.bytes;
    NSMutableArray *rows=[NSMutableArray array];NSUInteger nonzero=0;
    for(unsigned y=0;y<80;y++) {
        NSUInteger count=0;
        for(unsigned x=0;x<2592;x++)count+=p[y*2592+x]!=0;
        nonzero+=count;[rows addObject:@(count)];
    }
    return @{@"nonzero":@(nonzero),@"rows":rows};
}

- (NSArray *)imageMetadata:(NSError **)error {
    NSData *data=[self readChannel:2 length:24 error:error];
    if(!data)return nil;
    const uint8_t *p=data.bytes;
    NSMutableArray *words=[NSMutableArray array];
    for(unsigned i=0;i<6;i++)[words addObject:@(ds_read_le32(p+4*i))];
    return words;
}

- (NSDictionary *)imageBlock:(NSData *)command error:(NSError **)error {
    if (command.length!=10 || ((const uint8_t *)command.bytes)[0]!=0x28) {
        setError(error,bridgeError(11,@"Invalid image read command.")); return nil;
    }
    if (![self writeChannel:0 data:command error:error]) return nil;
    NSTimeInterval deadline=NSProcessInfo.processInfo.systemUptime+15;
    NSData *metadata=nil;
    uint32_t words[6]={0};
    do {
        metadata=[self readChannel:2 length:24 error:error];
        if(!metadata)return nil;
        const uint8_t *p=metadata.bytes;
        for(unsigned i=0;i<6;i++)words[i]=ds_read_le32(p+4*i);
        if(words[0]!=0 && !(words[0]==1 && words[5]==0))break;
        [NSThread sleepForTimeInterval:0.01];
    } while(NSProcessInfo.processInfo.systemUptime<deadline);
    if(words[0]!=1 && words[0]!=3) {
        setError(error,bridgeError(12,[NSString stringWithFormat:@"Image metadata state %u (%u, %u).",words[0],words[1],words[2]]));return nil;
    }
    uint64_t length=(uint64_t)words[3]*words[4];
    const uint8_t *cmd=command.bytes;
    uint32_t requested=((uint32_t)cmd[6]<<16)|((uint32_t)cmd[7]<<8)|cmd[8];
    if(length>1048576 || length>requested || words[3]>10000 || words[4]>10000 || (!length && words[0]!=3)) {
        setError(error,bridgeError(13,@"Image block dimensions exceed the capture bounds."));return nil;
    }
    NSData *data=[self readImageMemory:words[5] length:(uint32_t)length error:error];
    if(!data)return nil;
    NSData *status=[self readChannel:1 length:4 error:error];
    if(!status)return nil;
    NSMutableArray *values=[NSMutableArray array];
    for(unsigned i=0;i<6;i++)[values addObject:@(words[i])];
    return @{@"words":values,@"data":data,@"status":@(ds_read_le32(status.bytes))};
}
@end

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
    BOOL value = NO;
    if (![self waitReady:error] || ![self service:6 value:&value error:error]) return NO;
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

- (NSData *)scannerCommand:(NSData *)command inputLength:(NSUInteger)inputLength
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
    uint32_t code = ds_read_le32(status.bytes);
    if (code) {
        setError(error, bridgeError(code, [NSString stringWithFormat:@"Scanner command returned status 0x%08x.", code]));
        return nil;
    }
    return reply;
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
@end

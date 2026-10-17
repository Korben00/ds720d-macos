// SPDX-License-Identifier: MIT
#import "transport.h"

NS_ASSUME_NONNULL_BEGIN
@interface DSBridge : NSObject
- (instancetype)initWithTransport:(id<DSCommandTransport>)transport;
@property NSTimeInterval readyTimeout;
- (nullable NSData *)scannerCommand:(NSData *)command inputLength:(NSUInteger)inputLength
                             output:(nullable NSData *)output error:(NSError * _Nullable * _Nullable)error;
- (nullable NSData *)inquiry:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END

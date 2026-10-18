// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import "transport.h"

NS_ASSUME_NONNULL_BEGIN
@interface DSUSB : NSObject <DSCommandTransport>
// Root-only capture/configure/surrender. No interface open or scanner command.
+ (BOOL)prepareScanner:(NSError * _Nullable * _Nullable)error;
+ (nullable instancetype)openScanner:(NSError * _Nullable * _Nullable)error;
- (nullable NSData *)executeCDB:(NSData *)cdb inputLength:(NSUInteger)inputLength
                        output:(nullable NSData *)output error:(NSError * _Nullable * _Nullable)error;
- (void)close;
@end
NS_ASSUME_NONNULL_END

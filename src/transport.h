// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@protocol DSCommandTransport <NSObject>
- (nullable NSData *)executeCDB:(NSData *)cdb inputLength:(NSUInteger)inputLength
                        output:(nullable NSData *)output error:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END

// SPDX-License-Identifier: MIT
#ifdef __OBJC__
#import <Foundation/Foundation.h>
// Fixed 300 dpi duplex acquisition. No caller-provided USB commands or paths.
int ds_acquire(void (^sink)(NSDictionary *), BOOL (^cancelled)(void));
#endif
int ds_capture(void);
int ds_inspect(void);
int ds_decode_capture(const char *path);
int ds_decode_capture_raw(const char *path);

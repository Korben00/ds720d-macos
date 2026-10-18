// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>

// Blocks on a private reply queue, never call on the UI thread.
NSData *ds_service_capture(NSError **error);
BOOL ds_service_ping(NSError **error);
void ds_service_cancel(void);
// Runs as the user and creates a new private JSONL capture in a chosen folder.
NSURL *ds_service_capture_file(NSURL *folder,NSError **error);

// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>

// Holds an authenticated preparation lease, then acquires pixels as the user.
// Blocks; never call on the UI thread.
NSData *ds_service_capture(NSError **error);
BOOL ds_service_ping(NSError **error);
// Prepares through the service, then opens/closes pipes as the user. No CDB.
BOOL ds_service_probe(NSError **error);
void ds_service_cancel(void);
// Runs as the user and creates a new private JSONL capture in a chosen folder.
NSURL *ds_service_capture_file(NSURL *folder,NSError **error);

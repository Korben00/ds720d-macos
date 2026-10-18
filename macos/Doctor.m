// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import <ImageCaptureCore/ImageCaptureCore.h>
#import "ServiceClient.h"

@interface Doctor : NSObject <ICDeviceBrowserDelegate,ICScannerDeviceDelegate>
@property BOOL done;
@property BOOL success;
@property ICScannerDevice *scanner;
@end
@implementation Doctor
- (void)deviceBrowser:(ICDeviceBrowser *)browser didAddDevice:(ICDevice *)device moreComing:(BOOL)more {
    (void)browser;(void)more;
    if(device.usbVendorID!=0x04f9 || device.usbProductID!=0x60e2)return;
    printf("Image Capture device: %s; module: %s\n",device.name.UTF8String,device.modulePath.UTF8String?:"(none)");
    if(![device isKindOfClass:ICScannerDevice.class])return;
    self.scanner=(ICScannerDevice *)device;device.delegate=self;[device requestOpenSession];
}
- (void)deviceBrowser:(ICDeviceBrowser *)browser didRemoveDevice:(ICDevice *)device moreGoing:(BOOL)more {(void)browser;(void)device;(void)more;}
- (void)didRemoveDevice:(ICDevice *)device {(void)device;self.done=YES;}
- (void)device:(ICDevice *)device didOpenSessionWithError:(NSError *)error {
    if(error){fprintf(stderr,"Open session: %s\n",error.localizedDescription.UTF8String);self.done=YES;return;}
    [(ICScannerDevice *)device requestSelectFunctionalUnit:ICScannerFunctionalUnitTypeDocumentFeeder];
}
- (void)scannerDevice:(ICScannerDevice *)scanner didSelectFunctionalUnit:(ICScannerFunctionalUnit *)unit error:(NSError *)error {
    if(error)fprintf(stderr,"Select feeder: %s\n",error.localizedDescription.UTF8String);
    else {
        printf("Feeder: native %ldx%ld dpi; resolutions: %s; duplex: %s\n",(long)unit.nativeXResolution,(long)unit.nativeYResolution,unit.supportedResolutions.description.UTF8String,[(ICScannerFunctionalUnitDocumentFeeder *)unit supportsDuplexScanning]?"yes":"no");
        self.success=unit.type==ICScannerFunctionalUnitTypeDocumentFeeder && [unit.supportedResolutions containsIndex:300];
    }
    [scanner requestCloseSession];
}
- (void)device:(ICDevice *)device didCloseSessionWithError:(NSError *)error {(void)device;if(error)self.success=NO;self.done=YES;}
@end
int main(void){@autoreleasepool{
    NSError *error=nil;
    BOOL service=ds_service_ping(&error);
    printf("Signed USB service: %s\n",service?"ready":error.localizedDescription.UTF8String?:"unavailable");
    Doctor *doctor=[Doctor new];ICDeviceBrowser *browser=[ICDeviceBrowser new];
    browser.delegate=doctor;browser.browsedDeviceTypeMask=ICDeviceTypeMaskScanner|ICDeviceLocationTypeMaskLocal;[browser start];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:15];
    while(!doctor.done && [deadline timeIntervalSinceNow]>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
    if(doctor.scanner.hasOpenSession)[doctor.scanner requestCloseSession];[browser stop];
    if(!doctor.success)fprintf(stderr,"No working DS-720D ICA feeder found. Install the package, close other scan apps and reconnect USB.\n");
    // This diagnostic never requests a scan or sends USB commands.
    return doctor.success && service?0:1;
}}

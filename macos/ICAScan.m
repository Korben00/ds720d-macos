// SPDX-License-Identifier: MIT
// Hardware integration test client. Only the explicit `scan OUTPUT_DIR` command
// starts paper transport. It uses ImageCaptureCore, like a macOS scan application.
#import <Foundation/Foundation.h>
#import <ImageCaptureCore/ImageCaptureCore.h>
#include <unistd.h>

@interface ICATestScan : NSObject <ICDeviceBrowserDelegate,ICScannerDeviceDelegate>
@property ICScannerDevice *scanner;
@property NSURL *folder;
@property NSMutableArray<NSURL *> *images;
@property BOOL ready,requested,completed,closed;
@property NSError *failure;
@end
@implementation ICATestScan
- (void)deviceBrowser:(ICDeviceBrowser *)browser didAddDevice:(ICDevice *)device moreComing:(BOOL)more {
    (void)browser;(void)more;
    if(device.usbVendorID!=0x04f9 || device.usbProductID!=0x60e2 || ![device isKindOfClass:ICScannerDevice.class])return;
    self.scanner=(ICScannerDevice *)device;device.delegate=self;[device requestOpenSession];
}
- (void)deviceBrowser:(ICDeviceBrowser *)browser didRemoveDevice:(ICDevice *)device moreGoing:(BOOL)more {(void)browser;(void)more;if(device==self.scanner)self.closed=YES;}
- (void)didRemoveDevice:(ICDevice *)device {(void)device;self.closed=YES;}
- (void)device:(ICDevice *)device didOpenSessionWithError:(NSError *)error {(void)device;if(error){self.failure=error;self.closed=YES;}}
- (void)deviceDidBecomeReady:(ICDevice *)device {(void)device;self.ready=YES;}
- (void)device:(ICDevice *)device didCloseSessionWithError:(NSError *)error {(void)device;if(error)self.failure=error;self.closed=YES;}
- (void)scannerDevice:(ICScannerDevice *)scanner didSelectFunctionalUnit:(ICScannerFunctionalUnit *)unit error:(NSError *)error {(void)scanner;(void)unit;if(error)self.failure=error;}
- (void)scannerDevice:(ICScannerDevice *)scanner didScanToURL:(NSURL *)url {
    (void)scanner;if(url){[self.images addObject:url];printf("ICA image: %s\n",url.fileSystemRepresentation);fflush(stdout);}
}
- (void)scannerDevice:(ICScannerDevice *)scanner didCompleteScanWithError:(NSError *)error {
    (void)scanner;self.completed=YES;if(error)self.failure=error;
}
- (void)device:(ICDevice *)device didEncounterError:(NSError *)error {(void)device;self.failure=error;}
@end
int main(int argc,const char *argv[]){@autoreleasepool{
    if(argc!=3 || strcmp(argv[1],"scan") || argv[2][0]!='/'){fprintf(stderr,"Usage: DS720DICAScan scan /absolute/private/output-directory\n");return 64;}
    if(geteuid()==0){fprintf(stderr,"Run the Image Capture client as the logged-in user.\n");return 77;}
    NSURL *folder=[NSURL fileURLWithPath:@(argv[2]) isDirectory:YES];NSError *error=nil;
    if(![NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error]){fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 1;}
    ICATestScan *test=[ICATestScan new];test.folder=folder;test.images=[NSMutableArray array];
    ICDeviceBrowser *browser=[ICDeviceBrowser new];browser.delegate=test;
    browser.browsedDeviceTypeMask=ICDeviceTypeMaskScanner|ICDeviceLocationTypeMaskLocal;[browser start];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:210];
    while(!test.closed && !test.failure && [deadline timeIntervalSinceNow]>0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        ICScannerFunctionalUnit *unit=test.scanner.selectedFunctionalUnit;
        if(test.ready && !test.requested && unit.type==ICScannerFunctionalUnitTypeDocumentFeeder && [unit.supportedResolutions containsIndex:300]) {
            test.requested=YES;
            ICScannerFunctionalUnitDocumentFeeder *feeder=(ICScannerFunctionalUnitDocumentFeeder *)unit;
            feeder.resolution=300;feeder.pixelDataType=ICScannerPixelDataTypeRGB;feeder.bitDepth=ICScannerBitDepth8Bits;
            feeder.duplexScanningEnabled=YES;
            test.scanner.transferMode=ICScannerTransferModeFileBased;test.scanner.downloadsDirectory=folder;
            test.scanner.documentName=@"DS720D-native-test";test.scanner.documentUTI=@"public.png";
            printf("Starting one native Image Capture duplex pass; user uid %u.\n",(unsigned)geteuid());fflush(stdout);
            [test.scanner requestScan];
        }
        if(test.completed && test.images.count>=2)break;
    }
    BOOL ok=test.completed && !test.failure && test.images.count==2;
    if(!ok && test.requested && !test.completed)[test.scanner cancelScan];
    if(test.scanner.hasOpenSession)[test.scanner requestCloseSession];
    NSDate *closeDeadline=[NSDate dateWithTimeIntervalSinceNow:2];
    while(!test.closed && [closeDeadline timeIntervalSinceNow]>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
    [browser stop];
    if(!ok)fprintf(stderr,"ICA scan incomplete: %s; images=%lu, requested=%d, completed=%d.\n",test.failure.localizedDescription.UTF8String?:"timeout or missing pages",(unsigned long)test.images.count,test.requested,test.completed);
    return ok?0:1;
}}

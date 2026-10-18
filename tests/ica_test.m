// SPDX-License-Identifier: MIT
#define main ds_ica_main
#import "../macos/ICADevice.m"
#undef main
#include <assert.h>
#include <math.h>

// Offline test: no installed service, USB capture, notification or motor calls.
NSData *ds_service_capture(NSError **error){(void)error;abort();}
BOOL ds_service_ping(NSError **error){(void)error;return NO;}
BOOL ds_service_probe(NSError **error){(void)error;abort();}
void ds_service_cancel(void){}
NSURL *ds_service_capture_file(NSURL *folder,NSError **error){(void)folder;(void)error;abort();}

int main(void){@autoreleasepool{
    ScannerObjectInfo info={0};assert(openUSB(123,&info)==noErr);
    ICD_ScannerOpenSessionPB session={0};assert(openSession(&info,&session)==noErr);
    assert(openSession(&info,&session)==kICADeviceAlreadyOpenErr);
    NSMutableDictionary *dict=[NSMutableDictionary dictionary];
    ICD_ScannerGetParametersPB get={0};get.theDict=(__bridge CFMutableDictionaryRef)dict;
    assert(getParameters(&info,&get)==noErr);
    assert([dict[@"device"][@"functionalUnits"][@"availableFunctionalUnitTypes"] isEqual:@[@3]]);
    // ICA geometry uses inches at TWUN_INCHES, never pixel counts. A feeder
    // must advertise actual paper sizes; size 0 means a flatbed's full area.
    NSDictionary *caps=dict[@"device"];
    assert(fabs([caps[@"ICAP_PHYSICALWIDTH"][@"value"] doubleValue]-8.64)<.0001);
    assert(fabs([caps[@"ICAP_PHYSICALHEIGHT"][@"value"] doubleValue]-14.45)<.0001);
    assert(([caps[@"ICAP_SUPPORTEDSIZES"][@"value"] isEqual:@[@1,@3,@4]]));
    ICD_ScannerSetParametersPB set={0};set.theDict=(__bridge CFMutableDictionaryRef)dict;
    dict[@"userScanArea"]=@{@"ICAP_XRESOLUTION":one(@600)};assert(setParameters(&info,&set)==kICADeviceUnsupportedErr);
    dict[@"userScanArea"]=@{@"ICAP_XRESOLUTION":one(@300),@"CAP_DUPLEXENABLED":one(@0)};
    assert(setParameters(&info,&set)==noErr && !state(&info).duplex);
    NSString *folder=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:NO attributes:nil error:NULL]);
    state(&info).folder=folder;
    uint8_t rgb[300*180*3];memset(rgb,230,sizeof rgb);
    struct ds_document page={.pixels=rgb,.width=300,.height=180};
    for(NSString *format in @[@"public.png",@"public.tiff",@"public.jpeg",@"com.adobe.pdf"]) {
        state(&info).format=format;NSString *path=saveImage(state(&info),&page);assert(path);
        if([format isEqual:@"com.adobe.pdf"]){CGPDFDocumentRef pdf=CGPDFDocumentCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path]);assert(pdf && CGPDFDocumentGetNumberOfPages(pdf)==1);CGRect box=CGPDFPageGetBoxRect(CGPDFDocumentGetPage(pdf,1),kCGPDFMediaBox);assert(box.size.width==72 && box.size.height==43.2);CGPDFDocumentRelease(pdf);}
        else {CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);assert(source);NSDictionary *props=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));assert([props[(__bridge NSString *)kCGImagePropertyPixelWidth] integerValue]==300);assert([props[(__bridge NSString *)kCGImagePropertyPixelHeight] integerValue]==180);assert([props[(__bridge NSString *)kCGImagePropertyDPIWidth] integerValue]==300);CFRelease(source);}
        assert([NSFileManager.defaultManager removeItemAtPath:path error:NULL]);
    }
    assert([NSFileManager.defaultManager removeItemAtPath:folder error:NULL]);
    ICD_ScannerCloseSessionPB close={0};assert(closeSession(&info,&close)==noErr);assert(closeDevice(&info)==noErr && !info.privateData);
    puts("ICA offline contract: feeder/session settings, unsupported resolution, PNG/TIFF/JPEG/PDF output and 300 dpi checked.");
}return 0;}

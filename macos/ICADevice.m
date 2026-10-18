// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import <ICADevices/ICADevices.h>
#import <ImageIO/ImageIO.h>
#import <ImageCaptureCore/ImageCaptureCore.h>
#import <IOKit/IOKitLib.h>
#import "ServiceClient.h"
#import "raster.h"
#import "packet.h"
#include <unistd.h>
#include <fcntl.h>

// The SDK callback table belongs to ICADevices, which launches this executable.
@interface DSScannerState : NSObject
@property BOOL session;
@property BOOL scanning;
@property BOOL duplex;
@property BOOL bands;
@property NSUInteger bandSize;
@property(copy) NSString *folder;
@property(copy) NSString *format;
@end
@implementation DSScannerState
@end

static DSScannerState *state(const ScannerObjectInfo *info) {
    return info?(__bridge DSScannerState *)(void *)info->privateData:nil;
}
static NSDictionary *one(NSNumber *value){return @{@"type":@"TWON_ONEVALUE",@"value":value};}
static NSDictionary *choice(NSNumber *value){return @{@"type":@"TWON_ENUMERATION",@"value":@[value],@"current":@0,@"default":@0};}
static NSDictionary *parameters(void) {
    return @{@"functionalUnits":@{@"availableFunctionalUnitTypes":@[@3],@"selectedFunctionalUnitType":@3},
        @"CAP_FEEDERENABLED":one(@1),@"CAP_AUTOFEED":one(@0),@"CAP_DUPLEX":one(@2),
        @"CAP_DUPLEXENABLED":one(@1),@"CAP_FEEDERLOADED":one(@1),
        @"ICAP_PIXELTYPE":choice(@2),@"ICAP_BITDEPTH":choice(@8),@"ICAP_UNITS":choice(@0),
        @"ICAP_XRESOLUTION":choice(@300),@"ICAP_YRESOLUTION":choice(@300),
        @"ICAP_XNATIVERESOLUTION":one(@300),@"ICAP_YNATIVERESOLUTION":one(@300),
        @"ICAP_PHYSICALWIDTH":one(@2592),@"ICAP_PHYSICALHEIGHT":one(@4335),
        @"ICAP_XSCALING":one(@1),@"ICAP_YSCALING":one(@1),
        @"ICAP_SUPPORTEDSIZES":choice(@0),@"supportsProgressNotificationsWithScanData":@YES};
}
static ICAError openUSB(UInt32 location,ScannerObjectInfo *info) {
    if(!location) {
        CFMutableDictionaryRef match=IOServiceMatching("IOUSBHostDevice");
        CFDictionarySetValue(match,CFSTR("IOPropertyMatch"),(__bridge CFDictionaryRef)@{@"idVendor":@0x04f9,@"idProduct":@0x60e2});
        io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,match);
        if(!service)return kICADeviceNotFoundErr;
        CFTypeRef value=IORegistryEntryCreateCFProperty(service,CFSTR("locationID"),kCFAllocatorDefault,0);
        UInt32 found=[(__bridge NSNumber *)value unsignedIntValue];
        if(value)CFRelease(value);IOObjectRelease(service);
        return found?ICDScannerConnectUSBDevice(found):kICADeviceNotFoundErr;
    }
    if(!info)return kICADeviceInvalidParamErr;
    DSScannerState *scanner=[DSScannerState new];scanner.duplex=YES;scanner.bandSize=524288;
    scanner.format=@"public.tiff";
    info->privateData=(Ptr)CFBridgingRetain(scanner);
    info->icaObjectInfo.objectType=kICADevice;info->icaObjectInfo.objectSubtype=kICADeviceScanner;
    info->uniqueID=location;info->flags=0;info->thumbnailSize=0;info->dataSize=0;
    strlcpy((char *)info->name,"Brother DS-720D",sizeof info->name);
    strlcpy((char *)info->creationDate,"2026:01:01 00:00:00",sizeof info->creationDate);
    return noErr;
}
static ICAError openPath(UInt32 location,io_string_t path,ScannerObjectInfo *info){(void)path;return openUSB(location,info);}
static ICAError closeDevice(ScannerObjectInfo *info){
    if(state(info).scanning)ds_service_cancel();
    if(info && info->privateData){CFRelease(info->privateData);info->privateData=NULL;}return noErr;
}
static ICAError periodic(ScannerObjectInfo *info){return state(info)?noErr:kICAInvalidObjectErr;}
static ICAError children(const ScannerObjectInfo *parent,UInt32 index,ScannerObjectInfo *child){(void)parent;(void)index;(void)child;return kICAIndexOutOfRangeErr;}
static ICAError properties(ScannerObjectInfo *info,CFMutableDictionaryRef dict){
    if(!state(info) || !dict)return kICADeviceInvalidParamErr;
    NSMutableDictionary *out=(__bridge NSMutableDictionary *)dict;
    out[(__bridge NSString *)kICAUserAssignedDeviceNameKey]=@"Brother DS-720D";
    out[(__bridge NSString *)kICADeviceTypeKey]=(__bridge NSString *)kICADeviceTypeScanner;
    return noErr;
}
static ICAError openSession(const ScannerObjectInfo *info,ICD_ScannerOpenSessionPB *pb){
    (void)pb;DSScannerState *s=state(info);if(!s)return kICAInvalidObjectErr;
    if(s.session)return kICADeviceAlreadyOpenErr;s.session=YES;return noErr;
}
static ICAError closeSession(const ScannerObjectInfo *info,ICD_ScannerCloseSessionPB *pb){
    (void)pb;DSScannerState *s=state(info);if(!s || !s.session)return kICAInvalidSessionErr;
    ds_service_cancel();s.session=NO;return noErr;
}
static ICAError initialize(const ScannerObjectInfo *info,ICD_ScannerInitializePB *pb){(void)pb;return state(info).session?noErr:kICAInvalidSessionErr;}
static ICAError getParameters(const ScannerObjectInfo *info,ICD_ScannerGetParametersPB *pb){
    if(!state(info) || !pb->theDict)return kICADeviceInvalidParamErr;
    NSMutableDictionary *out=(__bridge NSMutableDictionary *)pb->theDict;
    NSMutableDictionary *device=[parameters() mutableCopy];device[@"CAP_DUPLEXENABLED"]=one(@(state(info).duplex));
    out[@"device"]=device;return noErr;
}
static ICAError setParameters(const ScannerObjectInfo *info,ICD_ScannerSetParametersPB *pb){
    DSScannerState *s=state(info);if(!s || !pb->theDict)return kICADeviceInvalidParamErr;
    id area=((__bridge NSDictionary *)pb->theDict)[@"userScanArea"];
    if([area isKindOfClass:NSArray.class])area=[area count]>1?area[1]:nil;
    if(![area isKindOfClass:NSDictionary.class])return noErr;
    NSNumber *unit=area[@"selectedFunctionalUnitType"];
    if(unit)return [unit integerValue]==3?noErr:kICADeviceUnsupportedErr;
    NSDictionary *supported=@{@"ICAP_XRESOLUTION":@300,@"ICAP_YRESOLUTION":@300,@"ICAP_PIXELTYPE":@2,@"ICAP_BITDEPTH":@8};
    for(NSString *key in supported) {
        id entry=area[key];
        if(entry && (![entry isKindOfClass:NSDictionary.class] || ![entry[@"value"] isEqual:supported[key]]))return kICADeviceUnsupportedErr;
    }
    id duplex=area[@"CAP_DUPLEXENABLED"];if([duplex isKindOfClass:NSDictionary.class])s.duplex=[duplex[@"value"] boolValue];
    s.bands=[area[@"progressNotificationWithScanData"] boolValue];
    NSUInteger band=[area[@"progressNotificationWithScanDataMaxBandSize"] unsignedIntegerValue];
    s.bandSize=MAX(DS_NATIVE_BPL,MIN(band?:524288,1048576ul));
    id folder=area[@"document folder"];if([folder isKindOfClass:NSString.class] && [folder isAbsolutePath])s.folder=folder;
    id format=area[@"document format"];
    if([format isKindOfClass:NSString.class] && [@[ @"public.tiff",@"public.png",@"public.jpeg",@"com.adobe.pdf"] containsObject:format])s.format=format;
    return noErr;
}
static ICAError status(const ScannerObjectInfo *info,ICD_ScannerStatusPB *pb){if(!state(info))return kICAInvalidObjectErr;pb->status=0;return noErr;}
static ICAError notify(ICAObject object,CFStringRef type,NSDictionary *extra,BOOL wait){
    NSMutableDictionary *dict=[extra mutableCopy]?:[NSMutableDictionary dictionary];
    dict[(__bridge NSString *)kICANotificationICAObjectKey]=@(object);
    dict[(__bridge NSString *)kICANotificationTypeKey]=(__bridge NSString *)type;
    ICASendNotificationPB pb={0};pb.notificationDictionary=(__bridge CFMutableDictionaryRef)dict;
    ICAError error=wait?ICDSendNotificationAndWaitForReply(&pb):ICDSendNotification(&pb);
    return error?:((ICAError)pb.replyCode);
}
static NSString *saveImage(DSScannerState *s,struct ds_document *page){
    NSString *folder=s.folder?:NSTemporaryDirectory();
    NSString *ext=[@{@"public.tiff":@"tiff",@"public.png":@"png",@"public.jpeg":@"jpg",@"com.adobe.pdf":@"pdf"} objectForKey:s.format];
    NSString *path=[folder stringByAppendingPathComponent:[NSString stringWithFormat:@"DS720D-%@.%@",NSUUID.UUID.UUIDString,ext]];
    int fd=open(path.fileSystemRepresentation,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0600);
    if(fd<0)return nil;close(fd);
    CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,page->pixels,page->width*page->height*3,NULL);
    CGImageRef image=CGImageCreate(page->width,page->height,8,24,page->width*3,space,(CGBitmapInfo)kCGImageAlphaNone,provider,NULL,false,kCGRenderingIntentDefault);
    CGImageDestinationRef destination=image?CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],(__bridge CFStringRef)s.format,1,NULL):NULL;
    BOOL ok=NO;
    if(destination){CGImageDestinationAddImage(destination,image,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImagePropertyDPIWidth:@300,(__bridge NSString *)kCGImagePropertyDPIHeight:@300});ok=CGImageDestinationFinalize(destination);CFRelease(destination);}
    if(image)CGImageRelease(image);CGDataProviderRelease(provider);CGColorSpaceRelease(space);
    if(!ok){unlink(path.fileSystemRepresentation);return nil;}return path;
}
static ICAError scan(const ScannerObjectInfo *info,ICD_ScannerStartPB *pb){
    (void)pb;DSScannerState *s=state(info);if(!s.session)return kICAInvalidSessionErr;
    if(s.scanning)return kICAIOPendingErr;s.scanning=YES;
    ICAError result=noErr;NSError *error=nil;
    NSData *raw=ds_service_capture(&error);
    if(!raw)result=kICACommunicationErr;
    for(unsigned side=0;raw && side<(s.duplex?2u:1u) && !result;side++) {
        struct ds_document page;
        if(!ds_raster_side(raw.bytes,raw.length,side,true,&page)){result=kICAFileCorruptedErr;break;}
        if(s.bands) {
            NSUInteger rows=MAX(1ul,s.bandSize/(page.width*3));
            for(NSUInteger y=0;y<page.height && !result;y+=rows) {
                NSUInteger count=MIN(rows,page.height-y);
                NSMutableDictionary *band=[NSMutableDictionary dictionary];
                result=ICDAddBandInfoToNotificationDictionary((__bridge CFMutableDictionaryRef)band,(UInt32)page.width,(UInt32)page.height,24,8,3,0,ICScannerPixelDataTypeRGB,(UInt32)(page.width*3),(UInt32)y,(UInt32)count,(UInt32)(count*page.width*3),page.pixels+y*page.width*3);
                if(!result)result=notify(info->icaObject,kICANotificationTypeScanProgressStatus,band,YES);
            }
            if(!result)result=notify(info->icaObject,kICANotificationTypeScannerPageDone,nil,NO);
        } else {
            NSString *path=saveImage(s,&page);
            if(!path)result=kICADeviceInternalErr;
            else result=notify(info->icaObject,kICANotificationTypeScannerPageDone,@{(__bridge NSString *)kICANotificationScannerDocumentNameKey:path},NO);
        }
        free(page.pixels);
    }
    if(result)notify(info->icaObject,kICANotificationTypeDeviceStatusError,@{(__bridge NSString *)kICANotificationVendorErrorCodeKey:@(result)},NO);
    notify(info->icaObject,kICANotificationTypeScannerScanDone,nil,NO);s.scanning=NO;
    return result;
}
static ICAError message(const ScannerObjectInfo *info,ICD_ScannerObjectSendMessagePB *pb,ICDCompletion completion){
    (void)info;(void)completion;
    if(pb->message.messageType==kICAMessageCheckDevice)return noErr;
    if(pb->message.messageType==kICAMessageDeviceYield){ds_service_cancel();return noErr;}
    return kICADeviceUnsupportedErr;
}
int main(int argc,const char *argv[]){@autoreleasepool{
    gICDScannerCallbackFunctions=(ICD_scanner_callback_functions){
        .f_ICD_ScannerOpenUSBDevice=openUSB,.f_ICD_ScannerOpenUSBDeviceWithIORegPath=openPath,
        .f_ICD_ScannerCloseDevice=closeDevice,.f_ICD_ScannerCleanup=closeDevice,.f_ICD_ScannerPeriodicTask=periodic,
        .f_ICD_ScannerGetObjectInfo=children,.f_ICD_ScannerGetPropertyData=ICDScannerGetStandardPropertyData,
        .f_ICD_ScannerAddPropertiesToCFDictionary=properties,.f_ICD_ScannerSendMessage=message,
        .f_ICD_ScannerOpenSession=openSession,.f_ICD_ScannerCloseSession=closeSession,
        .f_ICD_ScannerInitialize=initialize,.f_ICD_ScannerGetParameters=getParameters,
        .f_ICD_ScannerSetParameters=setParameters,.f_ICD_ScannerStatus=status,.f_ICD_ScannerStart=scan};
    return ICD_ScannerMain(argc,argv);
}}

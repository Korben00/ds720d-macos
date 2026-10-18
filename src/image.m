// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import "capture.h"
#import "packet.h"
#include <math.h>

static BOOL number(id value,uint64_t maximum,uint64_t *result) {
    if(![value isKindOfClass:NSNumber.class])return NO;
    double n=[value doubleValue];
    if(!isfinite(n) || n<0 || n>maximum || n!=floor(n))return NO;
    *result=(uint64_t)n;return YES;
}

static int invalidCapture(void) {
    fprintf(stderr,"Capture is incomplete, unsupported, or has inconsistent image metadata.\n");
    return 1;
}

static BOOL savePNG(NSString *path,NSData *pixels,size_t width) {
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
    CGImageRef image=CGImageCreate(width,pixels.length/(width*3),8,24,width*3,space,
        (CGBitmapInfo)kCGImageAlphaNone,provider,NULL,false,kCGRenderingIntentDefault);
    CGImageDestinationRef output=image?CGImageDestinationCreateWithURL(
        (__bridge CFURLRef)[NSURL fileURLWithPath:path],CFSTR("public.png"),1,NULL):NULL;
    BOOL success=NO;
    if(output) {
        CGImageDestinationAddImage(output,image,(__bridge CFDictionaryRef)@{
            (__bridge NSString *)kCGImagePropertyDPIWidth:@(DS_NATIVE_DPI),
            (__bridge NSString *)kCGImagePropertyDPIHeight:@(DS_NATIVE_DPI)});
        success=CGImageDestinationFinalize(output);CFRelease(output);
    }
    if(image)CGImageRelease(image);
    CGDataProviderRelease(provider);CGColorSpaceRelease(space);
    if(success)success=[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:NULL];
    return success;
}

int ds_decode_capture(const char *path) {
    NSString *file=@(path);
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:file error:NULL];
    if(!attributes || [attributes fileSize]>128000000)return 1;
    NSString *text=[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:NULL];
    if(!text)return 1;
    NSMutableData *raw=[NSMutableData data];
    uint64_t bpl=0,frames=0;
    BOOL configured=NO,ended=NO,done=NO;
    for(NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if(!line.length)continue;
        if(line.length>1500000 || done)return invalidCapture();
        id item=[NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        if(![item isKindOfClass:NSDictionary.class] || ![item[@"event"] isKindOfClass:NSString.class])return invalidCapture();
        if([item[@"event"] isEqual:@"configured"]) {
            uint64_t channels,stripe,dpi;
            if(configured || !number(item[@"bytesPerLine"],DS_NATIVE_BPL,&bpl) || !bpl || bpl%3 ||
                !number(item[@"channels"],3,&channels) || channels!=3 ||
                !number(item[@"stripeRows"],80,&stripe) || stripe!=DS_STRIPE_ROWS ||
                !number(item[@"dpi"],300,&dpi) || dpi!=DS_NATIVE_DPI ||
                ![item[@"imagePath"] isEqual:@"memory"] || ![item[@"layout"] isEqual:@"line-planar-rgb"])return invalidCapture();
            configured=YES;
        } else if([item[@"event"] isEqual:@"frame"]) {
            NSArray *words=item[@"words"];
            if(!configured || ended || ![words isKindOfClass:NSArray.class] || words.count!=6 ||
                ![item[@"data"] isKindOfClass:NSString.class])return invalidCapture();
            uint64_t w[6],status;
            for(unsigned i=0;i<6;i++)if(!number(words[i],UINT32_MAX,w+i))return invalidCapture();
            if(!number(item[@"status"],0,&status) || (w[0]!=1 && w[0]!=3) ||
                w[4]>DS_STRIPE_ROWS*3 || w[4]%3 ||
                (w[3]*w[4] && w[3]!=bpl/3))return invalidCapture();
            NSData *data=[[NSData alloc] initWithBase64EncodedString:item[@"data"] options:0];
            if(!data || data.length!=w[3]*w[4] || (!data.length && w[0]!=3) ||
                raw.length+data.length>80000000 || ++frames>256)return invalidCapture();
            [raw appendData:data];ended=w[0]==3;
        } else if([item[@"event"] isEqual:@"done"]) {
            uint64_t success,reportedFrames,reportedBytes;
            if(!ended || !number(item[@"success"],1,&success) || success!=1 ||
                !number(item[@"frames"],256,&reportedFrames) || reportedFrames!=frames ||
                !number(item[@"bytes"],80000000,&reportedBytes) || reportedBytes!=raw.length)return invalidCapture();
            done=YES;
        } else if([item[@"event"] isEqual:@"error"])return invalidCapture();
    }
    if(!done || !bpl || !raw.length || raw.length%bpl)return invalidCapture();
    NSMutableData *sides[2]={[NSMutableData data],[NSMutableData data]};
    const uint8_t *p=raw.bytes;
    NSUInteger width=(NSUInteger)bpl/3,rows=raw.length/(NSUInteger)bpl;
    for(NSUInteger y=0;y<rows;y++) {
        NSUInteger sideIndex=(y/DS_STRIPE_ROWS)%2;
        NSMutableData *side=sides[sideIndex];
        NSUInteger offset=side.length;
        [side increaseLengthBy:(NSUInteger)bpl];
        uint8_t *dst=(uint8_t *)side.mutableBytes+offset;
        const uint8_t *src=p+y*bpl;
        // The rear sensor reads the sheet in the opposite horizontal direction.
        for(NSUInteger x=0;x<width;x++)for(unsigned c=0;c<3;c++)
            dst[3*x+c]=src[c*width+(sideIndex?width-1-x:x)];
    }
    if(!sides[0].length || !sides[1].length)return invalidCapture();
    NSString *base=[file stringByDeletingPathExtension];
    NSString *front=[base stringByAppendingString:@"-front.png"],*back=[base stringByAppendingString:@"-back.png"];
    if(!savePNG(front,sides[0],width) || !savePNG(back,sides[1],width))return 1;
    printf("%s\n%s\nTransport complete; image quality requires visual verification.\n",front.fileSystemRepresentation,back.fileSystemRepresentation);
    return 0;
}

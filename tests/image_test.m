// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import "capture.h"
#include <assert.h>

static uint8_t sample(unsigned side,unsigned y,unsigned x,unsigned c) {
    return (uint8_t)(side*113+y*3+x*7+c*43);
}

static void writeCapture(NSString *path,NSArray *events) {
    NSMutableData *text=[NSMutableData data];
    for(NSDictionary *event in events) {
        [text appendData:[NSJSONSerialization dataWithJSONObject:event options:0 error:NULL]];
        [text appendBytes:"\n" length:1];
    }
    assert([text writeToFile:path atomically:YES]);
}

static void checkPNG(NSString *path,unsigned side,unsigned height) {
    CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);
    assert(source);
    CGImageRef image=CGImageSourceCreateImageAtIndex(source,0,NULL);
    assert(image && CGImageGetWidth(image)==7 && CGImageGetHeight(image)==height);
    NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
    assert([properties[(__bridge NSString *)kCGImagePropertyDPIWidth] intValue]==300);
    NSMutableData *bitmap=[NSMutableData dataWithLength:7*height*4];
    CGContextRef context=CGBitmapContextCreate(bitmap.mutableBytes,7,height,8,7*4,
        CGImageGetColorSpace(image),kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    assert(context);
    CGContextDrawImage(context,CGRectMake(0,0,7,height),image);
    const uint8_t *pixels=bitmap.bytes;
    for(unsigned y=0;y<height;y++)for(unsigned x=0;x<7;x++)for(unsigned c=0;c<3;c++)
        assert(pixels[(y*7+x)*4+c]==sample(side,y,x,c));
    CGContextRelease(context);CGImageRelease(image);CFRelease(source);
}

int main(void) {
    @autoreleasepool {
        NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        assert([NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:NO attributes:nil error:NULL]);
        NSString *path=[directory stringByAppendingPathComponent:@"test.jsonl"];
        NSMutableArray *events=[NSMutableArray arrayWithObject:@{@"event":@"configured",@"dpi":@300,@"bytesPerLine":@21,@"channels":@3,@"stripeRows":@80,@"imagePath":@"memory",@"layout":@"line-planar-rgb"}];
        NSMutableData *raw=[NSMutableData dataWithLength:400*21];
        uint8_t *p=raw.mutableBytes;
        for(unsigned y=0;y<400;y++)for(unsigned x=0;x<7;x++)for(unsigned c=0;c<3;c++) {
            unsigned side=(y/80)%2;
            p[y*21+c*7+x]=sample(side,(y/160)*80+y%80,side?6-x:x,c);
        }
        unsigned offset=0,index=0,chunks[]={13,80,7,80,1,79,60,80};
        while(offset<400) {
            unsigned rows=MIN(chunks[index++%8],400-offset);
            NSData *data=[raw subdataWithRange:NSMakeRange(offset*21,rows*21)];offset+=rows;
            [events addObject:@{@"event":@"frame",@"words":@[@(offset==400?3:1),@0,@0,@7,@(rows*3),@4096],@"status":@0,@"data":[data base64EncodedStringWithOptions:0]}];
        }
        NSUInteger frames=events.count-1;
        [events addObject:@{@"event":@"done",@"success":@YES,@"frames":@(frames),@"bytes":@(raw.length)}];
        writeCapture(path,events);assert(ds_decode_capture(path.fileSystemRepresentation)==0);
        checkPNG([directory stringByAppendingPathComponent:@"test-front.png"],0,240);
        checkPNG([directory stringByAppendingPathComponent:@"test-back.png"],1,160);

        // The real firmware can finish with a separate, empty EOP frame.
        NSMutableArray *emptyEnd=[events mutableCopy];
        NSMutableDictionary *last=[emptyEnd[frames] mutableCopy];
        NSArray *lastWords=last[@"words"];
        last[@"words"]=@[@1,@0,@0,lastWords[3],lastWords[4],@4096];
        emptyEnd[frames]=last;
        [emptyEnd insertObject:@{@"event":@"frame",@"words":@[@3,@0,@0,@0,@0,@0],@"status":@0,@"data":@""} atIndex:frames+1];
        emptyEnd[emptyEnd.count-1]=@{@"event":@"done",@"success":@YES,@"frames":@(frames+1),@"bytes":@(raw.length)};
        writeCapture(path,emptyEnd);assert(ds_decode_capture(path.fileSystemRepresentation)==0);
        checkPNG([directory stringByAppendingPathComponent:@"test-back.png"],1,160);

        NSMutableArray *bad=[events mutableCopy];[bad removeLastObject];
        writeCapture(path,bad);assert(ds_decode_capture(path.fileSystemRepresentation)!=0);
        bad=[events mutableCopy];bad[1]=@{@"event":@"frame",@"words":@[@1],@"status":@0,@"data":@""};
        writeCapture(path,bad);assert(ds_decode_capture(path.fileSystemRepresentation)!=0);
        bad=[events mutableCopy];bad[1]=@{@"event":@"frame",@"words":@[@1,@0,@0,@21,@80,@4096],@"status":@0,@"data":@"AA=="};
        writeCapture(path,bad);assert(ds_decode_capture(path.fileSystemRepresentation)!=0);
        bad=[events mutableCopy];bad[0]=@{@"event":@"configured",@"dpi":@300,@"bytesPerLine":@21,@"channels":@1,@"stripeRows":@80};
        writeCapture(path,bad);assert(ds_decode_capture(path.fileSystemRepresentation)!=0);
        bad=[events mutableCopy];bad[bad.count-1]=@{@"event":@"done",@"success":@NO,@"frames":@(frames),@"bytes":@(raw.length)};
        writeCapture(path,bad);assert(ds_decode_capture(path.fileSystemRepresentation)!=0);
        assert([NSFileManager.defaultManager removeItemAtPath:directory error:NULL]);
        puts("RGB duplex decoding: pixel values, stripe boundaries, DPI and malformed captures checked.");
    }
    return 0;
}

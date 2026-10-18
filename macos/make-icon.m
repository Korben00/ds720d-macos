// SPDX-License-Identifier: MIT
#import <AppKit/AppKit.h>

int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if(argc!=2)return 64;
        NSString *directory=@(argv[1]);
        if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL])return 1;
        const unsigned bases[]={16,32,128,256,512};
        for(unsigned i=0;i<5;i++)for(unsigned scale=1;scale<=2;scale++) {
            unsigned size=bases[i]*scale;
            NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:size pixelsHigh:size bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            NSGraphicsContext *context=[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
            [NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext=context;
            CGContextScaleCTM(context.CGContext,(double)size/1024,(double)size/1024);
            [[NSColor colorWithSRGBRed:0.08 green:0.42 blue:0.48 alpha:1] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(24,24,976,976) xRadius:210 yRadius:210] fill];
            [[NSColor colorWithSRGBRed:0.84 green:0.95 blue:0.94 alpha:1] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(267,370,490,492) xRadius:24 yRadius:24] fill];
            [[NSColor colorWithSRGBRed:0.26 green:0.61 blue:0.63 alpha:1] setFill];
            for(unsigned row=0;row<5;row++)[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(330,730-row*54,330-(row%2)*75,16) xRadius:8 yRadius:8] fill];
            [[NSColor colorWithSRGBRed:0.14 green:0.22 blue:0.28 alpha:1] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(140,176,744,310) xRadius:66 yRadius:66] fill];
            [NSColor.blackColor setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(218,402,588,28) xRadius:14 yRadius:14] fill];
            [[NSColor colorWithSRGBRed:0.47 green:0.91 blue:0.69 alpha:1] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(732,258,40,40)] fill];
            [NSGraphicsContext restoreGraphicsState];
            NSString *name=[NSString stringWithFormat:@"icon_%ux%u%@.png",bases[i],bases[i],scale==2?@"@2x":@""];
            NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            if(![png writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES])return 1;
        }
    }
    return 0;
}

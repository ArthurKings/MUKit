//
//  MUImageCacheUtils.m
//  MUKit_Example
//
//  Created by Jekity on 2018/7/30.
//  Copyright © 2018年 Jeykit. All rights reserved.
//

#import "MUImageCacheUtils.h"


inline size_t FICByteAlign(size_t width, size_t alignment) {
    return ((width + (alignment - 1)) / alignment) * alignment;
}

inline size_t FICByteAlignForCoreAnimation(size_t bytesPerRow) {
    return FICByteAlign(bytesPerRow, 64);
}

@implementation MUImageCacheUtils
{
    NSLock *_lock;
    NSMutableDictionary * _images;
}
+ (UIImage *)drawImageWithdrawSize:(CGSize)drawSize CornerRadius:(CGFloat)radius originalImage:(UIImage *)image{
    @autoreleasepool{
        
        CGImageRef imageRef = image.CGImage;
        // device color space
        static CGColorSpaceRef colorspaceRef = nil;
        if (!colorspaceRef) {
            colorspaceRef = CGColorSpaceCreateDeviceRGB();
        }
        //        BOOL hasAlpha = MUCGImageRefContainsAlpha(imageRef);
        // iOS display alpha info (BRGA8888/BGRX8888)
        //        CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Host;
        //        bitmapInfo |= hasAlpha ? kCGImageAlphaPremultipliedFirst : kCGImageAlphaNoneSkipFirst;
        CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host;
        
        CGFloat screenScale = [MUImageCacheUtils contentsScale];
        CGSize pixelSize = CGSizeMake(drawSize.width * screenScale, drawSize.height * screenScale);
        
        // It calculates the bytes-per-row based on the __bitsPerComponent and width arguments.
        size_t bytesPerRow = ceil((pixelSize.width * 4) / 64) * 64;
        size_t width = pixelSize.width;
        size_t height = pixelSize.height;
        
        CGRect imageRect = CGRectMake(0, 0, width, height);
        // kCGImageAlphaNone is not supported in CGBitmapContextCreate.
        // Since the original image here has no alpha info, use kCGImageAlphaNoneSkipLast
        // to create bitmap graphics contexts without alpha info.
        CGContextRef context = CGBitmapContextCreate(NULL,
                                                     width,
                                                     height,
                                                     8,
                                                     bytesPerRow,
                                                     colorspaceRef,
                                                     bitmapInfo);
        if (context == NULL) {
            return image;
        }
        
        if (radius > 0) {
            CGPathRef path = _FICDCreateRoundedRectPath(imageRect, ceilf(radius) * [MUImageCacheUtils contentsScale]);
            CGContextAddPath(context, path);
            CFRelease(path);
            CGContextEOClip(context);
        }
        
        CGContextClearRect(context, imageRect);
        CGContextDrawImage(context, imageRect, imageRef);
        // Draw the image into the context and retrieve the new bitmap image without alpha
        CGImageRef imageRefWithoutAlpha = nil;
        imageRefWithoutAlpha = CGBitmapContextCreateImage(context);
        UIImage *imageWithoutAlpha = [[UIImage alloc] initWithCGImage:imageRefWithoutAlpha scale:screenScale orientation:image.imageOrientation];
        CGContextRelease(context);
        CGImageRelease(imageRefWithoutAlpha);
        return imageWithoutAlpha;
    }
}

static const long long shareImageMaxLength = 1024*1024;
+(UIImage *)getImageWithDada:(NSData *)data
{
    if(!data)
    {
        return nil;
    }
    @autoreleasepool {
        UIImage *image = [UIImage imageWithData:data];
        if(data.length <= shareImageMaxLength)
        {
            return image;
        }
        else
        {
            CGFloat compressionQualityArr[1001] = {0};
            compressionQualityArr[0] = 0.0001;
            for(NSInteger i = 1; i <= 1000; i++)
            {
                compressionQualityArr[i] = i*0.001;
            }
            NSData *compressedData = [self findImageWithImage:image lowerBoundary:0 upperBoundary:1000 compressionQualityArr:compressionQualityArr];
            return [UIImage imageWithData:compressedData];
        }
    }
}
+(NSData *)findImageWithImage : (UIImage *)image
                lowerBoundary : (NSInteger)lowerBoundary
                upperBoundary : (NSInteger)upperBoundary
        compressionQualityArr : (CGFloat *)compressionQualityArr

{
    NSInteger x = (lowerBoundary + upperBoundary) / 2;
    NSData *data = UIImageJPEGRepresentation(image, compressionQualityArr[x]);
    if(data.length <= shareImageMaxLength)
    {
        NSLog(@"data.length:%lu,compressionQualityArr[%ld]:%f", (unsigned long)data.length, (long)x, compressionQualityArr[x]);
        return data;
    }
    if ((data.length > shareImageMaxLength) && (x > 0))//说明在compressionQualityArr[lowerBoundary]-compressionQualityArr[x]范围参数之中
    {
        return [self findImageWithImage:image lowerBoundary:lowerBoundary upperBoundary:x compressionQualityArr:compressionQualityArr];
    }
    else
    {
        NSLog(@"data.length:%lu,compressionQualityArr[%ld]:%f", (unsigned long)data.length, (long)x, compressionQualityArr[x]);
        return data;
    }
}
+ (NSString*)directoryPath
{
    
    static NSString* __directoryPath = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        __directoryPath = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"MUImage"];
        
        NSFileManager *fileManager = [[NSFileManager alloc] init];
        BOOL directoryExists = [fileManager fileExistsAtPath:__directoryPath];
        if (directoryExists == NO) {
            [fileManager createDirectoryAtPath:__directoryPath withIntermediateDirectories:YES attributes:nil error:nil];
        }
    });
    
    return __directoryPath;
}

+ (CGFloat)contentsScale
{
    
    static CGFloat __contentsScale = 1;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __contentsScale = [UIScreen mainScreen].scale;
    });
    
    return __contentsScale;
}

+ (NSString*)clientVersion
{
    
    static NSString* __clientVersion = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
        NSString *build = [[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"];
        
        __clientVersion = [version stringByAppendingString:build];
    });
    
    return __clientVersion;
}

+ (int)pageSize
{
    static int __pageSize = 0;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __pageSize = getpagesize();
    });
    
    return __pageSize;
}

+ (MUImageContentType)contentTypeForImageData:(NSData*)data
{
    
    if (!data) {
        return MUImageContentTypeUnknown;
    }
    
    uint8_t c;
    [data getBytes:&c length:1];
    switch (c) {
        case 0xFF:
            return MUImageContentTypeJPEG;
        case 0x89:
            return MUImageContentTypePNG;
        case 0x47:
            return MUImageContentTypeGif;
        case 0x49:
        case 0x4D:
            return MUImageContentTypeTiff;
        case 0x52:
            // R as RIFF for WEBP
            if ([data length] < 12) {
                return MUImageContentTypeUnknown;
            }
            
            NSString* testString = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, 12)] encoding:NSASCIIStringEncoding];
            if ([testString hasPrefix:@"RIFF"] && [testString hasSuffix:@"WEBP"]) {
                return MUImageContentTypeWebP;
            }
            
            return MUImageContentTypeUnknown;
    }
    return MUImageContentTypeUnknown;
}

// from FastImageCache
CGMutablePathRef _FICDCreateRoundedRectPath(CGRect rect, CGFloat cornerRadius)
{
    CGMutablePathRef path = CGPathCreateMutable();
    
    CGFloat minX = CGRectGetMinX(rect);
    CGFloat midX = CGRectGetMidX(rect);
    CGFloat maxX = CGRectGetMaxX(rect);
    CGFloat minY = CGRectGetMinY(rect);
    CGFloat midY = CGRectGetMidY(rect);
    CGFloat maxY = CGRectGetMaxY(rect);
    
    CGPathMoveToPoint(path, NULL, minX, midY);
    CGPathAddArcToPoint(path, NULL, minX, maxY, midX, maxY, cornerRadius);
    CGPathAddArcToPoint(path, NULL, maxX, maxY, maxX, midY, cornerRadius);
    CGPathAddArcToPoint(path, NULL, maxX, minY, midX, minY, cornerRadius);
    CGPathAddArcToPoint(path, NULL, minX, minY, minX, midY, cornerRadius);
    
    return path;
}

CGRect _MUImageCalcDrawBounds(CGSize imageSize, CGSize targetSize, NSString* const contentsGravity)
{
    
    CGFloat x, y, width, height;
    if ([contentsGravity isEqualToString:kCAGravityCenter]) {
        
        x = (targetSize.width - imageSize.width) / 2;
        y = (targetSize.height - imageSize.height) / 2;
        width = imageSize.width;
        height = imageSize.height;
        
    } else if ([contentsGravity isEqualToString:kCAGravityTop]) {
        
        x = (targetSize.width - imageSize.width) / 2;
        y = targetSize.height - imageSize.height;
        width = imageSize.width;
        height = imageSize.height;
        
    } else if ([contentsGravity isEqualToString:kCAGravityBottom]) {
        
        x = (targetSize.width - imageSize.width) / 2;
        y = 0;
        width = imageSize.width;
        height = imageSize.height;
        
    } else if ([contentsGravity isEqualToString:kCAGravityLeft]) {
        
        x = 0;
        y = (targetSize.height - imageSize.height) / 2;
        width = imageSize.width;
        height = imageSize.height;
        
    } else if ([contentsGravity isEqualToString:kCAGravityRight]) {
        
        x = targetSize.width - imageSize.width;
        y = (targetSize.height - imageSize.height) / 2;
        width = imageSize.width;
        height = imageSize.height;
        
    } else if ([contentsGravity isEqualToString:kCAGravityTopLeft]) {
        
        x = 0;
        y = targetSize.height - imageSize.height;
        width = imageSize.width;
        height = imageSize.height;
        
    } else if ([contentsGravity isEqualToString:kCAGravityTopRight]) {
        
        x = targetSize.width - imageSize.width;
        y = targetSize.height - imageSize.height;
        width = imageSize.width;
        height = imageSize.height;
        
    } else if ([contentsGravity isEqualToString:kCAGravityBottomLeft]) {
        
        x = 0;
        y = 0;
        width = imageSize.width;
        height = imageSize.height;
        
    } else if ([contentsGravity isEqualToString:kCAGravityBottomRight]) {
        
        x = targetSize.width - imageSize.width;
        y = 0;
        width = imageSize.width;
        height = imageSize.height;
        
    } else if ([contentsGravity isEqualToString:kCAGravityResizeAspectFill]) {
        
        CGFloat scaleWidth = targetSize.width / imageSize.width;
        CGFloat scaleHeight = targetSize.height / imageSize.height;
        
        if (scaleWidth < scaleHeight) {
            y = 0;
            height = targetSize.height;
            width = scaleHeight * imageSize.width;
            x = (targetSize.width - width) / 2;
        } else {
            x = 0;
            width = targetSize.width;
            height = scaleWidth * imageSize.height;
            y = (targetSize.height - height) / 2;
        }
    } else if ([contentsGravity isEqualToString:kCAGravityResize]) {
        
        x = y = 0;
        width = targetSize.width;
        height = targetSize.height;
        
    } else {
        
        // kCAGravityResizeAspect
        CGFloat scaleWidth = targetSize.width / imageSize.width;
        CGFloat scaleHeight = targetSize.height / imageSize.height;
        
        if (scaleWidth > scaleHeight) {
            y = 0;
            height = targetSize.height;
            width = scaleHeight * imageSize.width;
            x = (targetSize.width - width) / 2;
        } else {
            x = 0;
            width = targetSize.width;
            height = scaleWidth * imageSize.height;
            y = (targetSize.height - height) / 2;
        }
    }
    
    return CGRectMake(x, y, width, height);
}

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    static MUImageCacheUtils* __instance = nil;
    dispatch_once(&onceToken, ^{
        __instance = [[[self class] alloc] init];
    });
    
    return __instance;
}
- (instancetype)init{
    if (self = [super init]) {
        _lock = [[NSLock alloc]init];
        _images = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)addProgressiveImageWithKey:(NSString *)key progressive:(UIImage *)progressiveImage{
    [_lock lock];
    [_images setValue:nil forKey:key];
    [_images setValue:progressiveImage forKey:key];
    [_lock unlock];
}
- (UIImage *)getProgressiveImageWithKey:(NSString *)key{
    UIImage *progressiveImage = nil;
    [_lock lock];
    progressiveImage = [_images valueForKey:key];
    [_lock unlock];
    return progressiveImage;
}

- (void)removeProgressiveImageWithKey:(NSString *)key{
    [_lock lock];
    [_images setValue:nil forKey:key];
    [_lock unlock];
}
@end

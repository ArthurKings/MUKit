//
//  MUHighlightOverlayLayer.m
//  MUAsyncDisplayLayer
//
//  Created by Jekity on 2018/9/7.
//  Copyright © 2018年 Jekity. All rights reserved.
//

#import "MUHighlightOverlayLayer.h"

#import <UIKit/UIKit.h>
#import <tgmath.h>


CGFloat MUScreenScale()
{
    static CGFloat __scale = 0.0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __scale = [[UIScreen mainScreen] scale];
    });
    return __scale;
}


static const CGFloat kCornerRadius = 2.5;
static const UIEdgeInsets padding = {2, 4, 1.5, 4};

@implementation MUHighlightOverlayLayer
{
    NSArray *_rects;
}

+ (id)defaultValueForKey:(NSString *)key
{
    if ([key isEqualToString:@"contentsScale"]) {
        return @(MUScreenScale());
    } else if ([key isEqualToString:@"highlightColor"]) {
        CGFloat components[] = {0, 0, 0, 0.25};
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGColorRef color = CGColorCreate(colorSpace, components);
        CGColorSpaceRelease(colorSpace);
        return CFBridgingRelease(color);
    } else {
        return [super defaultValueForKey:key];
    }
}

+ (BOOL)needsDisplayForKey:(NSString *)key
{
    if ([key isEqualToString:@"bounds"]) {
        return YES;
    } else {
        return [super needsDisplayForKey:key];
    }
}

+ (id<CAAction>)defaultActionForKey:(NSString *)event
{
    return (id<CAAction>)[NSNull null];
}

- (instancetype)initWithRects:(NSArray *)rects
{
    return [self initWithRects:rects targetLayer:nil];
}

- (instancetype)initWithRects:(NSArray *)rects targetLayer:(id)targetLayer
{
    if (self = [super init]) {
        _rects = [rects copy];
        _targetLayer = targetLayer;
    }
    return self;
}

@dynamic highlightColor;

- (void)drawInContext:(CGContextRef)ctx
{
    [super drawInContext:ctx];
    
    CGAffineTransform affine = CGAffineTransformIdentity;
    CGMutablePathRef highlightPath = CGPathCreateMutable();
    CALayer *targetLayer = self.targetLayer;
    
    for (NSValue *value in _rects) {
        CGRect rect = [value CGRectValue];
        
        // Don't highlight empty rects.
        if (CGRectIsEmpty(rect)) {
            continue;
        }
        
        if (targetLayer != nil) {
            rect = [self convertRect:rect fromLayer:targetLayer];
        }
        rect = CGRectMake(round(rect.origin.x), round(rect.origin.y), round(rect.size.width), round(rect.size.height));
        
        CGFloat minX = rect.origin.x - padding.left;
        CGFloat maxX = CGRectGetMaxX(rect) + padding.right;
        CGFloat midX = (maxX - minX) / 2 + minX;
        CGFloat minY = rect.origin.y - padding.top;
        CGFloat maxY = CGRectGetMaxY(rect) + padding.bottom;
        CGFloat midY = (maxY - minY) / 2 + minY;
        
        CGPathMoveToPoint(highlightPath, &affine, minX, midY);
        CGPathAddArcToPoint(highlightPath, &affine, minX, maxY, midX, maxY, kCornerRadius);
        CGPathAddArcToPoint(highlightPath, &affine, maxX, maxY, maxX, midY, kCornerRadius);
        CGPathAddArcToPoint(highlightPath, &affine, maxX, minY, midX, minY, kCornerRadius);
        CGPathAddArcToPoint(highlightPath, &affine, minX, minY, minX, midY, kCornerRadius);
        CGPathCloseSubpath(highlightPath);
    }
    
    CGContextAddPath(ctx, highlightPath);
    CGContextSetFillColorWithColor(ctx, self.highlightColor);
    CGContextDrawPath(ctx, kCGPathFill);
    CGPathRelease(highlightPath);
}

- (CALayer *)hitTest:(CGPoint)p
{
    // Don't handle taps
    return nil;
}

@end



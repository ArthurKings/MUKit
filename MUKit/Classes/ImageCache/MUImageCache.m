//
//  MUImageCache.m
//  MUKit_Example
//
//  Created by Jekity on 2018/7/30.
//  Copyright © 2018年 Jeykit. All rights reserved.
//

#import "MUImageCache.h"
#import "MUImageDataFileManager.h"
#import "MUImageRetrieveOperation.h"
#import "MUImageDecoder.h"
#import "MUImageEncoder.h"

#define kImageInfoIndexFileName 0
#define kImageInfoIndexContentType 1
#define kImageInfoIndexWidth 2
#define kImageInfoIndexHeight 3
#define kImageInfoIndexLock 4

@interface MUImageCache ()
@property (nonatomic, strong) MUImageDecoder* decoder;
@property (nonatomic,assign ) BOOL savedFile;
@end

@implementation MUImageCache {
    NSLock* _lock;
    NSString* _metaPath;
    
    NSMutableDictionary* _images;
    NSMutableDictionary* _imagesMetaData;
    NSMutableDictionary* _addingImages;
    NSOperationQueue* _retrievingQueue;
}

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    static MUImageCache* __instance = nil;
    dispatch_once(&onceToken, ^{
        NSString *metaPath = [[MUImageCacheUtils directoryPath] stringByAppendingPathComponent:@"/__images"];
        __instance = [[[self class] alloc] initWithMetaPath:metaPath];
    });
    
    return __instance;
}



- (instancetype)initWithMetaPath:(NSString*)metaPath
{
    if (self = [super init]) {
        _lock = [[NSLock alloc] init];
        _addingImages = [[NSMutableDictionary alloc] init];
        _maxCachedBytes = 1024 * 1024 * 512;
        _retrievingQueue = [NSOperationQueue new];
        _retrievingQueue.qualityOfService = NSQualityOfServiceUserInteractive;
        _retrievingQueue.maxConcurrentOperationCount = 6;
        _savedFile = YES;
#ifdef FLYIMAGE_WEBP
        _autoConvertWebP = NO;
        _compressionQualityForWebP = 0.8;
#endif
        
        _metaPath = [metaPath copy];
        NSString* folderPath = [[_metaPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"/files"];
        self.dataFileManager = [[MUImageDataFileManager alloc] initWithFolderPath:folderPath];
        
        _metaPath = [metaPath copy];
        [self loadMetadata];
        
        _decoder = [[MUImageDecoder alloc] init];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onWillTerminate)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onDidEnterBackground)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }
    return self;
}
- (void)loadMetadata
{
    // load content from index file
    NSError* error;
    NSData* metadataData = [NSData dataWithContentsOfURL:[NSURL fileURLWithPath:_metaPath] options:NSDataReadingMappedAlways error:&error];
    if (error != nil || metadataData == nil) {
        [self createMetadata];
        return;
    }
    
    NSDictionary* parsedObject = (NSDictionary*)[NSJSONSerialization JSONObjectWithData:metadataData options:kNilOptions error:&error];
    if (error != nil || parsedObject == nil) {
        [self createMetadata];
        return;
    }
    
    _images = [NSMutableDictionary dictionaryWithDictionary:parsedObject];
    _imagesMetaData = [NSMutableDictionary dictionaryWithDictionary:parsedObject];
}

- (void)createMetadata
{
    _images = [NSMutableDictionary dictionaryWithCapacity:100];
    _imagesMetaData = [NSMutableDictionary dictionaryWithCapacity:100];
}
#pragma mark - LifeCircle

- (void)dealloc
{
    [_retrievingQueue cancelAllOperations];
    
    [self cleanCachedImages];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onWillTerminate
{
    [self cleanCachedImages];
}

- (void)onDidEnterBackground
{
    [self cleanCachedImages];
}

- (void)cleanCachedImages
{
    [_retrievingQueue cancelAllOperations];
    
    __weak __typeof__(self) weakSelf = self;
    [self.dataFileManager calculateSizeWithCompletionBlock:^(NSUInteger fileCount, NSUInteger totalSize) {
        if ( weakSelf.maxCachedBytes > totalSize ) {
            return;
        }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
        NSMutableArray *lockedFilenames = [NSMutableArray array];
        NSMutableArray *lockedKeys = [NSMutableArray array];
        @synchronized (_images) {
            for (NSString *key in _images) {
                NSArray *imageInfo = [_images objectForKey:key];
                if ( [imageInfo count] > kImageInfoIndexLock && [[imageInfo objectAtIndex:kImageInfoIndexLock] boolValue] ){
                    [lockedFilenames addObject:[imageInfo objectAtIndex:kImageInfoIndexFileName]];
                    [lockedKeys addObject:key];
                }
            }
        }
        
        [weakSelf.dataFileManager purgeWithExceptions:lockedFilenames
                                               toSize:weakSelf.maxCachedBytes/2
                                            completed:^(NSUInteger fileCount, NSUInteger totalSize) {
                                                
                                                // remove unlock keys
                                                @synchronized (_images) {
                                                    NSArray *allKeys = [_images allKeys];
                                                    for (NSString *key in allKeys) {
                                                        if ( [lockedKeys indexOfObject:key] == NSNotFound ) {
                                                            [_images removeObjectForKey:key];
                                                            [_imagesMetaData removeObjectForKey:key];
                                                        }
                                                    }
                                                }
                                                
                                                [weakSelf saveMetadata];
                                            }];
    }];
}

#pragma mark - APIs
- (void)addImageWithKey:(NSString*)key
               filename:(NSString*)filename
              completed:(MUImageCacheRetrieveBlock)completed
{
    [self addImageWithKey:key filename:filename drawSize:CGSizeZero contentsGravity:kCAGravityResizeAspect cornerRadius:0 completed:completed];
}

- (void)addImageWithKey:(NSString*)key
               filename:(NSString*)filename
               drawSize:(CGSize)drawSize
        contentsGravity:(NSString* const)contentsGravity
           cornerRadius:(CGFloat)cornerRadius
              completed:(MUImageCacheRetrieveBlock)completed
{
    
    NSParameterAssert(key != nil);
    NSParameterAssert(filename != nil);
    
    if ([self isImageExistWithKey:key] && completed != nil) {
        [self asyncGetImageWithKey:key
                          drawSize:drawSize
                   contentsGravity:contentsGravity
                      cornerRadius:cornerRadius
                         completed:completed];
        return;
    }
    
    // ignore draw size when add images
    @synchronized(_addingImages)
    {
        if ([_addingImages objectForKey:key] == nil) {
            NSMutableArray* blocks = [NSMutableArray array];
            if (completed != nil) {
                [blocks addObject:completed];
            }
            
            [_addingImages setObject:blocks forKey:key];
        } else {
            // waiting for drawing
            NSMutableArray* blocks = [_addingImages objectForKey:key];
            if (completed != nil) {
                [blocks addObject:completed];
            }
            
            return;
        }
    }
    
    [self doAddImageWithKey:[key copy]
                   filename:[filename copy]
                   drawSize:drawSize
            contentsGravity:contentsGravity
               cornerRadius:cornerRadius
                  completed:completed];
}

- (void)doAddImageWithKey:(NSString*)key
                 filename:(NSString*)filename
                 drawSize:(CGSize)drawSize
          contentsGravity:(NSString* const)contentsGravity
             cornerRadius:(CGFloat)cornerRadius
                completed:(MUImageCacheRetrieveBlock)completed
{
    
    static dispatch_queue_t __drawingQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *name = [NSString stringWithFormat:@"com.MUImage.addimage.%@", [[NSUUID UUID] UUIDString]];
        __drawingQueue = dispatch_queue_create([name cStringUsingEncoding:NSASCIIStringEncoding], NULL);
    });
    
    __weak typeof(self)weakSelf = self;
    dispatch_async(__drawingQueue, ^{
        __strong typeof(weakSelf)self = weakSelf;
        // get image meta
        CGSize imageSize = CGSizeZero;
        MUImageContentType contentType;
        @autoreleasepool {
            NSString *filePath = [self.dataFileManager.folderPath stringByAppendingPathComponent:filename];
            NSData *fileData = [NSData dataWithContentsOfFile:filePath];
            contentType = [MUImageCacheUtils contentTypeForImageData:fileData];
            UIImage *image = nil;
            if ( contentType == MUImageContentTypeWebP ) {
#ifdef FLYIMAGE_WEBP
                if ( _autoConvertWebP ) {
                    // Decode WebP
                    BOOL hasAlpha;
                    image = [_decoder imageWithWebPData:fileData hasAlpha:&hasAlpha];
                    if ( image != nil ) {
                        NSData *compresstionImageData;
                        if ( hasAlpha ) {
                            // Convert WebP to PNG
                            compresstionImageData = UIImagePNGRepresentation(image);
                            if ( compresstionImageData != nil ){
                                contentType = ImageContentTypePNG;
                            }
                        }else{
                            // Convert WebP to JPEG
                            compresstionImageData = UIImageJPEGRepresentation(image, self.compressionQualityForWebP);
                            if ( compresstionImageData != nil ){
                                contentType = ImageContentTypeJPEG;
                            }
                        }
                        
                        // save image into disk
                        if ( compresstionImageData != nil ){
                            NSString *filePath = [self.dataFileManager.folderPath stringByAppendingPathComponent:filename];
                            [compresstionImageData writeToFile:filePath atomically:YES];
                        }
                    }
                }
#endif
            }else{
                // read image meta, not data
                //                NSData *data = [NSData dataWithContentsOfFile:filePath];
                if (fileData) {
                    [_lock lock];
                    image = [UIImage imageWithData:fileData];
                    imageSize = image.size;
                    [_lock unlock];
                }
                //                image = [UIImage imageWithContentsOfFile:filePath];
                
            }
            
            //            imageSize = image.size;
        }
        
        [self.dataFileManager addExistFileName:filename];
        [_lock lock];
        MUImageDataFile *dataFile = [self.dataFileManager retrieveFileWithName:filename];
        if ( [dataFile open] == false ) {
            [_lock unlock];
            [self afterAddImage:nil key:key filePath:dataFile.filePath];
            return;
        }
        
        // save data file's param
        void *bytes = dataFile.address;
        size_t fileLength = (size_t)dataFile.fileLength;
        
        // callback with image
        
        UIImage *decodeImage = [self.decoder imageWithFile:(__bridge void *)(dataFile)
                                               contentType:contentType
                                                     bytes:bytes
                                                    length:fileLength
                                                  drawSize:CGSizeEqualToSize(drawSize, CGSizeZero) ? imageSize : drawSize
                                           contentsGravity:contentsGravity
                                              cornerRadius:cornerRadius];
        [_lock unlock];
        [self afterAddImage:decodeImage key:key filePath:dataFile.filePath];
        
        if (contentType == MUImageContentTypeUnknown) {
            return ;
        }
        
        @synchronized (_images) {
            // path, width, height, length
            NSArray *imageInfo = @[ filename,
                                    @(contentType),
                                    @(imageSize.width),
                                    @(imageSize.height) ];
            
            [_images setObject:imageInfo forKey:key];
            [_imagesMetaData setObject:imageInfo forKey:key];
        }
        if (self.savedFile) {
            self.savedFile = NO;
        }
    });
}

- (void)afterAddImage:(UIImage*)image
                  key:(NSString*)key
             filePath:(NSString *)filePath
{
    NSArray* blocks = nil;
    @synchronized(_addingImages)
    {
        blocks = [[_addingImages objectForKey:key] copy];
        [_addingImages removeObjectForKey:key];
    }
    
    for ( MUImageCacheRetrieveBlock block in blocks) {
        block( key, image ,filePath);
    }
}

- (void)removeImageWithKey:(NSString*)key
{
    NSString* fileName = nil;
    @synchronized(_images)
    {
        
        NSArray* imageInfo = [_images objectForKey:key];
        if (imageInfo == nil) {
            return;
        }
        
        // if locked
        if ([imageInfo count] > kImageInfoIndexLock && [[imageInfo objectAtIndex:kImageInfoIndexLock] boolValue] == YES) {
            return;
        }
        
        [_images removeObjectForKey:key];
        [_imagesMetaData removeObjectForKey:key];
        fileName = [imageInfo firstObject];
    }
    
    if (fileName != nil) {
        [self.dataFileManager removeFileWithName:fileName];
    }
}

- (void)changeImageKey:(NSString*)oldKey newKey:(NSString*)newKey
{
    @synchronized(_images)
    {
        id imageInfo = [_images objectForKey:oldKey];
        if (imageInfo == nil) {
            return;
        }
        
        [_images setObject:imageInfo forKey:newKey];
        [_images removeObjectForKey:oldKey];
        
        [_imagesMetaData setObject:imageInfo forKey:newKey];
        [_imagesMetaData removeObjectForKey:oldKey];
    }
}

- (BOOL)isImageExistWithKey:(NSString*)key
{
    NSParameterAssert(key != nil);
    
    @synchronized(_images)
    {
        return [_images objectForKey:key] != nil;
    }
}

- (void)asyncGetImageWithKey:(NSString*)key completed:(MUImageCacheRetrieveBlock)completed
{
    [self asyncGetImageWithKey:key drawSize:CGSizeZero contentsGravity:kCAGravityResizeAspect cornerRadius:0 completed:completed];
}

- (void)asyncGetImageWithKey:(NSString*)key
                    drawSize:(CGSize)drawSize
             contentsGravity:(NSString* const)contentsGravity
                cornerRadius:(CGFloat)cornerRadius
                   completed:(MUImageCacheRetrieveBlock)completed
{
    NSParameterAssert(key != nil);
    NSParameterAssert(completed != nil);
    
    NSArray* imageInfo;
    @synchronized(_images)
    {
        imageInfo = [_images objectForKey:key];
    }
    
    if (imageInfo == nil || [imageInfo count] <= kImageInfoIndexHeight) {
        completed(key, nil ,nil);
        return;
    }
    
    // filename, width, height, length
    NSString* filename = [imageInfo firstObject];
    MUImageDataFile* dataFile = [self.dataFileManager retrieveFileWithName:filename];
    if (dataFile == nil) {
        completed(key, nil ,nil);
        return;
    }
    
    // if the image is retrieving, then just add the block, no need to create a new operation.
    
    NSArray *tempArray = [_retrievingQueue.operations copy];
    for (MUImageRetrieveOperation* operation in tempArray) {
        if ([operation.name isEqualToString:key]) {
            [operation addBlock:completed];
            return;
        }
    }
    
    CGSize imageSize = drawSize;
    if (drawSize.width == 0 && drawSize.height == 0) {
        CGFloat imageWidth = [[imageInfo objectAtIndex:kImageInfoIndexWidth] floatValue];
        CGFloat imageHeight = [[imageInfo objectAtIndex:kImageInfoIndexHeight] floatValue];
        imageSize = CGSizeMake(imageWidth, imageHeight);
    }
    MUImageContentType contentType = [[imageInfo objectAtIndex:kImageInfoIndexContentType] integerValue];
    
    __weak __typeof__(self) weakSelf = self;
    MUImageRetrieveOperation* operation = [[MUImageRetrieveOperation alloc] initWithRetrieveBlock:^UIImage * {
        if ( [dataFile open] == NO) {
            return nil;
        }
        
        return [weakSelf.decoder imageWithFile:(__bridge void *)(dataFile)
                                   contentType:contentType
                                         bytes:dataFile.address
                                        length:(size_t)dataFile.fileLength
                                      drawSize:CGSizeEqualToSize(drawSize, CGSizeZero) ? imageSize : drawSize
                               contentsGravity:contentsGravity
                                  cornerRadius:cornerRadius];
    }];
    operation.name = key;
    operation.filePath = dataFile.filePath;
    [operation addBlock:completed];
    [_retrievingQueue addOperation:operation];
}

- (void)cancelGetImageWithKey:(NSString*)key
{
    NSParameterAssert(key != nil);
    
    for (MUImageRetrieveOperation* operation in _retrievingQueue.operations) {
        if (!operation.cancelled && !operation.finished && [operation.name isEqualToString:key]) {
            [operation cancel];
            return;
        }
    }
}

- (void)purge
{
    
    NSMutableArray* lockedFilenames = [NSMutableArray array];
    @synchronized(_images)
    {
        NSMutableArray* lockedKeys = [NSMutableArray array];
        for (NSString* key in _images) {
            NSArray* imageInfo = [_images objectForKey:key];
            if ([imageInfo count] > kImageInfoIndexLock && [[imageInfo objectAtIndex:kImageInfoIndexLock] boolValue]) {
                [lockedFilenames addObject:[imageInfo objectAtIndex:kImageInfoIndexFileName]];
                [lockedKeys addObject:key];
            }
        }
        
        // remove unlock keys
        NSArray* allKeys = [_images allKeys];
        for (NSString* key in allKeys) {
            if ([lockedKeys indexOfObject:key] == NSNotFound) {
                [_images removeObjectForKey:key];
                [_imagesMetaData removeObjectForKey:key];
            }
        }
    }
    
    [_retrievingQueue cancelAllOperations];
    
    @synchronized(_addingImages)
    {
        for (NSString* key in _addingImages) {
            NSArray* blocks = [_addingImages objectForKey:key];
            dispatch_main_async_safe(^{
                for ( MUImageCacheRetrieveBlock block in blocks) {
                    block( key, nil ,nil);
                }
            });
        }
        
        [_addingImages removeAllObjects];
    }
    
    // remove files
    [self.dataFileManager purgeWithExceptions:lockedFilenames toSize:0 completed:nil];
    
    [self saveMetadata];
}

- (NSString*)imagePathWithKey:(NSString*)key
{
    NSParameterAssert(key != nil);
    
    @synchronized(_images)
    {
        NSArray* fileInfo = [_images objectForKey:key];
        if ([fileInfo firstObject] == nil) {
            return nil;
        }
        
        NSString* filename = [fileInfo objectAtIndex:kImageInfoIndexFileName];
        return [self.dataFileManager.folderPath stringByAppendingPathComponent:filename];
    }
}

// 锁住文件，不能被回收
- (void)protectFileWithKey:(NSString*)key
{
    NSParameterAssert(key != nil);
    
    if (![self isImageExistWithKey:key]) {
        return;
    }
    
    @synchronized(_images)
    {
        NSArray* fileInfo = [_images objectForKey:key];
        if ([fileInfo firstObject] == nil) {
            return;
        }
        
        // alread locked
        if ([fileInfo count] > kImageInfoIndexLock && [[fileInfo objectAtIndex:kImageInfoIndexLock] boolValue]) {
            return;
        }
        
        // name, type, width, height, lock
        NSMutableArray* newFileInfo = [NSMutableArray arrayWithArray:[fileInfo subarrayWithRange:NSMakeRange(0, kImageInfoIndexLock)]];
        [newFileInfo addObject:@(1)];
        [_images setObject:newFileInfo forKey:key];
        [_imagesMetaData setObject:newFileInfo forKey:key];
        
        [self saveMetadata];
    }
}

// 解锁文件，可以被回收
- (void)unProtectFileWithKey:(NSString*)key
{
    NSParameterAssert(key != nil);
    
    if (![self isImageExistWithKey:key]) {
        return;
    }
    
    @synchronized(_images)
    {
        NSArray* fileInfo = [_images objectForKey:key];
        if ([fileInfo firstObject] == nil) {
            return;
        }
        
        // alread unlocked
        if ([fileInfo count] <= kImageInfoIndexLock) {
            return;
        }
        
        // name, type, width, height
        NSArray* newFileInfo = [fileInfo subarrayWithRange:NSMakeRange(0, kImageInfoIndexLock)];
        [_images setObject:newFileInfo forKey:key];
        [_imagesMetaData setObject:newFileInfo forKey:key];
        
        [self saveMetadata];
    }
}

#pragma mark - Working with Metadata
- (void)saveMetadata
{
    static dispatch_queue_t __metadataQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *name = [NSString stringWithFormat:@"com.muimage.iconmeta.%@", [[NSUUID UUID] UUIDString]];
        __metadataQueue = dispatch_queue_create([name cStringUsingEncoding:NSASCIIStringEncoding], NULL);
    });
    
    dispatch_async(__metadataQueue, ^{
        [_lock lock];
        NSArray *meta = [_imagesMetaData mutableCopy];
        [_lock unlock];
        NSData *data = [NSJSONSerialization dataWithJSONObject:meta options:kNilOptions error:NULL];
        BOOL fileWriteResult = [data writeToFile:_metaPath atomically:YES];
        if (fileWriteResult == NO) {
            MUImageErrorLog(@"couldn't save metadata");
        }
        
        
    });
}

#pragma clang diagnostic pop

//auto save metas when runloop in free time
- (void)commit{
    if (self.savedFile == NO) {
        self.savedFile = YES;
        [self saveMetadata];
    }
}
@end


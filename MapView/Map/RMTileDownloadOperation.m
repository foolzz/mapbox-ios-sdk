//
//  RMTileDownloadOperation.m
//  MapView
//
//  Created by David Haynes on 31/03/2015.
//
//

#import "RMTileDownloadOperation.h"
#import "RMAbstractWebMapSource.h"
#import "RMConfiguration.h"
#import "RMTileCache.h"
#import "NSURLSession+RMUserAgent.h"
#import "NSURLRequest+RMUserAgent.h"

#define HTTP_404_NOT_FOUND 404
#define HTTP_204_NO_CONTENT 204

@interface RMTileDownloadOperation ()

@property (nonatomic, assign) RMTile tile;
@property (nonatomic, strong) id<RMTileSource> tileSource;
@property (nonatomic, strong) RMTileCache *tileCache;
@property (nonatomic, assign) NSUInteger retryCount;
@property (nonatomic, assign) NSTimeInterval requestTimeoutSeconds;
@property (nonatomic, strong) UIImage *image;

@end

@implementation RMTileDownloadOperation

- (id)initWithTile:(RMTile)tile
     forTileSource:(id<RMTileSource>)source
        usingCache:(RMTileCache *)cache
boundsInScrollView:(CGRect)bounds
        retryCount:(NSUInteger)retryCount
           timeout:(NSTimeInterval)timeout
{
    self = [super init];
    if (self) {
        NSAssert([source isKindOfClass:[RMAbstractWebMapSource class]], @"Cannot download from non-web tile source");
        _tile = tile;
        _tileSource = source;
        _tileCache = cache;
        _requestTimeoutSeconds = timeout;
        _retryCount = retryCount;
        _boundsInScrollViewContent = bounds;
    }
    return self;
}

- (void)main
{
    if (!self.tileSource)
    {
        [self cancel];
    }

    if ([self isCancelled])
    {
        return;
    }

    if (self.tileSource.isHidden)
    {
        [self cancel];
    }

    UIImage *image = nil;

    self.tile = [self.tileSource.mercatorToTileProjection normaliseTile:self.tile];

    if (self.tileSource.isCacheable)
    {
        image = [self.tileCache cachedImage:self.tile withCacheKey:self.tileSource.uniqueTilecacheKey];

        if (image)
        {
            self.image = image;
            return;
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^(void)
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:RMTileRequested object:[NSNumber numberWithUnsignedLongLong:RMTileKey(self.tile)]];
    });

    NSURL *tileURL = [(RMAbstractWebMapSource *)self.tileSource URLForTile:self.tile];

    if (!tileURL)
    {
        [self cancel];
    }
    else {
        for (NSUInteger try = 0; image == nil && try < self.retryCount; ++try)
        {
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:tileURL];
            request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
            NSError *error = nil;
            NSURLResponse *urlResponse = nil;
            NSData *fetchedData = [NSURLSession rm_fetchDataSynchronouslyWithRequest:request error:&error response:&urlResponse];
            NSHTTPURLResponse *response = [urlResponse isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)urlResponse : nil;
            self.response = response;
            self.image = [UIImage imageWithData:fetchedData];

            if (response.statusCode == HTTP_404_NOT_FOUND)
            {
                break;
            } else if (response.statusCode == HTTP_204_NO_CONTENT) { // Return default tile image in case HTTP 204 is found
                self.image = [(RMAbstractWebMapSource *)self.tileSource defaultImageForZoomLevel:self.tile.zoom];
            }

            if (!self.image || error != nil)
            {
                if (error != nil)
                {
                    self.error = error;
                } else
                {
                    self.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil];
                }
                [self cancel];
            }

            if (self.image && self.tileSource.isCacheable)
            {
                if (self.image)
                {
                    [self.tileCache addImage:self.image forTile:self.tile withCacheKey:self.tileSource.uniqueTilecacheKey];
                }
                dispatch_async(dispatch_get_main_queue(), ^(void)
                {
                    [[NSNotificationCenter defaultCenter] postNotificationName:RMTileRetrieved object:[NSNumber numberWithUnsignedLongLong:RMTileKey(self.tile)]];
                });
            }
        }
    }
}

- (BOOL)isEqual:(id)other
{
    RMTileDownloadOperation *otherOperation = (RMTileDownloadOperation *)other;
    if (other == self) {
        return YES;
    }
    else if(self.tile.x == otherOperation.tile.x \
           && self.tile.y == otherOperation.tile.y \
           && self.tile.zoom == otherOperation.tile.zoom \
           && [self.tileSource isEqual:otherOperation.tileSource]) {
        return YES;
    }
    else {
        return NO;
    }
}

- (NSUInteger)hash
{
    return self.tile.x ^ self.tile.y ^ self.tile.zoom ^ self.tileSource.hash;
}


@end

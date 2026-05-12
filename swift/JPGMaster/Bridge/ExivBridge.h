// ExivBridge.h
// Objective-C wrapper around libexiv2 so Swift can call its C++ API.
// The .mm implementation file uses Objective-C++ to bridge across the
// language boundary. Swift sees only this Objective-C interface.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Captured metadata from a source image.
/// Holds raw byte buffers in libexiv2's internal exchange format so the
/// values can be re-applied to a destination file without lossy conversion.
@interface ExivCapturedMetadata : NSObject
@property (nonatomic, readonly, nullable) NSData *exifData;
@property (nonatomic, readonly, nullable) NSData *iptcData;
@property (nonatomic, readonly, nullable) NSString *xmpPacket;
@property (nonatomic, readonly, nullable) NSData *iccProfile;
@property (nonatomic, readonly) BOOL isEmpty;
@end

/// Errors emitted by ExivBridge.
extern NSErrorDomain const ExivBridgeErrorDomain;
typedef NS_ERROR_ENUM(ExivBridgeErrorDomain, ExivBridgeError) {
    ExivBridgeErrorOpenFailed = 1,
    ExivBridgeErrorReadFailed,
    ExivBridgeErrorWriteFailed,
    ExivBridgeErrorUnsupported,
};

@interface ExivBridge : NSObject

/// Read EXIF / IPTC / XMP / ICC metadata from a source file.
/// Returns nil and populates `error` on failure.
+ (nullable ExivCapturedMetadata *)readMetadataFromPath:(NSString *)path
                                                  error:(NSError * _Nullable * _Nullable)error;

/// Write captured metadata into a destination file, replacing any existing
/// metadata in the destination.
/// Returns YES on success, NO with `error` on failure.
+ (BOOL)writeMetadata:(ExivCapturedMetadata *)metadata
               toPath:(NSString *)path
                error:(NSError * _Nullable * _Nullable)error;

/// Strip all EXIF / IPTC / XMP metadata from a file. ICC profile is left in
/// place because it lives in the image data stream, not the metadata blocks.
+ (BOOL)stripMetadataAtPath:(NSString *)path
                      error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END

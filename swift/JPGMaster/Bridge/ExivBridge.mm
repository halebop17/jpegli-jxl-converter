// ExivBridge.mm
// Objective-C++ implementation. Bridges libexiv2 (C++) to Swift via an
// Objective-C interface. All exiv2 types live in this file; nothing C++
// leaks into the Swift-visible header.

#import "ExivBridge.h"

#include <exiv2/exiv2.hpp>
#include <string>
#include <vector>
#include <stdexcept>

NSErrorDomain const ExivBridgeErrorDomain = @"ExivBridgeErrorDomain";

// libexiv2 XmpParser uses a process-global Adobe XMP toolkit instance that
// is NOT thread-safe unless `XmpParser::initialize()` is called once before
// any worker touches it. Without it, concurrent `readMetadata()` calls on
// PNG/JPEG files race inside the XMP parser and crash with EXC_BAD_ACCESS.
//
// We also wrap every call through a serial NSLock — even with the parser
// initialised, ImageFactory::open and a few other entry points share file-
// system / mutable-state behaviour that we don't want to race on. Metadata
// I/O is microseconds per file, so serialising it is invisible next to
// cjpegli encoding (which stays parallel).
static NSLock *ExivLock(void) {
    static NSLock *lock = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lock = [[NSLock alloc] init];
        Exiv2::XmpParser::initialize();
        std::atexit([]{ Exiv2::XmpParser::terminate(); });
    });
    return lock;
}

// ─────────────────────────────────────────────────────────────────────────
// ExivCapturedMetadata
// ─────────────────────────────────────────────────────────────────────────

@interface ExivCapturedMetadata ()
@property (nonatomic, copy, nullable) NSData *exifData;
@property (nonatomic, copy, nullable) NSData *iptcData;
@property (nonatomic, copy, nullable) NSString *xmpPacket;
@property (nonatomic, copy, nullable) NSData *iccProfile;
@end

@implementation ExivCapturedMetadata

- (BOOL)isEmpty {
    return self.exifData == nil
        && self.iptcData == nil
        && (self.xmpPacket == nil || self.xmpPacket.length == 0)
        && self.iccProfile == nil;
}

@end

// ─────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────

static NSError *MakeError(ExivBridgeError code, NSString *description) {
    return [NSError errorWithDomain:ExivBridgeErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: description ?: @"unknown error" }];
}

static NSData *DataFromVector(const Exiv2::byte *bytes, size_t len) {
    if (!bytes || len == 0) return nil;
    return [NSData dataWithBytes:bytes length:len];
}

// Serialize the EXIF block to its raw on-disk byte representation so it can
// be transplanted into a different file later. Uses ExifParser::encode which
// produces the canonical TIFF-encoded EXIF blob.
static NSData *SerializeExif(Exiv2::Image &image) {
    Exiv2::ExifData &exifData = const_cast<Exiv2::ExifData &>(image.exifData());
    if (exifData.empty()) return nil;
    Exiv2::Blob blob;
    try {
        Exiv2::ExifParser::encode(blob, Exiv2::bigEndian, exifData);
    } catch (const Exiv2::Error &) {
        return nil;
    }
    if (blob.empty()) return nil;
    return [NSData dataWithBytes:blob.data() length:blob.size()];
}

static NSData *SerializeIptc(Exiv2::Image &image) {
    const Exiv2::IptcData &iptcData = image.iptcData();
    if (iptcData.empty()) return nil;
    try {
        Exiv2::DataBuf buf = Exiv2::IptcParser::encode(iptcData);
        if (buf.size() == 0) return nil;
        return DataFromVector(buf.c_data(), buf.size());
    } catch (const Exiv2::Error &) {
        return nil;
    }
}

static NSString *SerializeXmp(Exiv2::Image &image) {
    const Exiv2::XmpData &xmpData = image.xmpData();
    if (xmpData.empty() && image.xmpPacket().empty()) return nil;
    std::string packet;
    if (!image.xmpPacket().empty()) {
        packet = image.xmpPacket();
    } else {
        if (Exiv2::XmpParser::encode(packet, xmpData) != 0) return nil;
    }
    if (packet.empty()) return nil;
    return [NSString stringWithUTF8String:packet.c_str()];
}

static NSData *SerializeIcc(Exiv2::Image &image) {
    if (!image.iccProfileDefined()) return nil;
    const Exiv2::DataBuf &profile = image.iccProfile();
    if (profile.size() == 0) return nil;
    return DataFromVector(profile.c_data(), profile.size());
}

// Apply captured metadata onto a destination image. The destination is
// expected to support EXIF/IPTC/XMP/ICC; libexiv2 will silently skip any
// type the format doesn't support (e.g. IPTC into a JXL container).
static void ApplyMetadata(Exiv2::Image &dest, ExivCapturedMetadata *src) {
    if (src.exifData != nil && src.exifData.length > 0) {
        try {
            Exiv2::ExifData exifData;
            Exiv2::ExifParser::decode(exifData,
                                      static_cast<const Exiv2::byte *>(src.exifData.bytes),
                                      src.exifData.length);
            dest.setExifData(exifData);
        } catch (const Exiv2::Error &) {}
    }
    if (src.iptcData != nil && src.iptcData.length > 0) {
        try {
            Exiv2::IptcData iptcData;
            int rc = Exiv2::IptcParser::decode(iptcData,
                                               static_cast<const Exiv2::byte *>(src.iptcData.bytes),
                                               src.iptcData.length);
            if (rc == 0) dest.setIptcData(iptcData);
        } catch (const Exiv2::Error &) {}
    }
    if (src.xmpPacket != nil && src.xmpPacket.length > 0) {
        try {
            std::string packet = std::string([src.xmpPacket UTF8String] ?: "");
            dest.setXmpPacket(packet);
            Exiv2::XmpData xmp;
            if (Exiv2::XmpParser::decode(xmp, packet) == 0) {
                dest.setXmpData(xmp);
            }
        } catch (const Exiv2::Error &) {}
    }
    if (src.iccProfile != nil && src.iccProfile.length > 0) {
        try {
            Exiv2::DataBuf buf(static_cast<const Exiv2::byte *>(src.iccProfile.bytes),
                               src.iccProfile.length);
            dest.setIccProfile(std::move(buf));
        } catch (const Exiv2::Error &) {}
    }
}

// ─────────────────────────────────────────────────────────────────────────
// ExivBridge
// ─────────────────────────────────────────────────────────────────────────

@implementation ExivBridge

+ (nullable ExivCapturedMetadata *)readMetadataFromPath:(NSString *)path
                                                  error:(NSError **)error {
    NSLock *lock = ExivLock();
    [lock lock];
    @try {
        Exiv2::Image::UniquePtr img = Exiv2::ImageFactory::open(std::string([path UTF8String]));
        if (img.get() == nullptr) {
            if (error) *error = MakeError(ExivBridgeErrorOpenFailed, @"could not open image");
            return nil;
        }
        img->readMetadata();

        ExivCapturedMetadata *captured = [[ExivCapturedMetadata alloc] init];
        captured.exifData   = SerializeExif(*img);
        captured.iptcData   = SerializeIptc(*img);
        captured.xmpPacket  = SerializeXmp(*img);
        captured.iccProfile = SerializeIcc(*img);
        return captured;
    } @catch (NSException *e) {
        if (error) *error = MakeError(ExivBridgeErrorReadFailed, e.reason ?: @"read failed");
        return nil;
    } @finally {
        [lock unlock];
    }
    return nil;
}

+ (BOOL)writeMetadata:(ExivCapturedMetadata *)metadata
               toPath:(NSString *)path
                error:(NSError **)error {
    if (metadata == nil || metadata.isEmpty) return YES;
    NSLock *lock = ExivLock();
    [lock lock];
    BOOL ok = NO;
    try {
        Exiv2::Image::UniquePtr img = Exiv2::ImageFactory::open(std::string([path UTF8String]));
        if (img.get() == nullptr) {
            if (error) *error = MakeError(ExivBridgeErrorOpenFailed, @"could not open destination");
            ok = NO;
        } else {
            img->readMetadata();
            ApplyMetadata(*img, metadata);
            img->writeMetadata();
            ok = YES;
        }
    } catch (const Exiv2::Error &e) {
        if (error) *error = MakeError(ExivBridgeErrorWriteFailed,
                                      [NSString stringWithUTF8String:e.what()] ?: @"write failed");
        ok = NO;
    } catch (...) {
        if (error) *error = MakeError(ExivBridgeErrorWriteFailed, @"write failed");
        ok = NO;
    }
    [lock unlock];
    return ok;
}

+ (BOOL)stripMetadataAtPath:(NSString *)path
                      error:(NSError **)error {
    NSLock *lock = ExivLock();
    [lock lock];
    BOOL ok = NO;
    try {
        Exiv2::Image::UniquePtr img = Exiv2::ImageFactory::open(std::string([path UTF8String]));
        if (img.get() == nullptr) {
            if (error) *error = MakeError(ExivBridgeErrorOpenFailed, @"could not open image");
            ok = NO;
        } else {
            img->readMetadata();
            img->clearExifData();
            img->clearIptcData();
            img->clearXmpData();
            img->clearXmpPacket();
            img->writeMetadata();
            ok = YES;
        }
    } catch (const Exiv2::Error &e) {
        if (error) *error = MakeError(ExivBridgeErrorWriteFailed,
                                      [NSString stringWithUTF8String:e.what()] ?: @"strip failed");
        ok = NO;
    }
    [lock unlock];
    return ok;
}

@end

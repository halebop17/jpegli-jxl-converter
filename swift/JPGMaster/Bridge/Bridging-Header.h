// Bridging-Header.h
// Exposes Objective-C and Objective-C++ symbols to Swift.
// The vendored C libraries (libtiff, libpng, lcms2) are imported via
// the module.modulemap, not from this header — Swift can `import CTiff`
// etc. directly. This bridging header is reserved for ObjC++ wrappers
// around C++-only libraries (libexiv2).

#ifndef JPGMaster_Bridging_Header_h
#define JPGMaster_Bridging_Header_h

#import "ExivBridge.h"

#endif /* JPGMaster_Bridging_Header_h */

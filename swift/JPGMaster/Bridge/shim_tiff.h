#ifndef JPGMaster_shim_tiff_h
#define JPGMaster_shim_tiff_h

// Thin shim that pulls in libtiff's public headers so Swift sees them
// through the CTiff module. Matches the include layout produced by
// `make install` from the vendored libtiff source.

#include <tiff.h>
#include <tiffio.h>

// Non-variadic wrappers around TIFFGetField (defined in shim_tiff_varargs.c).
// Swift cannot call variadic C functions directly, so each call is routed
// through one of these.
int TIFFGetField_uint32(TIFF *tif, uint32_t tag, uint32_t *out);
int TIFFGetField_uint16(TIFF *tif, uint32_t tag, uint16_t *out);
int TIFFGetField_extras(TIFF *tif, uint32_t tag, uint16_t *count, uint16_t **values);

#endif

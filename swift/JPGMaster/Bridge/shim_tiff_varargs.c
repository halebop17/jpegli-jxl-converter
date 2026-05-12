// shim_tiff_varargs.c
// Non-variadic wrappers around libtiff's variadic TIFFGetField so Swift
// can call them. Each wrapper is specialised to the argument type it
// extracts.

#include <tiff.h>
#include <tiffio.h>

int TIFFGetField_uint32(TIFF *tif, uint32_t tag, uint32_t *out) {
    return TIFFGetField(tif, tag, out);
}

int TIFFGetField_uint16(TIFF *tif, uint32_t tag, uint16_t *out) {
    return TIFFGetField(tif, tag, out);
}

// EXTRASAMPLES is "uint16 count, uint16* values"
int TIFFGetField_extras(TIFF *tif, uint32_t tag, uint16_t *count, uint16_t **values) {
    return TIFFGetField(tif, tag, count, values);
}

// SetField wrappers used by PNGWriter (none needed for libtiff).

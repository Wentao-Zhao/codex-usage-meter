#ifndef CM_ZSTD_H
#define CM_ZSTD_H
#include <stddef.h>
#include <stdint.h>

typedef struct CMZstdReader CMZstdReader;
CMZstdReader *CMZstdOpen(const char *path, char *error, size_t error_capacity);
// Bytes read; 0 at validated EOF; -1 on error; -2 yields after bounded input I/O.
intptr_t CMZstdRead(CMZstdReader *reader, void *output, size_t capacity);
const char *CMZstdError(CMZstdReader *reader);
uint64_t CMZstdCompressedBytesRead(CMZstdReader *reader);
void CMZstdClose(CMZstdReader *reader);
#endif

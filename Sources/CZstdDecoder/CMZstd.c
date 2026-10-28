#include "include/CMZstd.h"
#include "vendor/zstddeclib.inc"
#include <stdio.h>
#include <string.h>

struct CMZstdReader {
    FILE *file;
    ZSTD_DStream *decoder;
    unsigned char input[65536];
    ZSTD_inBuffer buffer;
    int eof;
    int frame_complete;
    uint64_t compressed_bytes;
    char error[160];
};

CMZstdReader *CMZstdOpen(const char *path, char *error, size_t error_capacity) {
    CMZstdReader *reader = calloc(1, sizeof(*reader));
    const char *message = "Cannot allocate Zstandard reader";
    if (!reader) goto fail;
    reader->file = fopen(path, "rb");
    message = "Cannot open compressed session";
    if (!reader->file) goto fail;
    reader->decoder = ZSTD_createDStream();
    message = "Cannot allocate Zstandard decoder";
    if (!reader->decoder) goto fail;
    if (ZSTD_isError(ZSTD_initDStream(reader->decoder))) goto fail;
    // Bound the history window independently of the file's decompressed size.
    size_t result = ZSTD_DCtx_setParameter(reader->decoder, ZSTD_d_windowLogMax, 23);
    message = "Cannot set Zstandard memory limit";
    if (ZSTD_isError(result)) goto fail;
    reader->buffer.src = reader->input;
    return reader;
fail:
    if (error && error_capacity) snprintf(error, error_capacity, "%s", message);
    CMZstdClose(reader);
    return NULL;
}

intptr_t CMZstdRead(CMZstdReader *reader, void *output, size_t capacity) {
    if (!reader || !output || !capacity || reader->error[0]) return -1;
    ZSTD_outBuffer decoded = {output, capacity, 0};
    int read_input = 0;
    while (decoded.pos < decoded.size) {
        if (reader->buffer.pos == reader->buffer.size && !reader->eof) {
            if (read_input) return decoded.pos ? (intptr_t)decoded.pos : -2;
            reader->buffer.size = fread(reader->input, 1, sizeof(reader->input), reader->file);
            read_input = 1;
            reader->compressed_bytes += reader->buffer.size;
            reader->buffer.pos = 0;
            if (ferror(reader->file)) {
                snprintf(reader->error, sizeof(reader->error), "Cannot read compressed session");
                return -1;
            }
            reader->eof = reader->buffer.size == 0;
        }
        if (reader->eof && reader->buffer.pos == reader->buffer.size && reader->frame_complete) break;
        size_t previous_input = reader->buffer.pos;
        size_t previous_output = decoded.pos;
        size_t result = ZSTD_decompressStream(reader->decoder, &decoded, &reader->buffer);
        if (ZSTD_isError(result)) {
            snprintf(reader->error, sizeof(reader->error), "Invalid Zstandard session (including unsupported window size)");
            return -1;
        }
        reader->frame_complete = result == 0;
        if (previous_input == reader->buffer.pos && previous_output == decoded.pos) {
            snprintf(reader->error, sizeof(reader->error), "Truncated Zstandard session");
            return -1;
        }
    }
    return (intptr_t)decoded.pos;
}

const char *CMZstdError(CMZstdReader *reader) {
    return reader ? reader->error : "Invalid Zstandard reader";
}

uint64_t CMZstdCompressedBytesRead(CMZstdReader *reader) {
    return reader ? reader->compressed_bytes : 0;
}

void CMZstdClose(CMZstdReader *reader) {
    if (!reader) return;
    ZSTD_freeDStream(reader->decoder);
    if (reader->file) fclose(reader->file);
    free(reader);
}

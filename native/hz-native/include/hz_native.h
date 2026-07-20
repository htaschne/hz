#ifndef HZ_NATIVE_H
#define HZ_NATIVE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define HZ_NATIVE_ABI_VERSION 1u

typedef enum HzNativeStatus {
    HZ_NATIVE_OK = 0,
    HZ_NATIVE_NOT_IMPLEMENTED = 1,
    HZ_NATIVE_INVALID_ARGUMENT = 2,
    HZ_NATIVE_ALLOCATION_FAILED = 3,
    HZ_NATIVE_INTERNAL_ERROR = 4
} HzNativeStatus;

typedef struct HzNativeBuffer {
    uint8_t *data;
    size_t length;
} HzNativeBuffer;

typedef struct HzNativeResult {
    HzNativeStatus status;
    HzNativeBuffer buffer;
    const char *error_message;
} HzNativeResult;

uint32_t hz_native_abi_version(void);
const char *hz_native_version_string(void);
bool hz_native_is_available(void);

HzNativeResult hz_native_compress(
    const uint8_t *input,
    size_t input_length
);

HzNativeResult hz_native_decompress(
    const uint8_t *input,
    size_t input_length
);

HzNativeResult hz_native_compress_file(
    const char *source_path,
    const char *destination_path
);

HzNativeResult hz_native_decompress_file(
    const char *source_path,
    const char *destination_path
);

// Releases Rust-owned output memory returned inside HzNativeResult.
//
// Ownership rules:
// - input pointers passed to Rust remain owned by the caller;
// - Rust never retains input pointers after a call returns;
// - non-null result.buffer.data is owned by Rust and must be released exactly
//   once by passing the whole result to hz_native_result_free;
// - error_message currently points to static storage and is not freed directly
//   by callers.
void hz_native_result_free(HzNativeResult result);

#ifdef __cplusplus
}
#endif

#endif

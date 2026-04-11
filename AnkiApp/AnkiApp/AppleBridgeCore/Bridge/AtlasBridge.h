#ifndef AtlasBridge_h
#define AtlasBridge_h
#include <stdint.h>
#include <stdbool.h>

typedef struct { uint8_t *data; size_t len; } AtlasByteBuffer;

void *atlas_init(const uint8_t *config_data, size_t config_len);
AtlasByteBuffer atlas_command(void *handle, const char *method,
                              const uint8_t *input, size_t input_len,
                              bool *is_error);
void atlas_free(void *handle);
void atlas_free_buffer(AtlasByteBuffer buf);

#endif

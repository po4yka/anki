#ifndef AnkiBridge_h
#define AnkiBridge_h

#include <stdint.h>
#include <stdbool.h>

typedef struct {
    uint8_t *data;
    size_t len;
} ByteBuffer;

void *anki_init(const uint8_t *data, size_t len);
ByteBuffer anki_command(void *backend, uint32_t service, uint32_t method,
                        const uint8_t *input, size_t input_len, bool *is_error);
void anki_free(void *backend);
void anki_free_buffer(ByteBuffer buf);

#endif

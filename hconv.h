#ifndef HCONV_H
#define HCONV_H

#include <stddef.h>
#include <stdint.h>

#define SPAN_START 0x0B
#define SPAN_END 0x01

enum encoding_mode {
    ENCODING_UTF8,
    ENCODING_MODIFIED,
    ENCODING_NBYTES
};

enum decoder_state {
    STATE_S1,
    STATE_S2,
    STATE_S3,
    STATE_S4,
    STATE_S5,
    STATE_S6,
    STATE_S7,
    STATE_S8
};

struct hconv_nbytes_decoder {
    int in_span;
    enum decoder_state state;
    uint32_t initial_cp;
    uint32_t medial_cp;
    uint32_t final_cp;
    uint32_t final_first_cp;
    uint32_t final_second_cp;
    unsigned char initial_byte;
    unsigned char vowel_first_byte;
    unsigned char final_first_byte;
    unsigned char final_second_byte;
};

typedef int (*hconv_emit_codepoint_fn)(void *ctx, uint32_t cp);

const char *hconv_error_code(void);
const char *hconv_error_detail(void);

int hconv_parse_mode(const char *text, enum encoding_mode *out_mode);
int hconv_convert(enum encoding_mode from_code, enum encoding_mode to_code,
    const unsigned char *input, size_t input_len,
    unsigned char **output, size_t *output_len);
void hconv_free(void *ptr);

void hconv_nbytes_decoder_init(struct hconv_nbytes_decoder *decoder);
int hconv_nbytes_decode_byte(struct hconv_nbytes_decoder *decoder, unsigned char byte,
    hconv_emit_codepoint_fn emit, void *ctx);
int hconv_nbytes_finish(struct hconv_nbytes_decoder *decoder,
    hconv_emit_codepoint_fn emit, void *ctx);

int hconv_map_modified_codepoint(uint32_t cp, unsigned int *out_mapped);

#endif

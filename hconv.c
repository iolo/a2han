#include "hconv.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct byte_buffer {
    unsigned char *data;
    size_t len;
    size_t cap;
};

struct codepoint_buffer {
    uint32_t *data;
    size_t len;
    size_t cap;
};

static const uint32_t L_TABLE[] = {
    0x3131, 0x3132, 0x3134, 0x3137, 0x3138, 0x3139, 0x3141,
    0x3142, 0x3143, 0x3145, 0x3146, 0x3147, 0x3148, 0x3149,
    0x314A, 0x314B, 0x314C, 0x314D, 0x314E
};

static const uint32_t V_TABLE[] = {
    0x314F, 0x3150, 0x3151, 0x3152, 0x3153, 0x3154, 0x3155,
    0x3156, 0x3157, 0x3158, 0x3159, 0x315A, 0x315B, 0x315C,
    0x315D, 0x315E, 0x315F, 0x3160, 0x3161, 0x3162, 0x3163
};

static const uint32_t T_TABLE[] = {
    0x0000, 0x3131, 0x3132, 0x3133, 0x3134, 0x3135, 0x3136,
    0x3137, 0x3139, 0x313A, 0x313B, 0x313C, 0x313D, 0x313E,
    0x313F, 0x3140, 0x3141, 0x3142, 0x3144, 0x3145, 0x3146,
    0x3147, 0x3148, 0x314A, 0x314B, 0x314C, 0x314D, 0x314E
};

static const unsigned char FINAL_LOW_BYTES[] = {
    0x00,
    0xA8, 0xA9, 0xAA, 0xAB, 0xAC, 0xAD, 0xAE,
    0xAF, 0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
    0xB7, 0xB8, 0xB9, 0xBA, 0xBB, 0xBC, 0xBD, 0xBE,
    0xBF, 0xC0, 0xC1, 0xC2
};

static char error_code[64];
static char error_detail[160];

static void set_error(const char *code, const char *detail)
{
    strncpy(error_code, code, sizeof(error_code) - 1);
    error_code[sizeof(error_code) - 1] = '\0';
    strncpy(error_detail, detail, sizeof(error_detail) - 1);
    error_detail[sizeof(error_detail) - 1] = '\0';
}

static int ensure_byte_capacity(struct byte_buffer *buffer, size_t extra)
{
    unsigned char *new_data;
    size_t new_cap;
    size_t need = buffer->len + extra;

    if (need <= buffer->cap) {
        return 1;
    }

    new_cap = buffer->cap ? buffer->cap : 256;
    while (new_cap < need) {
        new_cap *= 2;
    }

    new_data = (unsigned char *)realloc(buffer->data, new_cap);
    if (new_data == NULL) {
        set_error("out_of_memory", "could not grow byte buffer");
        return 0;
    }

    buffer->data = new_data;
    buffer->cap = new_cap;
    return 1;
}

static int byte_buffer_append(struct byte_buffer *buffer, unsigned char value)
{
    if (!ensure_byte_capacity(buffer, 1)) {
        return 0;
    }
    buffer->data[buffer->len++] = value;
    return 1;
}

#ifdef HCONV_MAIN
static int read_stdin_all(struct byte_buffer *buffer)
{
    int ch;

    while ((ch = fgetc(stdin)) != EOF) {
        if (!byte_buffer_append(buffer, (unsigned char)ch)) {
            fprintf(stderr, "out_of_memory: could not grow input buffer\n");
            return 0;
        }
    }
    return 1;
}

static int write_stdout_all(const unsigned char *data, size_t len)
{
    return len == 0 || fwrite(data, 1, len, stdout) == len;
}
#endif

static int ensure_codepoint_capacity(struct codepoint_buffer *buffer, size_t extra)
{
    uint32_t *new_data;
    size_t new_cap;
    size_t need = buffer->len + extra;

    if (need <= buffer->cap) {
        return 1;
    }

    new_cap = buffer->cap ? buffer->cap : 256;
    while (new_cap < need) {
        new_cap *= 2;
    }

    new_data = (uint32_t *)realloc(buffer->data, new_cap * sizeof(uint32_t));
    if (new_data == NULL) {
        set_error("out_of_memory", "could not grow code point buffer");
        return 0;
    }

    buffer->data = new_data;
    buffer->cap = new_cap;
    return 1;
}

static int codepoint_buffer_append(struct codepoint_buffer *buffer, uint32_t value)
{
    if (!ensure_codepoint_capacity(buffer, 1)) {
        return 0;
    }
    buffer->data[buffer->len++] = value;
    return 1;
}

static uint32_t map_base_jamo(unsigned char ch)
{
    switch (ch) {
        case 'A': return 0x3141;
        case 'B': return 0x3160;
        case 'C': return 0x314A;
        case 'D': return 0x3147;
        case 'E': return 0x3137;
        case 'F': return 0x3139;
        case 'G': return 0x314E;
        case 'H': return 0x3157;
        case 'I': return 0x3151;
        case 'J': return 0x3153;
        case 'K': return 0x314F;
        case 'L': return 0x3163;
        case 'M': return 0x3161;
        case 'N': return 0x315C;
        case 'O': return 0x3150;
        case 'P': return 0x3154;
        case 'Q': return 0x3142;
        case 'R': return 0x3131;
        case 'S': return 0x3134;
        case 'T': return 0x3145;
        case 'U': return 0x3155;
        case 'V': return 0x314D;
        case 'W': return 0x3148;
        case 'X': return 0x314C;
        case 'Y': return 0x315B;
        case 'Z': return 0x314B;
        case 'e': return 0x3138;
        case 'o': return 0x3152;
        case 'p': return 0x3156;
        case 'q': return 0x3143;
        case 'r': return 0x3132;
        case 't': return 0x3146;
        case 'w': return 0x3149;
    }
    return 0;
}

static const char *jamo_to_nbytes(uint32_t cp)
{
    switch (cp) {
        case 0x3141: return "A";
        case 0x3160: return "B";
        case 0x314A: return "C";
        case 0x3147: return "D";
        case 0x3137: return "E";
        case 0x3139: return "F";
        case 0x314E: return "G";
        case 0x3157: return "H";
        case 0x3151: return "I";
        case 0x3153: return "J";
        case 0x314F: return "K";
        case 0x3163: return "L";
        case 0x3161: return "M";
        case 0x315C: return "N";
        case 0x3150: return "O";
        case 0x3154: return "P";
        case 0x3142: return "Q";
        case 0x3131: return "R";
        case 0x3134: return "S";
        case 0x3145: return "T";
        case 0x3155: return "U";
        case 0x314D: return "V";
        case 0x3148: return "W";
        case 0x314C: return "X";
        case 0x315B: return "Y";
        case 0x314B: return "Z";
        case 0x3138: return "e";
        case 0x3152: return "o";
        case 0x3156: return "p";
        case 0x3143: return "q";
        case 0x3132: return "r";
        case 0x3146: return "t";
        case 0x3149: return "w";
        case 0x3158: return "HK";
        case 0x3159: return "HO";
        case 0x315A: return "HL";
        case 0x315D: return "NJ";
        case 0x315E: return "NP";
        case 0x315F: return "NL";
        case 0x3162: return "ML";
        case 0x3133: return "RT";
        case 0x3135: return "SW";
        case 0x3136: return "SG";
        case 0x313A: return "FR";
        case 0x313B: return "FA";
        case 0x313C: return "FQ";
        case 0x313D: return "FT";
        case 0x313E: return "FX";
        case 0x313F: return "FV";
        case 0x3140: return "FG";
        case 0x3144: return "QT";
    }
    return NULL;
}

static uint32_t map_compound_vowel(unsigned char first, unsigned char second)
{
    if (first == 'H' && second == 'K') return 0x3158;
    if (first == 'H' && second == 'O') return 0x3159;
    if (first == 'H' && second == 'L') return 0x315A;
    if (first == 'N' && second == 'J') return 0x315D;
    if (first == 'N' && second == 'P') return 0x315E;
    if (first == 'N' && second == 'L') return 0x315F;
    if (first == 'M' && second == 'L') return 0x3162;
    return 0;
}

static uint32_t map_compound_final(unsigned char first, unsigned char second)
{
    if (first == 'R' && second == 'T') return 0x3133;
    if (first == 'S' && second == 'W') return 0x3135;
    if (first == 'S' && second == 'G') return 0x3136;
    if (first == 'F' && second == 'R') return 0x313A;
    if (first == 'F' && second == 'A') return 0x313B;
    if (first == 'F' && second == 'Q') return 0x313C;
    if (first == 'F' && second == 'T') return 0x313D;
    if (first == 'F' && second == 'X') return 0x313E;
    if (first == 'F' && second == 'V') return 0x313F;
    if (first == 'F' && second == 'G') return 0x3140;
    if (first == 'Q' && second == 'T') return 0x3144;
    return 0;
}

static int is_c(unsigned char ch)
{
    switch (ch) {
        case 'R': case 'r': case 'S': case 'E': case 'e':
        case 'F': case 'A': case 'Q': case 'q': case 'T':
        case 't': case 'D': case 'W': case 'w': case 'C':
        case 'Z': case 'X': case 'V': case 'G':
            return 1;
    }
    return 0;
}

static int is_cf(unsigned char ch)
{
    switch (ch) {
        case 'R': case 'r': case 'S': case 'E': case 'F':
        case 'A': case 'Q': case 'T': case 't': case 'D':
        case 'W': case 'C': case 'Z': case 'X': case 'V':
        case 'G':
            return 1;
    }
    return 0;
}

static int is_ci(unsigned char ch)
{
    return ch == 'e' || ch == 'q' || ch == 'w';
}

static int is_v(unsigned char ch)
{
    switch (ch) {
        case 'K': case 'O': case 'I': case 'o': case 'J':
        case 'P': case 'U': case 'p': case 'H': case 'Y':
        case 'N': case 'B': case 'M': case 'L':
            return 1;
    }
    return 0;
}

static int lookup_index(const uint32_t *table, size_t count, uint32_t cp)
{
    size_t i;
    for (i = 0; i < count; ++i) {
        if (table[i] == cp) {
            return (int)i;
        }
    }
    return -1;
}

static int compose_syllable(uint32_t initial_cp, uint32_t medial_cp, uint32_t final_cp, uint32_t *out_cp)
{
    int l_index = lookup_index(L_TABLE, sizeof(L_TABLE) / sizeof(L_TABLE[0]), initial_cp);
    int v_index = lookup_index(V_TABLE, sizeof(V_TABLE) / sizeof(V_TABLE[0]), medial_cp);
    int t_index = lookup_index(T_TABLE, sizeof(T_TABLE) / sizeof(T_TABLE[0]), final_cp);

    if (l_index < 0 || v_index < 0 || t_index < 0) {
        set_error("invalid_hangul_composition", "invalid Hangul composition triple");
        return 0;
    }

    *out_cp = 0xAC00u + (uint32_t)(l_index * 21 * 28) + (uint32_t)(v_index * 28) + (uint32_t)t_index;
    return 1;
}

static int decompose_syllable(uint32_t cp, uint32_t *initial_cp, uint32_t *medial_cp, uint32_t *final_cp)
{
    uint32_t offset;
    uint32_t l_index;
    uint32_t v_index;
    uint32_t t_index;

    if (cp < 0xAC00u || cp > 0xD7A3u) {
        set_error("unsupported_unicode_codepoint", "code point is not a Hangul syllable");
        return 0;
    }

    offset = cp - 0xAC00u;
    l_index = offset / (21u * 28u);
    v_index = (offset % (21u * 28u)) / 28u;
    t_index = offset % 28u;
    *initial_cp = L_TABLE[l_index];
    *medial_cp = V_TABLE[v_index];
    *final_cp = T_TABLE[t_index];
    return 1;
}

static int write_utf8_codepoint(struct byte_buffer *out, uint32_t cp)
{
    if (cp <= 0x7Fu) {
        return byte_buffer_append(out, (unsigned char)cp);
    }
    if (cp <= 0x7FFu) {
        return byte_buffer_append(out, (unsigned char)(0xC0u | (cp >> 6)))
            && byte_buffer_append(out, (unsigned char)(0x80u | (cp & 0x3Fu)));
    }
    if (cp <= 0xFFFFu) {
        return byte_buffer_append(out, (unsigned char)(0xE0u | (cp >> 12)))
            && byte_buffer_append(out, (unsigned char)(0x80u | ((cp >> 6) & 0x3Fu)))
            && byte_buffer_append(out, (unsigned char)(0x80u | (cp & 0x3Fu)));
    }
    return byte_buffer_append(out, (unsigned char)(0xF0u | (cp >> 18)))
        && byte_buffer_append(out, (unsigned char)(0x80u | ((cp >> 12) & 0x3Fu)))
        && byte_buffer_append(out, (unsigned char)(0x80u | ((cp >> 6) & 0x3Fu)))
        && byte_buffer_append(out, (unsigned char)(0x80u | (cp & 0x3Fu)));
}

static int decode_utf8(const unsigned char *raw, size_t raw_len, struct codepoint_buffer *out)
{
    size_t i = 0;

    while (i < raw_len) {
        unsigned char lead = raw[i++];
        uint32_t cp;
        unsigned int needed;
        unsigned int j;

        if (lead < 0x80u) {
            if (!codepoint_buffer_append(out, (uint32_t)lead)) {
                return 0;
            }
            continue;
        }

        if ((lead & 0xE0u) == 0xC0u) {
            needed = 1;
            cp = (uint32_t)(lead & 0x1Fu);
        } else if ((lead & 0xF0u) == 0xE0u) {
            needed = 2;
            cp = (uint32_t)(lead & 0x0Fu);
        } else if ((lead & 0xF8u) == 0xF0u) {
            needed = 3;
            cp = (uint32_t)(lead & 0x07u);
        } else {
            set_error("invalid_utf8_input", "invalid UTF-8 lead byte");
            return 0;
        }

        if (i + needed > raw_len) {
            set_error("invalid_utf8_input", "truncated UTF-8 sequence");
            return 0;
        }

        for (j = 0; j < needed; ++j) {
            unsigned char next = raw[i++];
            if ((next & 0xC0u) != 0x80u) {
                set_error("invalid_utf8_input", "invalid UTF-8 continuation byte");
                return 0;
            }
            cp = (cp << 6) | (uint32_t)(next & 0x3Fu);
        }

        if (!codepoint_buffer_append(out, cp)) {
            return 0;
        }
    }

    return 1;
}

static int encode_utf8(const struct codepoint_buffer *in, struct byte_buffer *out)
{
    size_t i;
    for (i = 0; i < in->len; ++i) {
        if (!write_utf8_codepoint(out, in->data[i])) {
            return 0;
        }
    }
    return 1;
}

static int decode_modified(const unsigned char *raw, size_t raw_len, struct codepoint_buffer *out)
{
    size_t i;

    if ((raw_len % 2u) != 0u) {
        set_error("invalid_modified_length", "modified stream length must be even");
        return 0;
    }

    for (i = 0; i < raw_len; i += 2) {
        uint32_t code = ((uint32_t)raw[i] << 8) | (uint32_t)raw[i + 1];
        if (0x4100u <= code && code <= 0x41FFu) {
            if (!codepoint_buffer_append(out, code + 0xD000u)) {
                return 0;
            }
        } else if (0x4C00u <= code && code <= 0x77A3u) {
            if (!codepoint_buffer_append(out, code + 0x6000u)) {
                return 0;
            }
        } else {
            set_error("invalid_modified_codepoint", "invalid modified code point");
            return 0;
        }
    }

    return 1;
}

static int encode_modified(const struct codepoint_buffer *in, struct byte_buffer *out)
{
    size_t i;

    for (i = 0; i < in->len; ++i) {
        uint32_t cp = in->data[i];
        uint32_t mapped;

        if (0x1100u <= cp && cp <= 0x11FFu) {
            mapped = cp - 0xD000u;
        } else if (0xAC00u <= cp && cp <= 0xD7A3u) {
            mapped = cp - 0x6000u;
        } else {
            set_error("unsupported_unicode_codepoint", "cannot encode code point as modified");
            return 0;
        }

        if (!byte_buffer_append(out, (unsigned char)((mapped >> 8) & 0xFFu))
                || !byte_buffer_append(out, (unsigned char)(mapped & 0xFFu))) {
            return 0;
        }
    }

    return 1;
}

void hconv_nbytes_decoder_init(struct hconv_nbytes_decoder *decoder)
{
    decoder->state = STATE_S1;
    decoder->initial_cp = 0;
    decoder->medial_cp = 0;
    decoder->final_cp = 0;
    decoder->final_first_cp = 0;
    decoder->final_second_cp = 0;
    decoder->initial_byte = 0;
    decoder->vowel_first_byte = 0;
    decoder->final_first_byte = 0;
    decoder->final_second_byte = 0;
}

static int flush_nbytes_buffer(struct hconv_nbytes_decoder *decoder,
    hconv_emit_codepoint_fn emit, void *ctx)
{
    uint32_t syllable_cp;

    switch (decoder->state) {
        case STATE_S1:
            break;
        case STATE_S2:
            if (!emit(ctx, decoder->initial_cp)) {
                return 0;
            }
            break;
        case STATE_S3:
        case STATE_S6:
            if (!compose_syllable(decoder->initial_cp, decoder->medial_cp, 0, &syllable_cp)
                    || !emit(ctx, syllable_cp)) {
                return 0;
            }
            break;
        case STATE_S4:
        case STATE_S5:
        case STATE_S7:
        case STATE_S8:
            if (!compose_syllable(decoder->initial_cp, decoder->medial_cp, decoder->final_cp, &syllable_cp)
                    || !emit(ctx, syllable_cp)) {
                return 0;
            }
            break;
    }

    hconv_nbytes_decoder_init(decoder);
    return 1;
}

static void begin_new_initial(struct hconv_nbytes_decoder *decoder, unsigned char byte)
{
    decoder->initial_cp = map_base_jamo(byte);
    decoder->initial_byte = byte;
    decoder->medial_cp = 0;
    decoder->final_cp = 0;
    decoder->final_first_cp = 0;
    decoder->final_second_cp = 0;
    decoder->vowel_first_byte = 0;
    decoder->final_first_byte = 0;
    decoder->final_second_byte = 0;
    decoder->state = STATE_S2;
}

static void begin_new_medial(struct hconv_nbytes_decoder *decoder, unsigned char byte, enum decoder_state state)
{
    decoder->medial_cp = map_base_jamo(byte);
    decoder->vowel_first_byte = byte;
    decoder->final_cp = 0;
    decoder->final_first_cp = 0;
    decoder->final_second_cp = 0;
    decoder->final_first_byte = 0;
    decoder->final_second_byte = 0;
    decoder->state = state;
}

int hconv_nbytes_decode_byte(struct hconv_nbytes_decoder *decoder, unsigned char byte,
    hconv_emit_codepoint_fn emit, void *ctx)
{
    uint32_t pair_cp;
    uint32_t syllable_cp;

    if (!decoder->in_span) {
        if (byte == SPAN_START) {
            decoder->in_span = 1;
            hconv_nbytes_decoder_init(decoder);
            return 1;
        }
        return emit(ctx, (uint32_t)byte);
    }

    if (byte == SPAN_END) {
        if (!flush_nbytes_buffer(decoder, emit, ctx)) {
            return 0;
        }
        decoder->in_span = 0;
        return 1;
    }

    if (byte == SPAN_START) {
        return 1;
    }

    if (!is_c(byte) && !is_v(byte)) {
        if (!flush_nbytes_buffer(decoder, emit, ctx)) {
            return 0;
        }
        return emit(ctx, (uint32_t)byte);
    }

    switch (decoder->state) {
        case STATE_S1:
            if (is_c(byte)) {
                begin_new_initial(decoder, byte);
            } else if (!emit(ctx, map_base_jamo(byte))) {
                return 0;
            }
            return 1;

        case STATE_S2:
            if (is_v(byte)) {
                begin_new_medial(decoder, byte, STATE_S3);
            } else {
                if (!emit(ctx, decoder->initial_cp)) {
                    return 0;
                }
                begin_new_initial(decoder, byte);
            }
            return 1;

        case STATE_S3:
            pair_cp = map_compound_vowel(decoder->vowel_first_byte, byte);
            if (pair_cp != 0) {
                decoder->medial_cp = pair_cp;
                decoder->state = STATE_S6;
            } else if (is_cf(byte)) {
                decoder->final_cp = map_base_jamo(byte);
                decoder->final_first_cp = decoder->final_cp;
                decoder->final_first_byte = byte;
                decoder->state = STATE_S4;
            } else if (is_ci(byte)) {
                if (!compose_syllable(decoder->initial_cp, decoder->medial_cp, 0, &syllable_cp)
                        || !emit(ctx, syllable_cp)) {
                    return 0;
                }
                begin_new_initial(decoder, byte);
            } else {
                if (!compose_syllable(decoder->initial_cp, decoder->medial_cp, 0, &syllable_cp)
                        || !emit(ctx, syllable_cp)
                        || !emit(ctx, map_base_jamo(byte))) {
                    return 0;
                }
                hconv_nbytes_decoder_init(decoder);
            }
            return 1;

        case STATE_S4:
            pair_cp = map_compound_final(decoder->final_first_byte, byte);
            if (pair_cp != 0) {
                decoder->final_cp = pair_cp;
                decoder->final_second_cp = map_base_jamo(byte);
                decoder->final_second_byte = byte;
                decoder->state = STATE_S5;
            } else if (is_c(byte)) {
                if (!compose_syllable(decoder->initial_cp, decoder->medial_cp, decoder->final_cp, &syllable_cp)
                        || !emit(ctx, syllable_cp)) {
                    return 0;
                }
                begin_new_initial(decoder, byte);
            } else {
                if (!compose_syllable(decoder->initial_cp, decoder->medial_cp, 0, &syllable_cp)
                        || !emit(ctx, syllable_cp)) {
                    return 0;
                }
                decoder->initial_cp = decoder->final_cp;
                decoder->initial_byte = decoder->final_first_byte;
                begin_new_medial(decoder, byte, STATE_S3);
            }
            return 1;

        case STATE_S5:
            if (is_c(byte)) {
                if (!compose_syllable(decoder->initial_cp, decoder->medial_cp, decoder->final_cp, &syllable_cp)
                        || !emit(ctx, syllable_cp)) {
                    return 0;
                }
                begin_new_initial(decoder, byte);
            } else {
                if (!compose_syllable(decoder->initial_cp, decoder->medial_cp, decoder->final_first_cp, &syllable_cp)
                        || !emit(ctx, syllable_cp)) {
                    return 0;
                }
                decoder->initial_cp = decoder->final_second_cp;
                decoder->initial_byte = decoder->final_second_byte;
                begin_new_medial(decoder, byte, STATE_S3);
            }
            return 1;

        case STATE_S6:
            if (is_cf(byte)) {
                decoder->final_cp = map_base_jamo(byte);
                decoder->final_first_cp = decoder->final_cp;
                decoder->final_first_byte = byte;
                decoder->state = STATE_S7;
            } else if (is_ci(byte)) {
                if (!compose_syllable(decoder->initial_cp, decoder->medial_cp, 0, &syllable_cp)
                        || !emit(ctx, syllable_cp)) {
                    return 0;
                }
                begin_new_initial(decoder, byte);
            } else {
                if (!compose_syllable(decoder->initial_cp, decoder->medial_cp, 0, &syllable_cp)
                        || !emit(ctx, syllable_cp)
                        || !emit(ctx, map_base_jamo(byte))) {
                    return 0;
                }
                hconv_nbytes_decoder_init(decoder);
            }
            return 1;

        case STATE_S7:
            pair_cp = map_compound_final(decoder->final_first_byte, byte);
            if (pair_cp != 0) {
                decoder->final_cp = pair_cp;
                decoder->final_second_cp = map_base_jamo(byte);
                decoder->final_second_byte = byte;
                decoder->state = STATE_S8;
            } else if (is_c(byte)) {
                if (!compose_syllable(decoder->initial_cp, decoder->medial_cp, decoder->final_cp, &syllable_cp)
                        || !emit(ctx, syllable_cp)) {
                    return 0;
                }
                begin_new_initial(decoder, byte);
            } else {
                if (!compose_syllable(decoder->initial_cp, decoder->medial_cp, 0, &syllable_cp)
                        || !emit(ctx, syllable_cp)) {
                    return 0;
                }
                decoder->initial_cp = decoder->final_cp;
                decoder->initial_byte = decoder->final_first_byte;
                begin_new_medial(decoder, byte, STATE_S6);
            }
            return 1;

        case STATE_S8:
            if (is_c(byte)) {
                if (!compose_syllable(decoder->initial_cp, decoder->medial_cp, decoder->final_cp, &syllable_cp)
                        || !emit(ctx, syllable_cp)) {
                    return 0;
                }
                begin_new_initial(decoder, byte);
            } else {
                if (!compose_syllable(decoder->initial_cp, decoder->medial_cp, decoder->final_first_cp, &syllable_cp)
                        || !emit(ctx, syllable_cp)) {
                    return 0;
                }
                decoder->initial_cp = decoder->final_second_cp;
                decoder->initial_byte = decoder->final_second_byte;
                begin_new_medial(decoder, byte, STATE_S3);
            }
            return 1;
    }

    return 0;
}

static int emit_codepoint_to_buffer(void *ctx, uint32_t cp)
{
    return codepoint_buffer_append((struct codepoint_buffer *)ctx, cp);
}

int hconv_nbytes_finish(struct hconv_nbytes_decoder *decoder,
    hconv_emit_codepoint_fn emit, void *ctx)
{
    if (decoder->in_span) {
        set_error("unterminated_nbytes_span", "unterminated nbytes span");
        return 0;
    }
    if (decoder->state != STATE_S1) {
        return flush_nbytes_buffer(decoder, emit, ctx);
    }
    return 1;
}

static int decode_nbytes(const unsigned char *raw, size_t raw_len, struct codepoint_buffer *out)
{
    struct hconv_nbytes_decoder decoder;
    size_t i;

    decoder.in_span = 0;
    hconv_nbytes_decoder_init(&decoder);

    for (i = 0; i < raw_len; ++i) {
        if (!hconv_nbytes_decode_byte(&decoder, raw[i], emit_codepoint_to_buffer, out)) {
            return 0;
        }
    }

    return hconv_nbytes_finish(&decoder, emit_codepoint_to_buffer, out);
}

static int append_ascii_string(struct byte_buffer *out, const char *text)
{
    while (*text != '\0') {
        if (!byte_buffer_append(out, (unsigned char)*text++)) {
            return 0;
        }
    }
    return 1;
}

static int encode_nbytes(const struct codepoint_buffer *in, struct byte_buffer *out)
{
    size_t i;

    for (i = 0; i < in->len; ++i) {
        uint32_t cp = in->data[i];
        const char *mapped = jamo_to_nbytes(cp);
        uint32_t initial_cp;
        uint32_t medial_cp;
        uint32_t final_cp;

        if (mapped != NULL) {
            if (!byte_buffer_append(out, SPAN_START)
                    || !append_ascii_string(out, mapped)
                    || !byte_buffer_append(out, SPAN_END)) {
                return 0;
            }
            continue;
        }

        if (0xAC00u <= cp && cp <= 0xD7A3u) {
            const char *initial_bytes;
            const char *medial_bytes;
            const char *final_bytes;

            if (!decompose_syllable(cp, &initial_cp, &medial_cp, &final_cp)) {
                return 0;
            }
            initial_bytes = jamo_to_nbytes(initial_cp);
            medial_bytes = jamo_to_nbytes(medial_cp);
            final_bytes = final_cp ? jamo_to_nbytes(final_cp) : NULL;
            if (initial_bytes == NULL || medial_bytes == NULL || (final_cp && final_bytes == NULL)) {
                set_error("unsupported_unicode_codepoint", "cannot encode syllable as nbytes");
                return 0;
            }
            if (!byte_buffer_append(out, SPAN_START)
                    || !append_ascii_string(out, initial_bytes)
                    || !append_ascii_string(out, medial_bytes)
                    || (final_bytes != NULL && !append_ascii_string(out, final_bytes))
                    || !byte_buffer_append(out, SPAN_END)) {
                return 0;
            }
            continue;
        }

        if (cp <= 0x7Fu) {
            if (!byte_buffer_append(out, (unsigned char)cp)) {
                return 0;
            }
            continue;
        }

        set_error("unsupported_unicode_codepoint", "cannot encode code point outside nbytes span");
        return 0;
    }

    return 1;
}

const char *hconv_error_code(void)
{
    return error_code;
}

const char *hconv_error_detail(void)
{
    return error_detail;
}

int hconv_parse_mode(const char *text, enum encoding_mode *out_mode)
{
    if (strcmp(text, "utf8") == 0) {
        *out_mode = ENCODING_UTF8;
        return 1;
    }
    if (strcmp(text, "modified") == 0) {
        *out_mode = ENCODING_MODIFIED;
        return 1;
    }
    if (strcmp(text, "nbytes") == 0) {
        *out_mode = ENCODING_NBYTES;
        return 1;
    }
    return 0;
}

static int decode_input(enum encoding_mode from_code, const struct byte_buffer *input, struct codepoint_buffer *unicode)
{
    switch (from_code) {
        case ENCODING_UTF8:
            return decode_utf8(input->data, input->len, unicode);
        case ENCODING_MODIFIED:
            return decode_modified(input->data, input->len, unicode);
        case ENCODING_NBYTES:
            return decode_nbytes(input->data, input->len, unicode);
    }
    return 0;
}

static int encode_output(enum encoding_mode to_code, const struct codepoint_buffer *unicode, struct byte_buffer *output)
{
    switch (to_code) {
        case ENCODING_UTF8:
            return encode_utf8(unicode, output);
        case ENCODING_MODIFIED:
            return encode_modified(unicode, output);
        case ENCODING_NBYTES:
            return encode_nbytes(unicode, output);
    }
    return 0;
}

int hconv_map_modified_codepoint(uint32_t cp, unsigned int *out_mapped)
{
    int l_index;
    int v_index;
    int t_index;

    if (0x1100u <= cp && cp <= 0x11FFu) {
        *out_mapped = (unsigned int)(cp - 0xD000u);
        return 1;
    }
    if (0xAC00u <= cp && cp <= 0xD7A3u) {
        *out_mapped = (unsigned int)(cp - 0x6000u);
        return 1;
    }

    l_index = lookup_index(L_TABLE, sizeof(L_TABLE) / sizeof(L_TABLE[0]), cp);
    if (l_index >= 0) {
        *out_mapped = 0x4100u + (unsigned int)l_index;
        return 1;
    }

    v_index = lookup_index(V_TABLE, sizeof(V_TABLE) / sizeof(V_TABLE[0]), cp);
    if (v_index >= 0) {
        *out_mapped = 0x4161u + (unsigned int)v_index;
        return 1;
    }

    t_index = lookup_index(T_TABLE, sizeof(T_TABLE) / sizeof(T_TABLE[0]), cp);
    if (t_index > 0) {
        *out_mapped = 0x4100u + (unsigned int)FINAL_LOW_BYTES[t_index];
        return 1;
    }

    set_error("unsupported_unicode_codepoint", "cannot encode code point as modified");
    return 0;
}

int hconv_convert(enum encoding_mode from_code, enum encoding_mode to_code,
    const unsigned char *input, size_t input_len,
    unsigned char **output, size_t *output_len)
{
    struct byte_buffer input_buffer = {0};
    struct codepoint_buffer unicode = {0};
    struct byte_buffer encoded = {0};
    int ok;

    *output = NULL;
    *output_len = 0;

    if (from_code == to_code) {
        input_buffer.data = (unsigned char *)malloc(input_len ? input_len : 1u);
        if (input_buffer.data == NULL) {
            set_error("out_of_memory", "could not allocate output buffer");
            return 0;
        }
        memcpy(input_buffer.data, input, input_len);
        *output = input_buffer.data;
        *output_len = input_len;
        return 1;
    }

    input_buffer.data = (unsigned char *)input;
    input_buffer.len = input_len;

    ok = decode_input(from_code, &input_buffer, &unicode)
        && encode_output(to_code, &unicode, &encoded);
    if (!ok) {
        free(unicode.data);
        free(encoded.data);
        return 0;
    }

    free(unicode.data);
    *output = encoded.data;
    *output_len = encoded.len;
    return 1;
}

void hconv_free(void *ptr)
{
    free(ptr);
}

#ifdef HCONV_MAIN
int main(int argc, char **argv)
{
    enum encoding_mode from_code = ENCODING_UTF8;
    enum encoding_mode to_code = ENCODING_UTF8;
    struct byte_buffer input = {0};
    unsigned char *output = NULL;
    size_t output_len = 0;
    int i;
    int have_from = 0;
    int have_to = 0;
    int status = 1;

    for (i = 1; i < argc; ++i) {
        if ((strcmp(argv[i], "-f") == 0 || strcmp(argv[i], "--from-code") == 0) && i + 1 < argc) {
            if (!hconv_parse_mode(argv[++i], &from_code)) {
                fprintf(stderr, "usage_error: unsupported from-code\n");
                goto cleanup;
            }
            have_from = 1;
        } else if ((strcmp(argv[i], "-t") == 0 || strcmp(argv[i], "--to-code") == 0) && i + 1 < argc) {
            if (!hconv_parse_mode(argv[++i], &to_code)) {
                fprintf(stderr, "usage_error: unsupported to-code\n");
                goto cleanup;
            }
            have_to = 1;
        } else {
            fprintf(stderr, "usage_error: usage: hconv -f <utf8|modified|nbytes> -t <utf8|modified|nbytes>\n");
            goto cleanup;
        }
    }

    if (!have_from || !have_to) {
        fprintf(stderr, "usage_error: usage: hconv -f <utf8|modified|nbytes> -t <utf8|modified|nbytes>\n");
        goto cleanup;
    }

    if (!read_stdin_all(&input)) {
        goto cleanup;
    }

    if (!hconv_convert(from_code, to_code, input.data, input.len, &output, &output_len)) {
        fprintf(stderr, "%s: %s\n", hconv_error_code(), hconv_error_detail());
        goto cleanup;
    }

    if (!write_stdout_all(output, output_len)) {
        fprintf(stderr, "io_error: output failed\n");
        goto cleanup;
    }

    status = 0;

cleanup:
    free(input.data);
    hconv_free(output);
    return status;
}
#endif

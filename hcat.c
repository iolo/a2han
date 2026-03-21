#include <conio.h>
#include <stdio.h>
#include <string.h>

#define CTRL_E 0x05
#define CTRL_K 0x0B
#define SPAN_MAX 512
#define SCREEN_COLS 40
#define SCREEN_ROWS 24
#define TEXT_PAGE1 0x0400
#define DISPLAY_SPACE 0xA0

enum encoding_mode {
    ENCODING_UTF8,
    ENCODING_MODIFIED,
    ENCODING_NBYTES
};

struct single_map {
    unsigned char ch;
    unsigned char index;
};

struct pair_map {
    unsigned char first;
    unsigned char second;
    unsigned char index;
};

static const struct single_map initial_map[] = {
    { 'R', 0x00 }, { 'r', 0x01 }, { 'S', 0x02 }, { 'E', 0x03 }, { 'e', 0x04 },
    { 'F', 0x05 }, { 'A', 0x06 }, { 'Q', 0x07 }, { 'q', 0x08 }, { 'T', 0x09 },
    { 't', 0x0A }, { 'D', 0x0B }, { 'W', 0x0C }, { 'w', 0x0D }, { 'C', 0x0E },
    { 'Z', 0x0F }, { 'X', 0x10 }, { 'V', 0x11 }, { 'G', 0x12 }
};

static const struct single_map vowel_map[] = {
    { 'K', 0x00 }, { 'O', 0x01 }, { 'I', 0x02 }, { 'o', 0x03 }, { 'J', 0x04 },
    { 'P', 0x05 }, { 'U', 0x06 }, { 'p', 0x07 }, { 'H', 0x08 }, { 'Y', 0x0C },
    { 'N', 0x0D }, { 'B', 0x11 }, { 'M', 0x12 }, { 'L', 0x14 }
};

static const struct pair_map vowel_pair_map[] = {
    { 'H', 'K', 0x09 }, { 'H', 'O', 0x0A }, { 'H', 'L', 0x0B },
    { 'N', 'J', 0x0E }, { 'N', 'P', 0x0F }, { 'N', 'L', 0x10 },
    { 'M', 'L', 0x13 }
};

static const struct single_map final_map[] = {
    { 'R', 0x01 }, { 'r', 0x02 }, { 'S', 0x04 }, { 'E', 0x07 }, { 'F', 0x08 },
    { 'A', 0x10 }, { 'Q', 0x11 }, { 'T', 0x13 }, { 't', 0x14 }, { 'D', 0x15 },
    { 'W', 0x16 }, { 'C', 0x17 }, { 'Z', 0x18 }, { 'X', 0x19 }, { 'V', 0x1A },
    { 'G', 0x1B }
};

static const struct pair_map final_pair_map[] = {
    { 'R', 'T', 0x03 }, { 'S', 'W', 0x05 }, { 'S', 'G', 0x06 },
    { 'F', 'R', 0x09 }, { 'F', 'A', 0x0A }, { 'F', 'Q', 0x0B },
    { 'F', 'T', 0x0C }, { 'F', 'X', 0x0D }, { 'F', 'V', 0x0E },
    { 'F', 'G', 0x0F }, { 'Q', 'T', 0x12 }
};

static const unsigned char final_low_bytes[] = {
    0x00,
    0xA8, 0xA9, 0xAA, 0xAB, 0xAC, 0xAD, 0xAE,
    0xAF, 0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
    0xB7, 0xB8, 0xB9, 0xBA, 0xBB, 0xBC, 0xBD, 0xBE,
    0xBF, 0xC0, 0xC1, 0xC2
};

static int saw_cr = 0;
static char last_error[96];
static unsigned char span_buffer[SPAN_MAX];
static char filename_buffer[128];
static unsigned char screen_x = 0;
static unsigned char screen_y = 0;

static void set_error(const char* message)
{
    strncpy(last_error, message, sizeof(last_error) - 1);
    last_error[sizeof(last_error) - 1] = '\0';
}

static unsigned int screen_addr(unsigned char x, unsigned char y)
{
    return TEXT_PAGE1 + ((unsigned int)(y & 0x07u) << 7) + ((unsigned int)(y >> 3) * SCREEN_COLS) + x;
}

static void screen_poke(unsigned int addr, unsigned char value)
{
    *(unsigned char*)addr = value;
}

static void clear_row(unsigned char y)
{
    unsigned char x;
    unsigned int addr = screen_addr(0, y);

    for (x = 0; x < SCREEN_COLS; ++x) {
        screen_poke(addr + x, DISPLAY_SPACE);
    }
}

static void hhome(void)
{
    unsigned char y;

    for (y = 0; y < SCREEN_ROWS; ++y) {
        clear_row(y);
    }

    screen_x = 0;
    screen_y = 0;
    saw_cr = 0;
}

static void wait_for_page(void)
{
    cgetc();
    hhome();
}

static void hnewline(void)
{
    screen_x = 0;
    if (screen_y + 1 < SCREEN_ROWS) {
        ++screen_y;
    } else {
        wait_for_page();
    }
}

static int hput_raw_byte(unsigned char value)
{
    if (value == '\r') {
        saw_cr = 1;
        hnewline();
        return 1;
    }
    if (value == '\n') {
        if (saw_cr) {
            saw_cr = 0;
            return 1;
        }
        hnewline();
        return 1;
    }
    saw_cr = 0;

    screen_poke(screen_addr(screen_x, screen_y), value);
    if (screen_x + 1 < SCREEN_COLS) {
        ++screen_x;
    } else {
        hnewline();
    }
    return 1;
}

static int hput_text_byte(unsigned char value)
{
    if (value == '\r' || value == '\n') {
        return hput_raw_byte(value);
    }
    if (value < 0x20u) {
        return 1;
    }
    return hput_raw_byte((unsigned char)(value | 0x80u));
}

static int emit_modified_pair(unsigned int value)
{
    if (!hput_raw_byte((unsigned char)((value >> 8) & 0xFF))) {
        return 0;
    }
    return hput_raw_byte((unsigned char)(value & 0xFF));
}

static int emit_modified_syllable(unsigned char l_index, unsigned char v_index, unsigned char t_index)
{
    unsigned int mapped = 0x4C00u + ((unsigned int)l_index * 21u * 28u)
        + ((unsigned int)v_index * 28u) + (unsigned int)t_index;
    return emit_modified_pair(mapped);
}

static int emit_modified_initial(unsigned char l_index)
{
    return emit_modified_pair(0x4100u + (unsigned int)l_index);
}

static int emit_modified_vowel(unsigned char v_index)
{
    return emit_modified_pair(0x4161u + (unsigned int)v_index);
}

static int emit_modified_final(unsigned char t_index)
{
    if (t_index == 0 || t_index >= sizeof(final_low_bytes)) {
        return 0;
    }
    return emit_modified_pair(0x4100u + (unsigned int)final_low_bytes[t_index]);
}

static int map_single(const struct single_map* table, unsigned int count, unsigned char ch, unsigned char* out_index)
{
    unsigned int i;
    for (i = 0; i < count; ++i) {
        if (table[i].ch == ch) {
            *out_index = table[i].index;
            return 1;
        }
    }
    return 0;
}

static int map_pair(const struct pair_map* table, unsigned int count, const unsigned char* data, unsigned int len, unsigned int pos, unsigned char* out_index)
{
    unsigned int i;
    if (pos + 1 >= len) {
        return 0;
    }
    for (i = 0; i < count; ++i) {
        if (table[i].first == data[pos] && table[i].second == data[pos + 1]) {
            *out_index = table[i].index;
            return 1;
        }
    }
    return 0;
}

static int map_initial(unsigned char ch, unsigned char* out_index)
{
    return map_single(initial_map, sizeof(initial_map) / sizeof(initial_map[0]), ch, out_index);
}

static int map_vowel_token(const unsigned char* data, unsigned int len, unsigned int pos, unsigned char* out_index, unsigned char* out_size)
{
    if (map_pair(vowel_pair_map, sizeof(vowel_pair_map) / sizeof(vowel_pair_map[0]), data, len, pos, out_index)) {
        *out_size = 2;
        return 1;
    }
    if (map_single(vowel_map, sizeof(vowel_map) / sizeof(vowel_map[0]), data[pos], out_index)) {
        *out_size = 1;
        return 1;
    }
    return 0;
}

static int map_final_token(const unsigned char* data, unsigned int len, unsigned int pos, unsigned char* out_index, unsigned char* out_size)
{
    if (map_pair(final_pair_map, sizeof(final_pair_map) / sizeof(final_pair_map[0]), data, len, pos, out_index)) {
        *out_size = 2;
        return 1;
    }
    if (map_single(final_map, sizeof(final_map) / sizeof(final_map[0]), data[pos], out_index)) {
        *out_size = 1;
        return 1;
    }
    return 0;
}

static int is_base_consonant(unsigned char ch)
{
    switch (ch) {
        case 'A':
        case 'C':
        case 'D':
        case 'E':
        case 'F':
        case 'G':
        case 'Q':
        case 'R':
        case 'S':
        case 'T':
        case 'V':
        case 'W':
        case 'X':
        case 'Z':
        case 'e':
        case 'q':
        case 'r':
        case 't':
        case 'w':
            return 1;
    }
    return 0;
}

static int is_safe_nbytes_byte(unsigned char ch)
{
    return strchr(" \t\r\n0123456789!\"#$%&'()*+,-./:;<=>?[\\]^_`{|}~", ch) != NULL;
}

static int convert_nbytes_payload(const unsigned char* data, unsigned int len)
{
    unsigned int i = 0;

    while (i < len) {
        unsigned char l_index;
        unsigned char v_index;
        unsigned char v_size;

        if (map_initial(data[i], &l_index) &&
                (i + 1 < len) &&
                map_vowel_token(data, len, i + 1, &v_index, &v_size)) {
            unsigned char t_index = 0;
            unsigned char t_size = 0;
            unsigned int consumed = 1u + (unsigned int)v_size;
            unsigned int next = i + consumed;

            if (next < len && map_final_token(data, len, next, &t_index, &t_size)) {
                if (!(t_size == 1 &&
                        (next + 1 < len) &&
                        is_base_consonant(data[next]) &&
                        map_vowel_token(data, len, next + 1, &v_index, &v_size))) {
                    consumed += (unsigned int)t_size;
                } else {
                    t_index = 0;
                }
                map_vowel_token(data, len, i + 1, &v_index, &v_size);
            }

            if (!emit_modified_syllable(l_index, v_index, t_index)) {
                set_error("output failed");
                return 0;
            }
            i += consumed;
            continue;
        }

        if (map_vowel_token(data, len, i, &v_index, &v_size)) {
            if (!emit_modified_vowel(v_index)) {
                set_error("output failed");
                return 0;
            }
            i += (unsigned int)v_size;
            continue;
        }

        if (map_initial(data[i], &l_index)) {
            if (!emit_modified_initial(l_index)) {
                set_error("output failed");
                return 0;
            }
            ++i;
            continue;
        }

        {
            unsigned char t_index;
            unsigned char t_size;
            if (map_final_token(data, len, i, &t_index, &t_size)) {
                if (!emit_modified_final(t_index)) {
                    set_error("output failed");
                    return 0;
                }
                i += (unsigned int)t_size;
                continue;
            }
        }

        if (is_safe_nbytes_byte(data[i])) {
            if (!hput_text_byte(data[i])) {
                set_error("output failed");
                return 0;
            }
            ++i;
            continue;
        }

        set_error("invalid nbytes byte");
        return 0;
    }

    return 1;
}

static int stream_modified_file(FILE* fp)
{
    int ch;
    while ((ch = fgetc(fp)) != EOF) {
        if (!hput_raw_byte((unsigned char)ch)) {
            set_error("output failed");
            return 0;
        }
    }
    return 1;
}

static int decode_utf8_sequence(FILE* fp, unsigned char lead, unsigned long* out_codepoint)
{
    unsigned int needed;
    unsigned long codepoint;
    unsigned int i;

    if ((lead & 0xE0u) == 0xC0u) {
        needed = 1;
        codepoint = (unsigned long)(lead & 0x1Fu);
    } else if ((lead & 0xF0u) == 0xE0u) {
        needed = 2;
        codepoint = (unsigned long)(lead & 0x0Fu);
    } else if ((lead & 0xF8u) == 0xF0u) {
        needed = 3;
        codepoint = (unsigned long)(lead & 0x07u);
    } else {
        set_error("invalid UTF-8 lead byte");
        return 0;
    }

    for (i = 0; i < needed; ++i) {
        int next = fgetc(fp);
        if (next == EOF) {
            set_error("truncated UTF-8 sequence");
            return 0;
        }
        if (((unsigned char)next & 0xC0u) != 0x80u) {
            set_error("invalid UTF-8 continuation byte");
            return 0;
        }
        codepoint = (codepoint << 6) | (unsigned long)((unsigned char)next & 0x3Fu);
    }

    *out_codepoint = codepoint;
    return 1;
}

static int stream_utf8_file(FILE* fp)
{
    int ch;

    while ((ch = fgetc(fp)) != EOF) {
        unsigned char byte = (unsigned char)ch;

        if (byte < 0x80u) {
            if (!hput_text_byte(byte)) {
                set_error("output failed");
                return 0;
            }
            continue;
        }

        {
            unsigned long codepoint;
            if (!decode_utf8_sequence(fp, byte, &codepoint)) {
                return 0;
            }

            if (codepoint == 0xFEFFu) {
                continue;
            }

            if (0x1100u <= codepoint && codepoint <= 0x11FFu) {
                if (!emit_modified_pair((unsigned int)(codepoint - 0xD000u))) {
                    set_error("output failed");
                    return 0;
                }
                continue;
            }

            if (0xAC00u <= codepoint && codepoint <= 0xD7A3u) {
                if (!emit_modified_pair((unsigned int)(codepoint - 0x6000u))) {
                    set_error("output failed");
                    return 0;
                }
                continue;
            }

            set_error("unsupported Unicode code point");
            return 0;
        }
    }

    return 1;
}

static int stream_nbytes_file(FILE* fp)
{
    unsigned int span_len = 0;
    int in_span = 0;
    int ch;

    while ((ch = fgetc(fp)) != EOF) {
        unsigned char byte = (unsigned char)ch;

        if (!in_span) {
            if (byte == CTRL_K) {
                in_span = 1;
                span_len = 0;
                continue;
            }
            if (!hput_text_byte(byte)) {
                set_error("output failed");
                return 0;
            }
            continue;
        }

        if (byte == CTRL_E) {
            if (!convert_nbytes_payload(span_buffer, span_len)) {
                return 0;
            }
            in_span = 0;
            span_len = 0;
            continue;
        }

        if (span_len >= SPAN_MAX) {
            set_error("nbytes span too long");
            return 0;
        }

        span_buffer[span_len++] = byte;
    }

    if (in_span) {
        set_error("unterminated nbytes span");
        return 0;
    }

    return 1;
}

static int prompt_line(const char* prompt, char* buffer, unsigned int size)
{
    unsigned int len;

    fputs(prompt, stdout);
    fflush(stdout);
    if (fgets(buffer, (int)size, stdin) == NULL) {
        set_error("input cancelled");
        return 0;
    }

    len = (unsigned int)strlen(buffer);
    while (len > 0 && (buffer[len - 1] == '\n' || buffer[len - 1] == '\r')) {
        buffer[--len] = '\0';
    }

    if (len == 0) {
        set_error("empty input");
        return 0;
    }

    return 1;
}

static int prompt_encoding(void)
{
    char buffer[8];
    if (!prompt_line("ENCODING: (U)nicode, (M)odified, (N)bytes: ", buffer, sizeof(buffer))) {
        return -1;
    }

    switch (buffer[0]) {
        case 'U':
        case 'u':
            return ENCODING_UTF8;
        case 'M':
        case 'm':
            return ENCODING_MODIFIED;
        case 'N':
        case 'n':
            return ENCODING_NBYTES;
    }

    set_error("unknown encoding");
    return -1;
}

static int stream_file(FILE* fp, int encoding)
{
    switch (encoding) {
        case ENCODING_UTF8:
            return stream_utf8_file(fp);
        case ENCODING_MODIFIED:
            return stream_modified_file(fp);
        case ENCODING_NBYTES:
            return stream_nbytes_file(fp);
    }

    set_error("unknown encoding");
    return 0;
}

int main(void)
{
    int encoding;
    FILE* fp;

    last_error[0] = '\0';
    if (!prompt_line("FILENAME: ", filename_buffer, sizeof(filename_buffer))) {
        cputs("ERROR: ");
        cputs(last_error);
        cputs("\r");
        return 1;
    }

    encoding = prompt_encoding();
    if (encoding < 0) {
        cputs("ERROR: ");
        cputs(last_error);
        cputs("\r");
        return 1;
    }

    fp = fopen(filename_buffer, "rb");
    if (fp == NULL) {
        cputs("ERROR: OPEN FAILED\r");
        return 1;
    }

    hhome();

    if (!stream_file(fp, encoding)) {
        fclose(fp);
        cputs("\rERROR: ");
        cputs(last_error);
        cputs("\r");
        return 1;
    }

    fclose(fp);
    cputs("\r");
    return 0;
}

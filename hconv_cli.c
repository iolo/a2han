#include "hconv.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct byte_buffer {
    unsigned char *data;
    size_t len;
    size_t cap;
};

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

// SPDX-License-Identifier: MIT
#ifndef DS720D_DOCUMENT_H
#define DS720D_DOCUMENT_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct ds_document {
    uint8_t *pixels; // Caller owns this allocation and frees it with free().
    size_t width, height, left, top;
    bool cropped, normalized;
    uint8_t paper[3];
};

// Deterministic document rendering; tone adjustment requires neutral bright paper.
// Input and acquisition data are never modified. No resampling or sharpening.
bool ds_document_clean(const uint8_t *rgb, size_t width, size_t height,
                       struct ds_document *result);
#endif

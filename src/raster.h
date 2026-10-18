// SPDX-License-Identifier: MIT
#ifndef DS720D_RASTER_H
#define DS720D_RASTER_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "document.h"
// Deinterleave native RGB stripes and mirror the rear sensor. Caller frees.
bool ds_raster_side(const uint8_t *raw,size_t length,unsigned side,bool clean,struct ds_document *out);
#endif

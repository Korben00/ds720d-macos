// SPDX-License-Identifier: MIT
#ifndef DS720D_ENGINE_H
#define DS720D_ENGINE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct ds_io {
    void *context;
    // Exact-length BOT transaction. 0 means success; both directions cannot coexist.
    int (*command)(void *,const uint8_t *,size_t,uint8_t *,size_t,const uint8_t *,size_t);
    bool (*cancelled)(void *);
};
struct ds_engine {
    struct ds_io io;
    char error[160];
    bool cleanup;
    double deadline;
};
// No motor commands.
bool ds_engine_identify(struct ds_engine *engine);
// Caller owns *raw on success. Fixed, bounded 300 dpi RGB duplex acquisition.
bool ds_engine_capture(struct ds_engine *engine,uint8_t **raw,size_t *length);
#endif

// SPDX-License-Identifier: MIT
#ifndef DS720D_PACKET_H
#define DS720D_PACKET_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum ds_bot_status {
    DS_BOT_OK = 0, DS_BOT_COMMAND_FAILED = 1, DS_BOT_PHASE_ERROR = 2,
    DS_BOT_MALFORMED = 3
};

bool ds_cbw_encode(uint8_t output[31], uint32_t tag, const uint8_t *cdb,
                   size_t cdb_length, uint32_t transfer_length, bool input);
enum ds_bot_status ds_csw_decode(const uint8_t *bytes, size_t length, uint32_t tag,
                                uint32_t requested, uint32_t transferred,
                                uint32_t *residue);
void ds_novatek_cdb(uint8_t cdb[16], uint8_t group, uint8_t action,
                    uint8_t channel, uint32_t length);
uint32_t ds_read_le32(const uint8_t *bytes);
void ds_write_be16(uint8_t *bytes, uint16_t value);
void ds_write_be32(uint8_t *bytes, uint32_t value);
enum { DS_NATIVE_DPI = 300, DS_NATIVE_WIDTH = 2592,
       DS_NATIVE_BPL = DS_NATIVE_WIDTH * 3, DS_STRIPE_ROWS = 80 };
void ds_native_window(uint8_t output[79]);
#endif

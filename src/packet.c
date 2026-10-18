// SPDX-License-Identifier: MIT
#include "packet.h"
#include <string.h>

uint32_t ds_read_le32(const uint8_t *b) {
    return (uint32_t)b[0] | ((uint32_t)b[1] << 8) |
           ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
}

static void write_le32(uint8_t *b, uint32_t n) {
    for (unsigned i = 0; i < 4; i++) b[i] = (uint8_t)(n >> (8 * i));
}

void ds_write_be16(uint8_t *b, uint16_t n) {
    b[0] = (uint8_t)(n >> 8); b[1] = (uint8_t)n;
}

void ds_write_be32(uint8_t *b, uint32_t n) {
    for (unsigned i = 0; i < 4; i++) b[i] = (uint8_t)(n >> (24 - 8 * i));
}

bool ds_cbw_encode(uint8_t out[31], uint32_t tag, const uint8_t *cdb,
                   size_t cdb_length, uint32_t length, bool input) {
    if (!out || !cdb || !cdb_length || cdb_length > 16) return false;
    memset(out, 0, 31);
    memcpy(out, "USBC", 4);
    write_le32(out + 4, tag);
    write_le32(out + 8, length);
    out[12] = input ? 0x80 : 0;
    out[14] = (uint8_t)cdb_length;
    memcpy(out + 15, cdb, cdb_length);
    return true;
}

enum ds_bot_status ds_csw_decode(const uint8_t *b, size_t length, uint32_t tag,
                                uint32_t requested, uint32_t transferred,
                                uint32_t *residue) {
    if (!b || length != 13 || memcmp(b, "USBS", 4) ||
        ds_read_le32(b + 4) != tag || b[12] > 2 || transferred > requested)
        return DS_BOT_MALFORMED;
    uint32_t remaining = ds_read_le32(b + 8);
    if (remaining > requested) return DS_BOT_MALFORMED;
    if (residue) *residue = remaining;
    if (b[12] == 0 && requested - remaining != transferred) return DS_BOT_MALFORMED;
    return (enum ds_bot_status)b[12];
}

void ds_novatek_cdb(uint8_t cdb[16], uint8_t group, uint8_t action,
                    uint8_t channel, uint32_t length) {
    memset(cdb, 0, 16);
    cdb[0] = 0xc5;
    cdb[1] = 0x07;
    ds_write_be32(cdb + 6, length);
    cdb[10] = group;
    cdb[11] = action;
    cdb[12] = channel;
}

void ds_native_window(uint8_t out[79]) {
    memset(out, 0, 79);
    ds_write_be16(out + 6, 71);
    uint8_t *d = out + 8;
    ds_write_be16(d + 2, DS_NATIVE_DPI);
    ds_write_be16(d + 4, DS_NATIVE_DPI);
    ds_write_be32(d + 14, DS_NATIVE_WIDTH * 4); // 1/1200-inch units.
    ds_write_be32(d + 18, 4335 * 4); // 14 inches plus rear sensor offset.
    d[22] = d[23] = d[24] = 128;
    d[25] = 5; d[26] = 8; // Native RGB, eight bits per component.
    d[29] = 3;
    d[40] = 0xff; d[41] = 0x1d; d[42] = 0xe0; d[43] = 0xff;
    ds_write_be16(d + 45, DS_NATIVE_BPL);
    ds_write_be16(d + 47, 4335 * 2);
    d[49] = 0x10;
    ds_write_be16(d + 51, 100); ds_write_be16(d + 53, 100);
    ds_write_be16(d + 55, 100);
    d[57] = 0x10; // Duplex source.
    d[61] = 11; // Background rows, not a sheet count.
}

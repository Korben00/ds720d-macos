// SPDX-License-Identifier: MIT
#include "packet.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    uint8_t cbw[31], cdb[16];
    ds_novatek_cdb(cdb, 0xff, 2, 0, 4);
    const uint8_t expected[] = {0xc5,7,0,0,0,0,0,0,0,4,0xff,2,0,0,0,0};
    assert(!memcmp(cdb, expected, 16));
    assert(ds_cbw_encode(cbw, 0x12345678, cdb, 16, 4, true));
    assert(!memcmp(cbw, "USBC\x78\x56\x34\x12\x04\x00\x00\x00\x80\x00\x10", 15));
    assert(!memcmp(cbw + 15, expected, 16));
    assert(!ds_cbw_encode(cbw, 0, cdb, 0, 0, false));
    assert(!ds_cbw_encode(cbw, 0, cdb, 17, 0, false));
    assert(!ds_cbw_encode(cbw, 0, NULL, 6, 0, false));
    uint8_t csw[13] = {'U','S','B','S',0x78,0x56,0x34,0x12,0,0,0,0,0};
    assert(ds_csw_decode(csw, 13, 0x12345678, 4, 4, NULL) == DS_BOT_OK);
    assert(ds_csw_decode(csw, 12, 0x12345678, 4, 4, NULL) == DS_BOT_MALFORMED);
    assert(ds_csw_decode(csw, 13, 5, 4, 4, NULL) == DS_BOT_MALFORMED);
    csw[8] = 2;
    uint32_t residue = 0;
    assert(ds_csw_decode(csw, 13, 0x12345678, 4, 2, &residue) == DS_BOT_OK && residue == 2);
    assert(ds_csw_decode(csw, 13, 0x12345678, 4, 4, NULL) == DS_BOT_MALFORMED);
    csw[8] = 5;
    assert(ds_csw_decode(csw, 13, 0x12345678, 4, 0, NULL) == DS_BOT_MALFORMED);
    csw[8] = 0; csw[12] = 1;
    assert(ds_csw_decode(csw, 13, 0x12345678, 4, 0, NULL) == DS_BOT_COMMAND_FAILED);
    csw[12] = 2;
    assert(ds_csw_decode(csw, 13, 0x12345678, 4, 0, NULL) == DS_BOT_PHASE_ERROR);
    csw[12] = 3;
    assert(ds_csw_decode(csw, 13, 0x12345678, 4, 0, NULL) == DS_BOT_MALFORMED);
    csw[0] = 'X'; csw[12] = 0;
    assert(ds_csw_decode(csw, 13, 0x12345678, 0, 0, NULL) == DS_BOT_MALFORMED);
    uint8_t word[4];
    ds_write_be32(word, 0x12345678);
    assert(!memcmp(word, "\x12\x34\x56\x78", 4));
    uint8_t window[79];
    ds_native_window(window);
    // Independent wire fixture: 300 dpi native RGB, full sensor, duplex.
    const uint8_t native[79]={
        0,0,0,0,0,0,0,71,
        0,0,1,0x2c,1,0x2c,0,0,0,0,0,0,0,0,0,0,
        0x28,0x80,0,0,0x43,0xbc,0x80,0x80,0x80,5,8,0,0,3,
        0,0,0,0,0,0,0,0,0,0,0xff,0x1d,0xe0,0xff,0,
        0x1e,0x60,0x21,0xde,0x10,0,0,0x64,0,0x64,0,0x64,
        0x10,0,0,0,11,0,0,0,0,0,0,0,0,0};
    assert(!memcmp(window,native,sizeof window));
    puts("USB packet framing: all checks passed.");
    return 0;
}

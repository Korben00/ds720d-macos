// SPDX-License-Identifier: MIT
#include "raster.h"
#include "packet.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>

int main(void) {
    size_t rows=DS_STRIPE_ROWS*4+7,length=rows*DS_NATIVE_BPL;
    uint8_t *raw=malloc(length);assert(raw);
    for(size_t y=0;y<rows;y++)for(unsigned c=0;c<3;c++)for(size_t x=0;x<DS_NATIVE_WIDTH;x++)
        raw[y*DS_NATIVE_BPL+c*DS_NATIVE_WIDTH+x]=(uint8_t)(y+17*c+x);
    struct ds_document page;
    for(unsigned side=0;side<2;side++) {
        assert(ds_raster_side(raw,length,side,false,&page));
        assert(page.width==DS_NATIVE_WIDTH && page.height==(side?160:167));
        size_t line=0;
        for(size_t y=0;y<rows;y++)if((y/80)%2==side){
            for(size_t x=0;x<DS_NATIVE_WIDTH;x++)for(unsigned c=0;c<3;c++)
                assert(page.pixels[line*DS_NATIVE_BPL+3*x+c]==(uint8_t)(y+17*c+(side?DS_NATIVE_WIDTH-1-x:x)));
            line++;
        }
        free(page.pixels);
    }
    assert(!ds_raster_side(raw,length-1,0,false,&page));
    assert(!ds_raster_side(raw,length,2,false,&page));
    assert(!ds_raster_side(raw,DS_NATIVE_BPL,1,false,&page));
    free(raw);puts("Shared raster: planar RGB, both sensors, stripe boundaries and partial stripe checked.");
}

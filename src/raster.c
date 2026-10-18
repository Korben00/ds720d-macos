// SPDX-License-Identifier: MIT
#include "raster.h"
#include "packet.h"
#include <stdlib.h>
#include <string.h>

bool ds_raster_side(const uint8_t *raw,size_t length,unsigned side,bool clean,struct ds_document *out) {
    if(!out)return false;
    memset(out,0,sizeof *out);
    if(!raw || !length || length>80000000 || length%DS_NATIVE_BPL || side>1)return false;
    size_t rows=length/DS_NATIVE_BPL,height=0,width=DS_NATIVE_BPL/3;
    for(size_t y=0;y<rows;y++)height+=(y/DS_STRIPE_ROWS)%2==side;
    if(!height)return false;
    uint8_t *rgb=malloc(width*height*3);if(!rgb)return false;
    size_t line=0;
    for(size_t y=0;y<rows;y++)if((y/DS_STRIPE_ROWS)%2==side) {
        const uint8_t *src=raw+y*DS_NATIVE_BPL;uint8_t *dst=rgb+line++*DS_NATIVE_BPL;
        for(size_t x=0;x<width;x++)for(unsigned c=0;c<3;c++)dst[3*x+c]=src[c*width+(side?width-1-x:x)];
    }
    if(clean){bool ok=ds_document_clean(rgb,width,height,out);free(rgb);return ok;}
    out->pixels=rgb;out->width=width;out->height=height;return true;
}

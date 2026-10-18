// SPDX-License-Identifier: MIT
#include "document.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const uint8_t *at(const struct ds_document *d,size_t x,size_t y) {
    assert(x>=d->left && y>=d->top && x-d->left<d->width && y-d->top<d->height);
    return d->pixels+3*((y-d->top)*d->width+x-d->left);
}

int main(void) {
    const size_t w=512,h=768;
    uint8_t *input=calloc(w*h,3),*original=malloc(w*h*3);
    assert(input && original);
    // Gray paper with a gradual illumination change, texture and a mild cast.
    for(size_t y=32;y<732;y++)for(size_t x=24;x<488;x++) {
        unsigned level=150+(unsigned)x/24+(unsigned)y/100;
        int texture=(int)((x*13+y*17)%5)-2;
        uint8_t *p=input+3*(y*w+x);
        p[0]=(uint8_t)(level+texture+2);p[1]=(uint8_t)(level+texture);p[2]=(uint8_t)(level+texture+5);
        if(y>=110 && y<116 && x>=80 && x<430)memset(p,20,3); // Thin dark print.
        if(y>=200 && y<206 && x>=80 && x<430) { // Faint gray print must survive.
            p[0]-=24;p[1]-=24;p[2]-=24;
        }
        if(y>=300 && y<340 && x>=80 && x<120){p[0]=150;p[1]=40;p[2]=25;}
    }
    memcpy(original,input,w*h*3);
    struct ds_document d;
    assert(ds_document_clean(input,w,h,&d));
    assert(!memcmp(original,input,w*h*3));
    assert(d.cropped && d.normalized);
    assert(d.left==26 && d.top==34 && d.width==460 && d.height==696);
    size_t paper=0,white=0;
    for(size_t y=40;y<720;y++)for(size_t x=40;x<475;x++) {
        if((y>=108 && y<=118) || (y>=198 && y<=208) || (y>=298 && y<=342))continue;
        const uint8_t *p=at(&d,x,y);paper++;
        white+=p[0]>=245 && p[1]>=245 && p[2]>=245;
    }
    assert(white*100>=paper*98);
    const uint8_t *ink=at(&d,200,112),*faint=at(&d,200,202),*color=at(&d,100,320);
    for(unsigned c=0;c<3;c++){assert(ink[c]<40);assert(faint[c]>180 && faint[c]<240);}
    assert(color[0]>200 && color[1]<80 && color[2]<60);
    free(d.pixels);

    // Different rear-sensor brightness receives its own normalization.
    for(size_t i=0;i<w*h*3;i++)input[i]=(uint8_t)(original[i]*4/5);
    assert(ds_document_clean(input,w,h,&d) && d.normalized);
    assert(d.left==26 && d.top==34 && d.width==460 && d.height==696);
    const uint8_t *back=at(&d,200,500);
    for(unsigned c=0;c<3;c++)assert(back[c]>=245);
    free(d.pixels);

    // Avoid interpreting a dark/colored image as gray document paper.
    for(size_t i=0;i<w*h;i++){input[3*i]=150;input[3*i+1]=30;input[3*i+2]=20;}
    assert(ds_document_clean(input,w,h,&d) && !d.normalized && !d.cropped);
    assert(!memcmp(input,d.pixels,w*h*3));free(d.pixels);
    memset(input,0,w*h*3);
    assert(ds_document_clean(input,w,h,&d) && !d.normalized && !d.cropped);
    assert(!memcmp(input,d.pixels,w*h*3));free(d.pixels);
    memset(input,255,w*h*3);
    assert(ds_document_clean(input,w,h,&d) && !d.normalized && !d.cropped);
    assert(!memcmp(input,d.pixels,w*h*3));free(d.pixels);
    assert(!ds_document_clean(NULL,w,h,&d));
    assert(!ds_document_clean(input,0,h,&d));
    assert(!ds_document_clean(input,SIZE_MAX,h,&d));
    free(input);free(original);
    puts("Document rendering: paper crop, local white balance, faint print, color and raw preservation checked.");
    return 0;
}

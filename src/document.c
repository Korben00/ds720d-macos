// SPDX-License-Identifier: MIT
#include "document.h"
#include <stdlib.h>
#include <string.h>

enum { TILE = 128 };
struct bounds { size_t left, top, right, bottom; };

static unsigned luminance(const uint8_t *p) {
    return (77u*p[0]+150u*p[1]+29u*p[2]+128u)>>8;
}

static unsigned maximum(unsigned a,unsigned b) { return a>b?a:b; }
static unsigned minimum(unsigned a,unsigned b) { return a<b?a:b; }

static bool neutral(const uint8_t *p) {
    return maximum(p[0],maximum(p[1],p[2]))-minimum(p[0],minimum(p[1],p[2]))<=24;
}

static int compare_size(const void *a,const void *b) {
    size_t x=*(const size_t *)a,y=*(const size_t *)b;
    return (x>y)-(x<y);
}

static size_t percentile(size_t *samples,size_t n,unsigned thousandths) {
    qsort(samples,n,sizeof *samples,compare_size);
    return samples[(n-1)*thousandths/1000];
}

// Find the paper against the scanner's dark backing, independently of printed
// content. Inscribe a rectangle inside the robust edge estimates; never crop to ink.
static struct bounds paper_bounds(const uint8_t *rgb,size_t w,size_t h) {
    struct bounds full={0,0,w,h};
    if(w<64 || h<64)return full;
    size_t top=h,bottom=0;
    for(size_t y=0;y<h;y++) {
        size_t light=0;
        for(size_t x=0;x<w;x+=4)light+=luminance(rgb+3*(y*w+x))>=64;
        if(light*12>=w) { if(top==h)top=y;bottom=y+1; }
    }
    if(top==h || bottom-top<h*3/5)return full;
    size_t *starts=malloc(maximum((unsigned)w,(unsigned)h)*sizeof *starts);
    size_t *ends=malloc(maximum((unsigned)w,(unsigned)h)*sizeof *ends);
    if(!starts || !ends){free(starts);free(ends);return full;}
    size_t count=0;
    for(size_t y=top;y<bottom;y+=4) {
        size_t left=0,right=w;
        while(left<w && luminance(rgb+3*(y*w+left))<64)left++;
        while(right>left && luminance(rgb+3*(y*w+right-1))<64)right--;
        if(right-left>=w*3/5) { starts[count]=left;ends[count]=right;count++; }
    }
    if(!count){free(starts);free(ends);return full;}
    size_t left=percentile(starts,count,995),right=percentile(ends,count,5);
    count=0;
    for(size_t x=left;x<right;x+=4) {
        size_t a=top,b=bottom;
        while(a<bottom && luminance(rgb+3*(a*w+x))<64)a++;
        while(b>a && luminance(rgb+3*((b-1)*w+x))<64)b--;
        if(b-a>=h*3/5){starts[count]=a;ends[count]=b;count++;}
    }
    if(count){top=percentile(starts,count,995);bottom=percentile(ends,count,5);}
    free(starts);free(ends);
    if(right<=left || bottom<=top || right-left<w*3/5 || bottom-top<h*3/5)return full;
    if(left>0)left+=2;
    if(top>0)top+=2;
    if(right<w)right-=2;
    if(bottom<h)bottom-=2;
    return (struct bounds){left,top,right,bottom};
}

static unsigned mode(const size_t hist[256],unsigned low,unsigned high) {
    size_t best=0;
    unsigned selected=low;
    for(unsigned i=low;i<=high;i++) {
        size_t count=0;
        for(unsigned j=i>4?i-4:0;j<=minimum(255,i+4);j++)count+=hist[j];
        if(count>best){best=count;selected=i;}
    }
    return selected;
}

static uint8_t quantile(const size_t hist[256],size_t count) {
    size_t target=count/5+1,sum=0; // Lower paper percentile leaves texture near white.
    for(unsigned i=0;i<256;i++){sum+=hist[i];if(sum>=target)return (uint8_t)i;}
    return 255;
}

static bool paper_level(const uint8_t *rgb,size_t stride,struct bounds area,
                        unsigned low,unsigned high,uint8_t white[3]) {
    size_t hist[256]={0},channels[3][256]={{0}},samples=0,candidates=0;
    for(size_t y=area.top;y<area.bottom;y+=2)for(size_t x=area.left;x<area.right;x+=2) {
        const uint8_t *p=rgb+3*(y*stride+x);
        unsigned v=luminance(p);samples++;
        if(neutral(p) && v>=low && v<=high){hist[v]++;candidates++;}
    }
    if(candidates<samples/3 || !candidates)return false;
    unsigned peak=mode(hist,low,high),a=maximum(low,peak>12?peak-12:0),b=minimum(high,peak+12);
    size_t count=0;
    for(size_t y=area.top;y<area.bottom;y+=2)for(size_t x=area.left;x<area.right;x+=2) {
        const uint8_t *p=rgb+3*(y*stride+x);
        unsigned v=luminance(p);
        if(neutral(p) && v>=a && v<=b) {
            for(unsigned c=0;c<3;c++)channels[c][p[c]]++;
            count++;
        }
    }
    if(count<samples/4)return false;
    for(unsigned c=0;c<3;c++)white[c]=quantile(channels[c],count);
    return true;
}

bool ds_document_clean(const uint8_t *rgb,size_t w,size_t h,struct ds_document *out) {
    if(!out)return false;
    memset(out,0,sizeof *out);
    if(!rgb || !w || !h || w>20000 || h>20000 || w*h>30000000)return false;
    struct bounds crop=paper_bounds(rgb,w,h);
    out->left=crop.left;out->top=crop.top;
    out->width=crop.right-crop.left;out->height=crop.bottom-crop.top;
    out->cropped=out->width!=w || out->height!=h;
    out->pixels=malloc(out->width*out->height*3);
    if(!out->pixels)return false;
    for(size_t y=0;y<out->height;y++)memcpy(out->pixels+3*y*out->width,
        rgb+3*((y+crop.top)*w+crop.left),out->width*3);
    if(w<64 || h<64 || !paper_level(rgb,w,crop,96,245,out->paper))return true;

    size_t nx=(out->width+TILE-1)/TILE,ny=(out->height+TILE-1)/TILE;
    uint8_t *grid=malloc(nx*ny*3);
    if(!grid){free(out->pixels);memset(out,0,sizeof *out);return false;}
    unsigned center=luminance(out->paper),low=maximum(96,center>40?center-40:0),high=minimum(245,center+40);
    for(size_t gy=0;gy<ny;gy++)for(size_t gx=0;gx<nx;gx++) {
        struct bounds tile={crop.left+gx*TILE,crop.top+gy*TILE,
            minimum((unsigned)crop.right,(unsigned)(crop.left+(gx+1)*TILE)),
            minimum((unsigned)crop.bottom,(unsigned)(crop.top+(gy+1)*TILE))};
        uint8_t *level=grid+3*(gy*nx+gx);
        if(!paper_level(rgb,w,tile,low,high,level))memcpy(level,out->paper,3);
    }
    // Bilinear white-field interpolation avoids rectangular seams between tiles.
    for(size_t y=0;y<out->height;y++)for(size_t x=0;x<out->width;x++) {
        double fx=((double)x+0.5)/TILE-0.5,fy=((double)y+0.5)/TILE-0.5;
        if(fx<0)fx=0;
        if(fy<0)fy=0;
        size_t x0=(size_t)fx,y0=(size_t)fy;
        if(x0>=nx-1){x0=nx-1;fx=(double)x0;}
        if(y0>=ny-1){y0=ny-1;fy=(double)y0;}
        size_t x1=x0+1<nx?x0+1:x0,y1=y0+1<ny?y0+1:y0;
        double dx=fx-x0,dy=fy-y0;
        for(unsigned c=0;c<3;c++) {
            double a=grid[3*(y0*nx+x0)+c]*(1-dx)+grid[3*(y0*nx+x1)+c]*dx;
            double b=grid[3*(y1*nx+x0)+c]*(1-dx)+grid[3*(y1*nx+x1)+c]*dx;
            double white=a*(1-dy)+b*dy;
            uint8_t *p=out->pixels+3*(y*out->width+x)+c;
            double value=*p*255.0/white;
            *p=value>=255?255:(uint8_t)(value+0.5);
        }
    }
    out->normalized=true;free(grid);return true;
}

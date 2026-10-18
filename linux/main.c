// SPDX-License-Identifier: MIT
#define _POSIX_C_SOURCE 200809L
#include "usb_libusb.h"
#include "raster.h"
#include <png.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>

static bool save(const char *path,struct ds_document *page){
    int fd=open(path,O_WRONLY|O_CREAT|O_EXCL,0600);if(fd<0){perror(path);return false;}
    FILE *file=fdopen(fd,"wb");if(!file){close(fd);unlink(path);return false;}
    png_structp png=png_create_write_struct(PNG_LIBPNG_VER_STRING,NULL,NULL,NULL);
    png_infop info=png?png_create_info_struct(png):NULL;bool ok=false;
    if(png && info && !setjmp(png_jmpbuf(png))){
        png_init_io(png,file);png_set_IHDR(png,info,(png_uint_32)page->width,(png_uint_32)page->height,8,PNG_COLOR_TYPE_RGB,PNG_INTERLACE_NONE,PNG_COMPRESSION_TYPE_DEFAULT,PNG_FILTER_TYPE_DEFAULT);
        png_set_pHYs(png,info,11811,11811,PNG_RESOLUTION_METER);png_set_sRGB(png,info,PNG_sRGB_INTENT_PERCEPTUAL);png_write_info(png,info);
        for(size_t y=0;y<page->height;y++)png_write_row(png,page->pixels+y*page->width*3);
        png_write_end(png,info);ok=true;
    }
    if(png)png_destroy_write_struct(&png,info?&info:NULL);
    if(fclose(file))ok=false;if(!ok)unlink(path);return ok;
}
int main(int argc,char **argv){
    bool probe=argc==2 && !strcmp(argv[1],"probe");
    bool scan=(argc==3 || argc==4) && !strcmp(argv[1],"scan") && (argc==3 || !strcmp(argv[3],"--raw"));
    if(!probe && !scan){fprintf(stderr,"Usage: ds720d-linux probe | scan OUTPUT_PREFIX [--raw]\n");return 64;}
    char error[160]={0};struct ds_usb *usb=ds_usb_open(error);
    if(!usb){fprintf(stderr,"%s\n",error);return 1;}
    struct ds_engine engine={.io=ds_usb_io(usb)};
    if(probe){bool ok=ds_engine_identify(&engine);ds_usb_close(usb);puts(ok?"Brother DS-720D detected.":engine.error);return ok?0:1;}
    uint8_t *raw=NULL;size_t length=0;bool ok=ds_engine_capture(&engine,&raw,&length);ds_usb_close(usb);
    if(!ok){fprintf(stderr,"%s\n",engine.error);return 1;}
    for(unsigned side=0;side<2 && ok;side++){
        struct ds_document page;ok=ds_raster_side(raw,length,side,argc!=4,&page);if(!ok)break;
        size_t capacity=strlen(argv[2])+20;char *path=malloc(capacity);
        if(path){snprintf(path,capacity,"%s-%s.png",argv[2],side?"back":"front");ok=save(path,&page);if(ok)printf("%s (%zux%zu)\n",path,page.width,page.height);free(path);}else ok=false;
        free(page.pixels);
    }
    free(raw);return ok?0:1;
}

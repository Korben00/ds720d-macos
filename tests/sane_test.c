// SPDX-License-Identifier: MIT
#include "sane_prefix.h"
#include <sane/sane.h>
#include "usb_libusb.h"
#include "packet.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned captures;
int ds_usb_count(void){return 1;}
struct ds_usb *ds_usb_open(char error[160]){(void)error;return (struct ds_usb *)(uintptr_t)1;}
void ds_usb_close(struct ds_usb *usb){(void)usb;}
struct ds_io ds_usb_io(struct ds_usb *usb){(void)usb;return (struct ds_io){0};}
bool ds_engine_capture(struct ds_engine *engine,uint8_t **raw,size_t *length){
    (void)engine;captures++;*length=DS_NATIVE_BPL*160;*raw=malloc(*length);assert(*raw);memset(*raw,210,*length);return true;
}
static void consume(SANE_Handle h){
    SANE_Parameters p;assert(sane_get_parameters(h,&p)==SANE_STATUS_GOOD);
    assert(p.last_frame && p.depth==8 && p.format==SANE_FRAME_RGB && p.pixels_per_line==DS_NATIVE_WIDTH && p.lines==80);
    SANE_Byte bytes[1003];SANE_Int n;size_t total=0;SANE_Status status;
    while((status=sane_read(h,bytes,sizeof bytes,&n))==SANE_STATUS_GOOD){assert(n>0);total+=(size_t)n;}
    assert(status==SANE_STATUS_EOF && n==0 && total==(size_t)p.bytes_per_line*p.lines);
}
int main(void){
    SANE_Int version;assert(sane_init(&version,NULL)==SANE_STATUS_GOOD);const SANE_Device **devices;
    assert(sane_get_devices(&devices,SANE_TRUE)==SANE_STATUS_GOOD && devices[0] && !devices[1]);
    SANE_Handle h=NULL,other=NULL;assert(sane_open("",&h)==SANE_STATUS_GOOD);assert(sane_open("",&other)==SANE_STATUS_DEVICE_BUSY);
    SANE_Word clean=0;assert(sane_control_option(h,4,SANE_ACTION_SET_VALUE,&clean,NULL)==SANE_STATUS_GOOD);
    assert(sane_start(h)==SANE_STATUS_GOOD && captures==1);consume(h);
    assert(sane_start(h)==SANE_STATUS_GOOD && captures==1);consume(h);
    assert(sane_start(h)==SANE_STATUS_GOOD && captures==2);sane_cancel(h);
    SANE_Byte byte;SANE_Int length=9;assert(sane_read(h,&byte,1,&length)==SANE_STATUS_CANCELLED && length==0);
    assert(sane_start(h)==SANE_STATUS_GOOD && captures==3);consume(h);
    assert(sane_set_io_mode(h,SANE_TRUE)==SANE_STATUS_UNSUPPORTED);
    sane_close(h);assert(sane_get_parameters(h,NULL)==SANE_STATUS_INVAL);sane_exit();
    puts("SANE lifecycle: duplex pages share one feed, second sheet starts a new feed, cancellation discards cache, RGB sizes checked.");
}

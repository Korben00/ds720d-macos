// SPDX-License-Identifier: MIT
#include "engine.h"
#include "packet.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct firmware {bool locked,cancel,motor,malformed,calibrate;unsigned frames,stops,releases,transactions;uint8_t scsi[10];};
static void le32(uint8_t *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i));}
static uint32_t be32(const uint8_t *p){return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}
static bool cancel(void *context){return ((struct firmware *)context)->cancel;}
static int transfer(void *context,const uint8_t *cmd,size_t cmdn,uint8_t *in,size_t inn,const uint8_t *out,size_t outn){
    struct firmware *f=context;f->transactions++;assert(cmdn==16 && cmd[1]==7);if(in)memset(in,0,inn);
    if(cmd[0]==0xc3){assert(f->motor && !f->locked);assert(be32(cmd+6)==inn);for(size_t i=0;i<inn;i++)in[i]=(uint8_t)(be32(cmd+2)+i);return 0;}
    assert(cmd[0]==0xc5);uint8_t group=cmd[10],action=cmd[11],channel=cmd[12];
    if(group==255){
        if(action==2){assert(inn==4);memcpy(in,"NOVA",4);return 0;}
        assert(inn==16);le32(in,16);
        bool value=false;
        if(action==3)value=f->locked;
        else if(action==4)value=true;
        else if(action==5){assert(!f->locked);f->locked=true;value=true;}
        else if(action==6){assert(f->locked);f->locked=false;value=true;}
        else assert(0);
        le32(in+8,value);return 0;
    }
    assert(group==2 && f->locked);
    if(action==3){
        assert(channel==0 && outn>=10);memcpy(f->scsi,out,10);
        if(out[0]==0x24){assert(outn==89);uint8_t expected[79];ds_native_window(expected);assert(!memcmp(out+10,expected,79));}
        if(out[0]==0x1b){if(out[5]==0xc0)f->motor=true;else {f->motor=false;f->stops++;}}
        if(out[0]==0x17)f->releases++;
        return 0;
    }
    assert(action==1 || action==2);if(action==1)return 0;
    if(channel==3){assert(inn==2);in[0]=4;in[1]=0xf9;}
    else if(channel==4){assert(inn==2);in[0]=0x60;in[1]=0xe2;}
    else if(channel==0){
        if(f->scsi[0]==0x12){in[4]=31;if(inn>5)memcpy(in+8,"BROTHER DS-720D",15);}
        else if(f->scsi[0]==0x28 && f->scsi[2]==0xa0)in[0]=1;
        else if(f->scsi[0]==0x28 && f->scsi[2]==0x60)in[4]=f->calibrate?0:3;
        else assert(0);
    } else if(channel==2){
        assert(inn==24 && f->motor);
        if(f->frames<2){le32(in,1);le32(in+12,f->malformed?100:DS_NATIVE_WIDTH);le32(in+16,240);le32(in+20,0x100000+f->frames*DS_NATIVE_BPL*80);f->frames++;}
        else le32(in,3);
    } else assert(channel==1 && inn==4);
    return 0;
}
int main(void){
    struct firmware f={0};struct ds_engine e={.io={&f,transfer,cancel}};
    assert(ds_engine_identify(&e) && !f.motor && !f.locked && !f.stops);
    uint8_t *raw=NULL;size_t length=0;
    assert(ds_engine_capture(&e,&raw,&length));assert(length==DS_NATIVE_BPL*160 && f.stops==1 && f.releases==1 && !f.locked && !f.motor);
    for(size_t i=0;i<length;i++)assert(raw[i]==(uint8_t)(0x100000+i));
    free(raw);
    f=(struct firmware){.malformed=true};assert(!ds_engine_capture(&e,&raw,&length));assert(!raw && !length && f.stops==1 && f.releases==1 && !f.motor && !f.locked);
    f=(struct firmware){.calibrate=true};assert(!ds_engine_capture(&e,&raw,&length));assert(!f.motor && !f.stops && !f.releases && !f.locked);
    f=(struct firmware){.cancel=true};assert(!ds_engine_capture(&e,&raw,&length));assert(f.transactions==0);
    puts("Portable acquisition: identity, exact window, duplex, EOF, malformed metadata, calibration guard and cancellation checked.");
}

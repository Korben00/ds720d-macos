// SPDX-License-Identifier: MIT
#define _POSIX_C_SOURCE 200809L
#include "engine.h"
#include "packet.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
static void pause_poll(void){struct timespec t={0,10000000};nanosleep(&t,NULL);}
static bool fail(struct ds_engine *e,const char *text){snprintf(e->error,sizeof e->error,"%s",text);return false;}
static bool transaction(struct ds_engine *e,const uint8_t *cdb,size_t cdbn,uint8_t *in,size_t inn,const uint8_t *out,size_t outn){
    if(!e->cleanup && ((e->io.cancelled && e->io.cancelled(e->io.context)) || (e->deadline && now()>e->deadline)))return fail(e,"Acquisition cancelled or timed out.");
    if(e->io.command(e->io.context,cdb,cdbn,in,inn,out,outn))return fail(e,"USB transaction failed.");
    return true;
}
static bool exchange(struct ds_engine *e,uint8_t group,uint8_t action,uint8_t channel,uint8_t *in,size_t inn,const uint8_t *out,size_t outn){
    uint8_t cdb[16];ds_novatek_cdb(cdb,group,action,channel,(uint32_t)(inn?inn:outn));
    return transaction(e,cdb,16,in,inn,out,outn);
}
static bool service(struct ds_engine *e,uint8_t action,bool *value){
    uint8_t bytes[16];if(!exchange(e,255,action,0,bytes,16,NULL,0))return false;
    if(ds_read_le32(bytes)!=16)return fail(e,"Malformed bridge service response.");
    *value=ds_read_le32(bytes+8)!=0;return true;
}
static bool ready(struct ds_engine *e){
    double deadline=now()+5;
    do {bool value=false;if(!service(e,4,&value))return false;if(value)return true;pause_poll();}while(now()<deadline);
    return fail(e,"Scanner bridge readiness timed out.");
}
static bool claim(struct ds_engine *e){
    bool value=false;
    if(!ready(e) || !service(e,3,&value))return false;
    if(value)return fail(e,"Scanner firmware is already locked; reconnect the USB cable.");
    if(!service(e,5,&value))return false;
    return value || fail(e,"Scanner refused its transaction lock.");
}
static bool release(struct ds_engine *e){
    // Always release our own lock, including when cancellation arrives mid-command.
    bool previous=e->cleanup;e->cleanup=true;
    bool value=false,ok=ready(e) && service(e,6,&value);
    e->cleanup=previous;return ok && (value || fail(e,"Scanner refused to release its lock."));
}
static bool write_channel(struct ds_engine *e,uint8_t channel,const uint8_t *bytes,size_t length){
    if(!claim(e))return false;
    bool ok=exchange(e,2,3,channel,NULL,0,bytes,length);
    bool released=release(e);return ok && released;
}
static bool read_channel(struct ds_engine *e,uint8_t channel,uint8_t *bytes,size_t length){
    if(!claim(e))return false;
    bool ok=exchange(e,2,1,channel,bytes,length,NULL,0) && ready(e) && exchange(e,2,2,channel,bytes,length,NULL,0);
    bool released=release(e);return ok && released;
}
static bool scanner(struct ds_engine *e,const uint8_t cmd[10],uint8_t *in,size_t inn,const uint8_t *out,size_t outn){
    if(inn>65536 || outn>65526 || (inn && outn))return fail(e,"Invalid scanner command bounds.");
    uint8_t packet[65536];memcpy(packet,cmd,10);if(outn)memcpy(packet+10,out,outn);
    if(!write_channel(e,0,packet,10+outn) || (inn && !read_channel(e,0,in,inn)))return false;
    uint8_t status[4];if(!read_channel(e,1,status,4))return false;
    return !ds_read_le32(status) || fail(e,"Scanner reported an error status.");
}
static bool simple(struct ds_engine *e,uint8_t opcode){uint8_t cmd[10]={opcode};return scanner(e,cmd,NULL,0,NULL,0);}
bool ds_engine_identify(struct ds_engine *e){
    if(!e || !e->io.command)return false;
    e->error[0]=0;e->cleanup=false;
    uint8_t magic[4],vid[2],pid[2];
    if(!exchange(e,255,2,0,magic,4,NULL,0) || !read_channel(e,3,vid,2) || !read_channel(e,4,pid,2))return false;
    if(memcmp(magic,"NOVA",4) || memcmp(vid,"\x04\xf9",2) || memcmp(pid,"\x60\xe2",2))return fail(e,"Unexpected USB bridge identity.");
    uint8_t cmd[10]={0x12,0,0,0,5},inquiry[255];
    if(!scanner(e,cmd,inquiry,5,NULL,0))return false;
    unsigned length=(unsigned)inquiry[4]+5;if(length>255)length=255;
    if(length<36)return fail(e,"Incomplete scanner inquiry.");
    cmd[4]=(uint8_t)length;if(!scanner(e,cmd,inquiry,length,NULL,0))return false;
    return !memcmp(inquiry+8,"BROTHER ",8) && !memcmp(inquiry+16,"DS-720D",7) ? true:fail(e,"Unexpected scanner model.");
}
static bool image_block(struct ds_engine *e,uint8_t *buffer,size_t *length,bool *end){
    uint32_t requested=DS_NATIVE_BPL*DS_STRIPE_ROWS;
    uint8_t cmd[10]={0x28,0,0,0,0x0a,0x0d};cmd[6]=(uint8_t)(requested>>16);cmd[7]=(uint8_t)(requested>>8);cmd[8]=(uint8_t)requested;
    if(!write_channel(e,0,cmd,10))return false;
    uint8_t metadata[24];uint32_t w[6]={0};double deadline=now()+15;
    do {
        if(!read_channel(e,2,metadata,24))return false;
        for(unsigned i=0;i<6;i++)w[i]=ds_read_le32(metadata+4*i);
        if(w[0] && !(w[0]==1 && !w[5]))break;
        pause_poll();
    }while(now()<deadline);
    uint64_t size=(uint64_t)w[3]*w[4];
    if((w[0]!=1 && w[0]!=3) || size>requested || (size && (w[3]!=DS_NATIVE_WIDTH || w[4]%3)) || (!size && w[0]!=3) || (w[5]&3) || w[5]>UINT32_MAX-size)return fail(e,"Invalid scanner image metadata.");
    for(uint32_t offset=0;offset<size;) {
        uint32_t chunk=(uint32_t)(size-offset);if(chunk>65536)chunk=65536;
        uint8_t cdb[16]={0xc3,7};ds_write_be32(cdb+2,w[5]+offset);ds_write_be32(cdb+6,chunk);
        if(!transaction(e,cdb,16,buffer+offset,chunk,NULL,0))return false;
        offset+=chunk;
    }
    uint8_t status[4];if(!read_channel(e,1,status,4))return false;
    if(ds_read_le32(status))return fail(e,"Scanner image read returned an error.");
    *length=(size_t)size;*end=w[0]==3;return true;
}
bool ds_engine_capture(struct ds_engine *e,uint8_t **raw,size_t *length){
    if(!e || !raw || !length || !e->io.command)return false;
    *raw=NULL;*length=0;e->deadline=now()+150;e->cleanup=false;
    bool reserved=false,started=false,ok=false;uint8_t *data=NULL;size_t used=0;
    if(!ds_engine_identify(e) || !simple(e,0))goto done;
    uint8_t cmd[10]={0x28,0,0xa0,0,0x0a,0x0d,0,0,2},light[2];
    if(!scanner(e,cmd,light,2,NULL,0))goto done;
    if(light[0]==0){uint8_t send[10]={0x2a,0,0xa0,0,0,0,0,0,1},on=1;if(!scanner(e,send,NULL,0,&on,1))goto done;}
    else if(light[0]!=1){fail(e,"Scanner illumination is not ready.");goto done;}
    uint8_t format[10]={0x28,0,0x60,0,0x0a,0x0d,0,0,32},calibration[32];
    if(!scanner(e,format,calibration,32,NULL,0))goto done;
    if((calibration[4]&3)!=3){fail(e,"Scanner requires calibration; no scan was started.");goto done;}
    uint8_t window[79],setup[10]={0x24};ds_native_window(window);setup[8]=sizeof window;
    if(!scanner(e,setup,NULL,0,window,sizeof window) || !simple(e,0x16))goto done;
    reserved=true;uint8_t start[10]={0x1b,0,0,0,0,0xc0};
    if(!scanner(e,start,NULL,0,NULL,0))goto done;
    started=true;
    for(unsigned blocks=0;blocks<256;blocks++) {
        uint8_t block[DS_NATIVE_BPL*DS_STRIPE_ROWS];size_t size=0;bool end=false;
        if(!image_block(e,block,&size,&end))goto done;
        if(size>80000000-used){fail(e,"Capture exceeded its byte limit.");goto done;}
        if(size){uint8_t *next=realloc(data,used+size);if(!next){fail(e,"Out of memory.");goto done;}data=next;memcpy(data+used,block,size);used+=size;}
        if(end){ok=used>0;break;}
    }
    if(!ok)fail(e,"Scanner did not finish within acquisition bounds.");
done:
    e->cleanup=true;
    char failure[sizeof e->error];memcpy(failure,e->error,sizeof failure);
    if(started && !simple(e,0x1b))ok=false;
    if(reserved && !simple(e,0x17))ok=false;
    if(failure[0])memcpy(e->error,failure,sizeof failure);
    e->cleanup=false;e->deadline=0;
    if(ok){*raw=data;*length=used;}else free(data);
    return ok;
}

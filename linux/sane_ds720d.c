// SPDX-License-Identifier: MIT
#include "sane_prefix.h"
#include <sane/sane.h>
#include "usb_libusb.h"
#include "raster.h"
#include "packet.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct scanner {
    atomic_bool cancelled;
    bool acquiring,reading,clean;
    struct ds_document pages[2];
    int current,next;
    size_t offset;
};
static struct scanner *opened;
static const SANE_Device device={"usb:04f9:60e2","Brother","DS-720D (MIT)","sheetfed scanner"};
static const SANE_Device *devices[2];
static const SANE_String_Const modes[]={"Color",NULL},sources[]={"ADF Duplex",NULL};
static const SANE_Word resolutions[]={1,300};
static const SANE_Option_Descriptor options[]={
    {.name="",.title="Number of options",.type=SANE_TYPE_INT,.size=sizeof(SANE_Word),.cap=SANE_CAP_SOFT_DETECT},
    {.name="mode",.title="Scan mode",.desc="24-bit RGB",.type=SANE_TYPE_STRING,.size=6,.cap=SANE_CAP_SOFT_DETECT,.constraint_type=SANE_CONSTRAINT_STRING_LIST,.constraint.string_list=modes},
    {.name="resolution",.title="Resolution",.desc="Native 300 dpi",.type=SANE_TYPE_INT,.unit=SANE_UNIT_DPI,.size=sizeof(SANE_Word),.cap=SANE_CAP_SOFT_DETECT,.constraint_type=SANE_CONSTRAINT_WORD_LIST,.constraint.word_list=resolutions},
    {.name="source",.title="Source",.desc="One sheet, front and back",.type=SANE_TYPE_STRING,.size=11,.cap=SANE_CAP_SOFT_DETECT,.constraint_type=SANE_CONSTRAINT_STRING_LIST,.constraint.string_list=sources},
    {.name="document-cleanup",.title="Clean document",.desc="Remove dark backing and normalize neutral paper. Disable for photos or shading.",.type=SANE_TYPE_BOOL,.size=sizeof(SANE_Word),.cap=SANE_CAP_SOFT_SELECT|SANE_CAP_SOFT_DETECT}
};
enum {OPTION_COUNT=sizeof options/sizeof options[0]};
static bool valid(SANE_Handle h){return h && h==opened;}
static void clear_pages(struct scanner *s){for(unsigned i=0;i<2;i++){free(s->pages[i].pixels);memset(&s->pages[i],0,sizeof s->pages[i]);}s->reading=false;s->next=0;s->offset=0;}
SANE_Status sane_init(SANE_Int *version,SANE_Auth_Callback auth){(void)auth;if(version)*version=SANE_VERSION_CODE(1,0,1);return SANE_STATUS_GOOD;}
void sane_exit(void){if(opened)sane_close(opened);devices[0]=NULL;}
SANE_Status sane_get_devices(const SANE_Device ***out,SANE_Bool local){(void)local;if(!out)return SANE_STATUS_INVAL;int count=ds_usb_count();if(count<0)return SANE_STATUS_IO_ERROR;devices[0]=count==1?&device:NULL;devices[1]=NULL;*out=devices;return SANE_STATUS_GOOD;}
SANE_Status sane_open(SANE_String_Const name,SANE_Handle *out){
    if(!name || !out)return SANE_STATUS_INVAL;
    if(*name && strcmp(name,device.name) && strcmp(name,"usb:04f9:60e2"))return SANE_STATUS_INVAL;
    if(opened)return SANE_STATUS_DEVICE_BUSY;
    if(ds_usb_count()!=1)return SANE_STATUS_INVAL;
    opened=calloc(1,sizeof *opened);if(!opened)return SANE_STATUS_NO_MEM;
    atomic_init(&opened->cancelled,false);opened->clean=true;*out=opened;return SANE_STATUS_GOOD;
}
void sane_close(SANE_Handle h){if(!valid(h))return;atomic_store(&opened->cancelled,true);if(opened->acquiring)return;clear_pages(opened);free(opened);opened=NULL;}
const SANE_Option_Descriptor *sane_get_option_descriptor(SANE_Handle h,SANE_Int option){return valid(h) && option>=0 && option<OPTION_COUNT?options+option:NULL;}
SANE_Status sane_control_option(SANE_Handle h,SANE_Int option,SANE_Action action,void *value,SANE_Int *info){
    if(info)*info=0;
    if(!valid(h) || !value || option<0 || option>=OPTION_COUNT)return SANE_STATUS_INVAL;
    struct scanner *s=h;if(s->acquiring || s->reading)return SANE_STATUS_DEVICE_BUSY;
    if(action==SANE_ACTION_GET_VALUE){switch(option){case 0:*(SANE_Word *)value=OPTION_COUNT;break;case 1:strcpy(value,"Color");break;case 2:*(SANE_Word *)value=300;break;case 3:strcpy(value,"ADF Duplex");break;case 4:*(SANE_Word *)value=s->clean;break;}return SANE_STATUS_GOOD;}
    if(option!=4 || action!=SANE_ACTION_SET_VALUE)return SANE_STATUS_UNSUPPORTED;
    SANE_Word clean=*(SANE_Word *)value;if(clean!=SANE_FALSE && clean!=SANE_TRUE)return SANE_STATUS_INVAL;
    s->clean=clean!=0;clear_pages(s);if(info)*info=SANE_INFO_RELOAD_PARAMS;return SANE_STATUS_GOOD;
}
SANE_Status sane_get_parameters(SANE_Handle h,SANE_Parameters *p){
    if(!valid(h) || !p)return SANE_STATUS_INVAL;
    struct scanner *s=h;struct ds_document *page=s->pages+s->current;
    *p=(SANE_Parameters){SANE_FRAME_RGB,SANE_TRUE,(SANE_Int)(page->pixels?page->width*3:DS_NATIVE_BPL),(SANE_Int)(page->pixels?page->width:DS_NATIVE_WIDTH),page->pixels?(SANE_Int)page->height:-1,8};
    return SANE_STATUS_GOOD;
}
struct acquisition {struct ds_io usb;struct scanner *scanner;};
static int transfer(void *p,const uint8_t *cmd,size_t cmdn,uint8_t *in,size_t inn,const uint8_t *out,size_t outn){struct acquisition *a=p;return a->usb.command(a->usb.context,cmd,cmdn,in,inn,out,outn);}
static bool cancelled(void *p){return atomic_load(&((struct acquisition *)p)->scanner->cancelled);}
SANE_Status sane_start(SANE_Handle h){
    if(!valid(h))return SANE_STATUS_INVAL;
    struct scanner *s=h;
    if(s->acquiring || s->reading)return SANE_STATUS_DEVICE_BUSY;
    if(atomic_load(&s->cancelled)){clear_pages(s);atomic_store(&s->cancelled,false);}
    if(s->next==1 && s->pages[1].pixels){s->current=1;s->next=2;s->offset=0;s->reading=true;return SANE_STATUS_GOOD;}
    clear_pages(s);s->acquiring=true;
    char error[160]={0};struct ds_usb *usb=ds_usb_open(error);
    if(!usb){s->acquiring=false;return SANE_STATUS_ACCESS_DENIED;}
    struct acquisition context={ds_usb_io(usb),s};
    struct ds_engine engine={.io={&context,transfer,cancelled}};
    uint8_t *raw=NULL;size_t length=0;bool ok=ds_engine_capture(&engine,&raw,&length);
    ds_usb_close(usb);
    if(ok)ok=ds_raster_side(raw,length,0,s->clean,s->pages) && ds_raster_side(raw,length,1,s->clean,s->pages+1);
    free(raw);s->acquiring=false;
    if(!ok || atomic_load(&s->cancelled)){clear_pages(s);return atomic_load(&s->cancelled)?SANE_STATUS_CANCELLED:SANE_STATUS_IO_ERROR;}
    s->current=0;s->next=1;s->offset=0;s->reading=true;return SANE_STATUS_GOOD;
}
SANE_Status sane_read(SANE_Handle h,SANE_Byte *data,SANE_Int maximum,SANE_Int *length){
    if(length)*length=0;
    if(!valid(h) || !data || !length || maximum<=0)return SANE_STATUS_INVAL;
    struct scanner *s=h;if(atomic_load(&s->cancelled)){clear_pages(s);return SANE_STATUS_CANCELLED;}
    if(!s->reading)return SANE_STATUS_EOF;
    struct ds_document *page=s->pages+s->current;size_t total=page->width*page->height*3,remaining=total-s->offset;
    if(!remaining){s->reading=false;return SANE_STATUS_EOF;}
    size_t amount=remaining<(size_t)maximum?remaining:(size_t)maximum;
    memcpy(data,page->pixels+s->offset,amount);s->offset+=amount;*length=(SANE_Int)amount;return SANE_STATUS_GOOD;
}
void sane_cancel(SANE_Handle h){if(valid(h))atomic_store(&opened->cancelled,true);}
SANE_Status sane_set_io_mode(SANE_Handle h,SANE_Bool nonblocking){if(!valid(h))return SANE_STATUS_INVAL;return nonblocking?SANE_STATUS_UNSUPPORTED:SANE_STATUS_GOOD;}
SANE_Status sane_get_select_fd(SANE_Handle h,SANE_Int *fd){(void)h;(void)fd;return SANE_STATUS_UNSUPPORTED;}

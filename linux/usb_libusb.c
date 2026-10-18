// SPDX-License-Identifier: MIT
#include "usb_libusb.h"
#include "packet.h"
#include <libusb.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct ds_usb {libusb_context *context;libusb_device_handle *handle;int interface;uint8_t in,out;uint32_t tag;bool claimed,poisoned;atomic_bool cancelled;};
int ds_usb_count(void){
    libusb_context *context=NULL;if(libusb_init(&context))return -1;
    libusb_device **devices=NULL;ssize_t n=libusb_get_device_list(context,&devices);int count=0;
    if(n<0)count=-1;
    for(ssize_t i=0;i<n;i++){struct libusb_device_descriptor d;if(!libusb_get_device_descriptor(devices[i],&d) && d.idVendor==0x04f9 && d.idProduct==0x60e2)count++;}
    if(devices)libusb_free_device_list(devices,1);
    libusb_exit(context);return count;
}
struct ds_usb *ds_usb_open(char error[160]){
    struct ds_usb *usb=calloc(1,sizeof *usb);if(!usb)return NULL;atomic_init(&usb->cancelled,false);
    int result=libusb_init(&usb->context);if(result)goto fail;
    libusb_device **devices=NULL;ssize_t n=libusb_get_device_list(usb->context,&devices);libusb_device *selected=NULL;int count=0;
    for(ssize_t i=0;i<n;i++){struct libusb_device_descriptor d;if(!libusb_get_device_descriptor(devices[i],&d) && d.idVendor==0x04f9 && d.idProduct==0x60e2){selected=devices[i];count++;}}
    result=count==1?libusb_open(selected,&usb->handle):LIBUSB_ERROR_NO_DEVICE;
    if(devices)libusb_free_device_list(devices,1);
    if(result)goto fail;
    struct libusb_config_descriptor *config=NULL;result=libusb_get_active_config_descriptor(libusb_get_device(usb->handle),&config);if(result)goto fail;
    bool found=false;
    for(unsigned i=0;i<config->bNumInterfaces;i++)for(int a=0;a<config->interface[i].num_altsetting;a++){
        const struct libusb_interface_descriptor *d=config->interface[i].altsetting+a;
        if(d->bInterfaceClass!=8 || d->bInterfaceSubClass!=6 || d->bInterfaceProtocol!=0x50 || d->bAlternateSetting!=0)continue;
        uint8_t in=0,out=0;
        for(unsigned j=0;j<d->bNumEndpoints;j++)if((d->endpoint[j].bmAttributes&3)==2){uint8_t ep=d->endpoint[j].bEndpointAddress;if(ep&0x80)in=ep;else out=ep;}
        if(in && out){usb->interface=d->bInterfaceNumber;usb->in=in;usb->out=out;found=true;}
    }
    libusb_free_config_descriptor(config);if(!found){result=LIBUSB_ERROR_NOT_SUPPORTED;goto fail;}
    // Detach and reattach only the verified scanner interface, never a global USB driver.
    result=libusb_set_auto_detach_kernel_driver(usb->handle,1);
    if(result && result!=LIBUSB_ERROR_NOT_SUPPORTED)goto fail;
    result=libusb_claim_interface(usb->handle,usb->interface);if(result)goto fail;usb->claimed=true;return usb;
fail:
    snprintf(error,160,"Cannot open exactly one DS-720D: %s",libusb_error_name(result));ds_usb_close(usb);return NULL;
}
void ds_usb_close(struct ds_usb *usb){if(!usb)return;if(usb->claimed)libusb_release_interface(usb->handle,usb->interface);if(usb->handle)libusb_close(usb->handle);if(usb->context)libusb_exit(usb->context);free(usb);}
static int command(void *context,const uint8_t *cdb,size_t cdbn,uint8_t *in,size_t inn,const uint8_t *out,size_t outn){
    struct ds_usb *usb=context;size_t length=inn?inn:outn;
    if(usb->poisoned || length>65536 || (inn && outn))return -1;
    uint8_t cbw[31],csw[13];uint32_t tag=++usb->tag;
    if(!ds_cbw_encode(cbw,tag,cdb,cdbn,(uint32_t)length,inn>0))return -1;
    int transferred=0,result=libusb_bulk_transfer(usb->handle,usb->out,cbw,31,&transferred,5000);
    if(result || transferred!=31)goto poison;
    transferred=0;
    if(length){uint8_t ep=inn?usb->in:usb->out;result=libusb_bulk_transfer(usb->handle,ep,inn?in:(uint8_t *)(uintptr_t)out,(int)length,&transferred,20000);
        if(result==LIBUSB_ERROR_PIPE)result=libusb_clear_halt(usb->handle,ep);
        if(result)goto poison;
    }
    int statusn=0;result=libusb_bulk_transfer(usb->handle,usb->in,csw,13,&statusn,5000);if(result)goto poison;
    uint32_t residue=0;enum ds_bot_status status=ds_csw_decode(csw,(size_t)statusn,tag,(uint32_t)length,(uint32_t)transferred,&residue);
    if(status!=DS_BOT_OK || (size_t)transferred!=length){if(status!=DS_BOT_COMMAND_FAILED)usb->poisoned=true;return -1;}
    return 0;
poison:usb->poisoned=true;return -1;
}
static bool cancelled(void *context){return atomic_load(&((struct ds_usb *)context)->cancelled);}
void ds_usb_cancel(struct ds_usb *usb){if(usb)atomic_store(&usb->cancelled,true);}
struct ds_io ds_usb_io(struct ds_usb *usb){return (struct ds_io){usb,command,cancelled};}

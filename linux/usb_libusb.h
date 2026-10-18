// SPDX-License-Identifier: MIT
#ifndef DS720D_LIBUSB_H
#define DS720D_LIBUSB_H
#include "engine.h"
struct ds_usb;
int ds_usb_count(void);
struct ds_usb *ds_usb_open(char error[160]);
void ds_usb_close(struct ds_usb *usb);
struct ds_io ds_usb_io(struct ds_usb *usb);
void ds_usb_cancel(struct ds_usb *usb);
#endif

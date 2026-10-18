// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/scsi/SCSITaskLib.h>
#import <IOUSBHost/IOUSBHost.h>
#include <string.h>
#include <unistd.h>
#import "usb.h"
#import "packet.h"
#import "bridge.h"
#import "authorize.h"
#import "capture.h"

static BOOL isScanner(io_service_t service) {
    CFTypeRef vendor = IORegistryEntryCreateCFProperty(service, CFSTR("idVendor"), NULL, 0);
    CFTypeRef product = IORegistryEntryCreateCFProperty(service, CFSTR("idProduct"), NULL, 0);
    BOOL matches = vendor && product && CFGetTypeID(vendor) == CFNumberGetTypeID()
        && CFGetTypeID(product) == CFNumberGetTypeID()
        && [(__bridge NSNumber *)vendor unsignedIntValue] == 0x04f9
        && [(__bridge NSNumber *)product unsignedIntValue] == 0x60e2;
    if (vendor) CFRelease(vendor);
    if (product) CFRelease(product);
    return matches;
}

static BOOL hasScannerAncestor(io_service_t service) {
    io_registry_entry_t current = service;
    IOObjectRetain(current);
    BOOL found = NO;
    while (current) {
        if (IOObjectConformsTo(current, "IOUSBHostDevice") && isScanner(current)) {
            found = YES;
            IOObjectRelease(current);
            break;
        }
        io_registry_entry_t parent = IO_OBJECT_NULL;
        IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent);
        IOObjectRelease(current);
        current = parent;
    }
    return found;
}

static int probeSCSI(void) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching("IOSCSILogicalUnitNub"), &iterator);
    if (kr != KERN_SUCCESS) return 1;
    io_service_t service;
    BOOL found = NO;
    int result = 1;
    while ((service = IOIteratorNext(iterator))) {
        if (!hasScannerAncestor(service)) { IOObjectRelease(service); continue; }
        found = YES;
        IOCFPlugInInterface **plugin = NULL;
        SInt32 score = 0;
        kr = IOCreatePlugInInterfaceForService(service, kIOSCSITaskDeviceUserClientTypeID,
            kIOCFPlugInInterfaceID, &plugin, &score);
        printf("SCSI plugin: 0x%08x (%s)\n", kr, mach_error_string(kr));
        if (kr == KERN_SUCCESS && plugin) {
            SCSITaskDeviceInterface **device = NULL;
            HRESULT hr = (*plugin)->QueryInterface(plugin,
                CFUUIDGetUUIDBytes(kIOSCSITaskDeviceInterfaceID), (LPVOID *)&device);
            printf("SCSI interface: 0x%08x\n", (unsigned)hr);
            if (hr == S_OK && device) {
                kr = (*device)->ObtainExclusiveAccess(device);
                printf("SCSI exclusive access: 0x%08x (%s)\n", kr, mach_error_string(kr));
                if (kr == KERN_SUCCESS) {
                    result = 0;
                    (*device)->ReleaseExclusiveAccess(device);
                }
                (*device)->Release(device);
            }
            IODestroyPlugInInterface(plugin);
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    if (!found) fprintf(stderr, "DS-720D SCSI service not found.\n");
    return result;
}

static int listScanners(void) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching("IOUSBHostDevice"), &iterator);
    if (kr != KERN_SUCCESS) return 1;
    NSMutableArray *devices = [NSMutableArray array];
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        if (isScanner(service)) {
            uint64_t registryID = 0;
            IORegistryEntryGetRegistryEntryID(service, &registryID);
            [devices addObject:@{@"model": @"Brother DS-720D", @"vendorID": @"04f9",
                @"productID": @"60e2", @"registryID": @(registryID)}];
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    NSData *json = [NSJSONSerialization dataWithJSONObject:devices options:NSJSONWritingPrettyPrinted error:NULL];
    fwrite(json.bytes, 1, json.length, stdout);
    putchar('\n');
    return devices.count ? 0 : 2;
}

static int probeUSB(void) {
    if (geteuid() != 0) {
        fprintf(stderr, "USB capture requires administrator access. Run this command with sudo.\n");
        return 1;
    }
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching("IOUSBHostDevice"), &iterator);
    if (kr != KERN_SUCCESS) return 1;
    io_service_t selected = IO_OBJECT_NULL, service;
    unsigned count = 0;
    while ((service = IOIteratorNext(iterator))) {
        if (isScanner(service)) {
            count++;
            if (!selected) { selected = service; continue; }
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    if (count != 1) {
        if (selected) IOObjectRelease(selected);
        fprintf(stderr, "Connect exactly one DS-720D (found %u).\n", count);
        return 2;
    }
    NSError *error = nil;
    IOUSBHostDevice *device = [[IOUSBHostDevice alloc] initWithIOService:selected
        options:IOUSBHostObjectInitOptionsDeviceCapture queue:nil error:&error interestHandler:nil];
    IOObjectRelease(selected);
    if (!device) {
        fprintf(stderr, "USB capture: %s\n", error.description.UTF8String);
        return 1;
    }
    printf("USB exclusive capture acquired.\n");
    const IOUSBConfigurationDescriptor *config = [device configurationDescriptorWithIndex:0 error:&error];
    if (config) {
        const uint8_t *bytes = (const uint8_t *)config;
        size_t length = bytes[2] | ((size_t)bytes[3] << 8);
        printf("Configuration descriptor (%zu bytes):", length);
        for (size_t i = 0; i < length; i++) printf(" %02x", bytes[i]);
        putchar('\n');
    } else fprintf(stderr, "Descriptor: %s\n", error.description.UTF8String);
    [device destroy];
    return config ? 0 : 1;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if(argc==2 && !strcmp(argv[1],"authorize-probe"))return ds_authorize_probe(argv[0]);
        if(argc==2 && !strcmp(argv[1],"authorize-scan"))return ds_authorize_scan(argv[0]);
        if(argc==4 && !strcmp(argv[1],"authorize-scan") && !strcmp(argv[2],"--output-dir"))return ds_authorize_scan_to(argv[0],argv[3]);
        if(argc==2 && !strcmp(argv[1],"authorize-inspect"))return ds_authorize_inspect(argv[0]);
        if(argc==2 && !strcmp(argv[1],"inspect"))return ds_inspect();
        if(argc==2 && !strcmp(argv[1],"capture"))return ds_capture();
        if(argc==3 && !strcmp(argv[1],"decode"))return ds_decode_capture(argv[2]);
        if(argc==4 && !strcmp(argv[1],"decode") && !strcmp(argv[3],"--raw"))return ds_decode_capture_raw(argv[2]);
        if (argc == 2 && strcmp(argv[1], "list") == 0) return listScanners();
        if (argc == 2 && strcmp(argv[1], "probe-scsi") == 0) return probeSCSI();
        if (argc == 2 && strcmp(argv[1], "probe-usb") == 0) return probeUSB();
        if (argc == 2 && strcmp(argv[1], "probe") == 0) {
            alarm(90);
            NSError *error = nil;
            DSUSB *usb = [DSUSB openScanner:&error];
            if (!usb) { fprintf(stderr, "%s\n", error.description.UTF8String); return 1; }
            uint8_t inquiry[] = {0x12, 0, 0, 0, 36, 0};
            NSData *reply = [usb executeCDB:[NSData dataWithBytes:inquiry length:6] inputLength:36 output:nil error:&error];
            if (reply) printf("SCSI identity: %.*s\n", (int)MAX(0, (NSInteger)reply.length - 8), (const char *)reply.bytes + MIN(8, reply.length));
            uint8_t cdb[16];
            ds_novatek_cdb(cdb, 0xff, 2, 0, 4);
            NSData *magic = reply ? [usb executeCDB:[NSData dataWithBytes:cdb length:16] inputLength:4 output:nil error:&error] : nil;
            if (magic) printf("Transport identity: %.*s\n", (int)magic.length, (const char *)magic.bytes);
            NSData *scanner = nil;
            if (magic.length == 4 && !memcmp(magic.bytes, "NOVA", 4)) {
                DSBridge *bridge = [[DSBridge alloc] initWithTransport:usb];
                scanner = [bridge inquiry:&error];
                if (scanner) printf("Scanner identity: %.*s\n", 28, (const char *)scanner.bytes + 8);
            } else if (magic) {
                error = [NSError errorWithDomain:@"DS720D" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Unexpected transport identity."}];
            }
            [usb close];
            if (!scanner) { fprintf(stderr, "%s\n", error.description.UTF8String); return 1; }
            return 0;
        }
        fprintf(stderr, "Usage: ds720d list | authorize-probe | authorize-inspect | authorize-scan\n"
            "       ds720d authorize-scan --output-dir DIRECTORY\n"
            "       ds720d decode CAPTURE.jsonl [--raw]\n"
            "       ds720d probe | inspect | capture | probe-scsi | probe-usb\n");
        return 64;
    }
}

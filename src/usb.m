// SPDX-License-Identifier: MIT
#import "usb.h"
#import "packet.h"
#import <IOUSBHost/IOUSBHost.h>
#import <IOKit/usb/USB.h>
#include <unistd.h>

static NSError *failure(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"DS720D.USB" code:code
        userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setError(NSError **target, NSError *value) {
    if (target) *target = value;
}

@implementation DSUSB {
    IOUSBHostDevice *_device;
    IOUSBHostInterface *_interface;
    IOUSBHostPipe *_input;
    IOUSBHostPipe *_output;
    uint32_t _tag;
    BOOL _poisoned;
}

+ (instancetype)openScanner:(NSError **)error {
    if (geteuid() != 0) {
        setError(error, failure(13, @"USB capture requires administrator access. Run this command with sudo."));
        return nil;
    }
    DSUSB *transport = [DSUSB new];
    CFMutableDictionaryRef match = IOServiceMatching("IOUSBHostDevice");
    NSDictionary *identity = @{@"idVendor": @0x04f9, @"idProduct": @0x60e2};
    CFDictionarySetValue(match, CFSTR("IOPropertyMatch"), (__bridge CFDictionaryRef)identity);
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator);
    if (kr != KERN_SUCCESS) { setError(error, failure(kr, @"Cannot enumerate USB devices.")); return nil; }
    io_service_t service = IOIteratorNext(iterator);
    io_service_t extra = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (!service || extra) {
        if (service) IOObjectRelease(service);
        if (extra) IOObjectRelease(extra);
        setError(error, failure(2, @"Connect exactly one Brother DS-720D."));
        return nil;
    }
    transport->_device = [[IOUSBHostDevice alloc] initWithIOService:service
        options:IOUSBHostObjectInitOptionsDeviceCapture queue:nil error:error interestHandler:nil];
    IOObjectRelease(service);
    if (!transport->_device) return nil;
    const IOUSBConfigurationDescriptor *config =
        [transport->_device configurationDescriptorWithIndex:0 error:error];
    if (!config) return nil;
    // Capture prevents the storage driver from reclaiming the scanner until close.
    if (![transport->_device configureWithValue:config->bConfigurationValue matchInterfaces:NO error:error]) return nil;
    // Reconfiguration terminates the previous interfaces. Enumerate afresh on
    // each bounded retry instead of stopping at a disappearing registry entry.
    NSError *interfaceError = nil;
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 3;
    do {
        kr = IORegistryEntryCreateIterator(transport->_device.ioService, kIOServicePlane,
            kIORegistryIterateRecursively, &iterator);
        if (kr != KERN_SUCCESS) { setError(error, failure(kr, @"Cannot enumerate scanner interfaces.")); return nil; }
        while ((service = IOIteratorNext(iterator))) {
            if (IOObjectConformsTo(service, "IOUSBHostInterface")) {
                transport->_interface = [[IOUSBHostInterface alloc] initWithIOService:service
                    options:IOUSBHostObjectInitOptionsNone queue:nil error:&interfaceError interestHandler:nil];
            }
            IOObjectRelease(service);
            if (transport->_interface) break;
        }
        IOObjectRelease(iterator);
        if (transport->_interface) break;
        if (interfaceError.code == (NSInteger)(int32_t)kIOReturnNotPrivileged ||
            interfaceError.code == (NSInteger)(int32_t)kIOReturnNotPermitted) break;
        usleep(100000);
    } while (NSProcessInfo.processInfo.systemUptime < deadline);
    if (!transport->_interface) {
        setError(error, interfaceError ?: failure(3, @"Scanner USB interface unavailable after capture."));
        return nil;
    }
    const IOUSBInterfaceDescriptor *iface = transport->_interface.interfaceDescriptor;
    if (!iface || iface->bInterfaceClass != 8 || iface->bInterfaceSubClass != 6 || iface->bInterfaceProtocol != 0x50) {
        setError(error, failure(4, @"Unexpected USB interface; refusing scanner commands."));
        return nil;
    }
    const IOUSBEndpointDescriptor *endpoint = NULL;
    while ((endpoint = IOUSBGetNextEndpointDescriptor(transport->_interface.configurationDescriptor,
        iface, (const IOUSBDescriptorHeader *)endpoint))) {
        if ((endpoint->bmAttributes & 3) != 2) continue;
        IOUSBHostPipe *pipe = [transport->_interface copyPipeWithAddress:endpoint->bEndpointAddress error:error];
        if (!pipe) return nil;
        if (endpoint->bEndpointAddress & 0x80) transport->_input = pipe;
        else transport->_output = pipe;
    }
    if (!transport->_input || !transport->_output) {
        setError(error, failure(5, @"Scanner must provide bulk IN and OUT endpoints."));
        return nil;
    }
    return transport;
}

- (NSData *)executeCDB:(NSData *)cdb inputLength:(NSUInteger)inputLength
                output:(NSData *)output error:(NSError **)error {
    if (_poisoned || !_device) { setError(error, failure(6, @"USB session is closed or requires reopening.")); return nil; }
    NSUInteger length = inputLength ? inputLength : output.length;
    if (length > 65536 || (inputLength && output.length) || cdb.length == 0 || cdb.length > 16) {
        setError(error, failure(7, @"Invalid USB command length or direction.")); return nil;
    }
    uint8_t cbw[31];
    uint32_t tag = ++_tag;
    if (!ds_cbw_encode(cbw, tag, cdb.bytes, cdb.length, (uint32_t)length, inputLength > 0)) {
        setError(error, failure(7, @"Invalid command wrapper.")); return nil;
    }
    NSUInteger done = 0;
    NSMutableData *wrapper = [NSMutableData dataWithBytes:cbw length:31];
    if (![_output sendIORequestWithData:wrapper bytesTransferred:&done completionTimeout:5 error:error] || done != 31) {
        _poisoned = YES;
        if (!error || !*error) setError(error, failure(8, @"Short USB command write."));
        return nil;
    }
    NSMutableData *data = inputLength ? [NSMutableData dataWithLength:inputLength] : [output mutableCopy];
    done = 0;
    if (length) {
        IOUSBHostPipe *pipe = inputLength ? _input : _output;
        NSError *dataError = nil;
        if (![pipe sendIORequestWithData:data bytesTransferred:&done completionTimeout:20 error:&dataError]) {
            if (dataError.code != (NSInteger)(int32_t)kIOUSBPipeStalled || ![pipe clearStallWithError:error]) {
                _poisoned = YES;
                if (!error || !*error) setError(error, dataError);
                return nil;
            }
        }
    }
    NSUInteger statusLength = 0;
    NSMutableData *status = [NSMutableData dataWithLength:13];
    if (![_input sendIORequestWithData:status bytesTransferred:&statusLength completionTimeout:5 error:error]) {
        _poisoned = YES; return nil;
    }
    uint32_t residue = 0;
    enum ds_bot_status result = ds_csw_decode(status.bytes, statusLength, tag,
        (uint32_t)length, (uint32_t)done, &residue);
    if (result != DS_BOT_OK) {
        _poisoned = result != DS_BOT_COMMAND_FAILED;
        setError(error, failure(result, [NSString stringWithFormat:@"USB command failed (status=%d, transferred=%lu, residue=%u).",
            result, (unsigned long)done, residue]));
        return nil;
    }
    if (output.length && done != output.length) {
        setError(error, failure(9, @"Scanner accepted only part of the outgoing command.")); return nil;
    }
    if (inputLength) { data.length = done; return data; }
    return [NSData data];
}

- (void)close {
    _input = nil; _output = nil;
    [_interface destroy]; _interface = nil;
    // Normal capture destruction resets USB, disconnecting the ICA module
    // before it can deliver its images. Surrender releases ownership without
    // resetting the device or rematching its mass-storage driver.
    [_device destroyWithOptions:IOUSBHostObjectDestroyOptionsDeviceSurrender]; _device = nil;
}

- (void)dealloc { [self close]; }
@end

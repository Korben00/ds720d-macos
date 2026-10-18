CC ?= cc
CFLAGS ?= -O2 -g
WARN = -std=c11 -Wall -Wextra -Werror
CPPFLAGS += -I../src -I. $(shell pkg-config --cflags libusb-1.0 libpng)
CORE = ../src/engine.c ../src/packet.c ../src/document.c ../src/raster.c usb_libusb.c
PREFIX ?= /usr
LIBDIR ?= $(PREFIX)/lib/$(shell $(CC) -dumpmachine)
DESTDIR ?=

.PHONY: all clean install test
all: build/ds720d-linux build/libsane-ds720d.so.1.0.0
build:
	mkdir -p $@
build/ds720d-linux: main.c $(CORE) | build
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $^ $(shell pkg-config --libs libusb-1.0 libpng) -o $@
build/libsane-ds720d.so.1.0.0: sane_ds720d.c $(CORE) | build
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fPIC -shared -Wl,-soname,libsane-ds720d.so.1 $^ $(shell pkg-config --libs libusb-1.0) -o $@
install: all
	install -Dm755 build/ds720d-linux $(DESTDIR)$(PREFIX)/bin/ds720d-linux
	install -Dm755 build/libsane-ds720d.so.1.0.0 $(DESTDIR)$(LIBDIR)/sane/libsane-ds720d.so.1.0.0
	ln -sfn libsane-ds720d.so.1.0.0 $(DESTDIR)$(LIBDIR)/sane/libsane-ds720d.so.1
	ln -sfn libsane-ds720d.so.1 $(DESTDIR)$(LIBDIR)/sane/libsane-ds720d.so
	install -Dm644 ../packaging/linux/60-ds720d.rules $(DESTDIR)/usr/lib/udev/rules.d/60-ds720d.rules
	install -Dm644 ../packaging/linux/ds720d.conf $(DESTDIR)/etc/sane.d/dll.d/ds720d.conf
	install -Dm644 ../LICENSE $(DESTDIR)$(PREFIX)/share/doc/ds720d/LICENSE
test: build/engine_test build/raster_test build/sane_test
	./build/engine_test
	./build/raster_test
	./build/sane_test
build/engine_test: ../tests/engine_test.c ../src/engine.c ../src/packet.c | build
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fsanitize=address,undefined $^ -o $@
build/raster_test: ../tests/raster_test.c ../src/raster.c ../src/document.c | build
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fsanitize=address,undefined $^ -o $@
build/sane_test: ../tests/sane_test.c sane_ds720d.c ../src/raster.c ../src/document.c | build
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fsanitize=address,undefined $^ -o $@
clean:
	rm -rf build

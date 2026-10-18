CC = xcrun clang
CFLAGS = -Wall -Wextra -Werror -O2 -g -mmacosx-version-min=14.0
FRAMEWORKS = -framework Foundation -framework IOKit -framework IOUSBHost -framework Security -framework ImageIO -framework CoreGraphics
MAC_SOURCES = src/main.m src/usb.m src/packet.c src/bridge.m src/authorize.m src/capture.m src/image.m src/document.c

.PHONY: all clean test analyze
all: build/ds720d

build/ds720d: src/main.m src/usb.m src/usb.h src/packet.c src/packet.h src/bridge.m src/bridge.h src/transport.h src/authorize.m src/authorize.h src/capture.m src/capture.h src/image.m src/document.c src/document.h
	@mkdir -p build
	$(CC) $(CFLAGS) -fobjc-arc $(MAC_SOURCES) $(FRAMEWORKS) -o $@
	codesign --force --sign - $@

build/ds720d-universal: $(MAC_SOURCES) src/authorize.h src/capture.h src/document.h src/packet.h src/usb.h src/bridge.h src/transport.h
	@mkdir -p build
	$(CC) $(CFLAGS) -arch arm64 -arch x86_64 -fobjc-arc $(MAC_SOURCES) $(FRAMEWORKS) -o $@

build/DS720DScanner-universal: macos/App.m macos/ServiceClient.m macos/ServiceClient.h macos/ServiceIdentity.h
	@mkdir -p build
	$(CC) $(CFLAGS) -Isrc -Imacos -arch arm64 -arch x86_64 -fobjc-arc macos/App.m macos/ServiceClient.m -framework AppKit -framework UniformTypeIdentifiers -framework Security -o $@

build/DS720DICA-universal: macos/ICADevice.m macos/ServiceClient.m macos/ServiceClient.h macos/ServiceIdentity.h src/raster.c src/raster.h src/document.c
	@mkdir -p build
	$(CC) $(CFLAGS) -Isrc -Imacos -arch arm64 -arch x86_64 -fobjc-arc macos/ICADevice.m macos/ServiceClient.m src/raster.c src/document.c -framework Foundation -framework ICADevices -framework ImageCaptureCore -framework ImageIO -framework CoreGraphics -framework IOKit -framework Security -o $@

build/DS720DUSBService-universal: macos/USBService.m macos/ServiceIdentity.h src/capture.m src/bridge.m src/usb.m src/packet.c
	@mkdir -p build
	$(CC) $(CFLAGS) -Isrc -Imacos -arch arm64 -arch x86_64 -fobjc-arc macos/USBService.m src/usb.m src/bridge.m src/capture.m src/packet.c -framework Foundation -framework IOKit -framework IOUSBHost -framework Security -o $@

.PHONY: app pkg dmg
app: build/ds720d-universal build/DS720DScanner-universal build/DS720DICA-universal build/DS720DUSBService-universal
	./packaging/macos/build-app.sh

pkg: app
	./packaging/macos/build-pkg.sh

dmg: pkg
	./packaging/macos/build-dmg.sh

clean:
	rm -rf build

build/packet_test: src/packet.c src/packet.h tests/packet_test.c
	@mkdir -p build
	$(CC) $(CFLAGS) -Isrc -fsanitize=address,undefined src/packet.c tests/packet_test.c -o $@

build/bridge_test: src/bridge.m src/bridge.h src/transport.h src/packet.c tests/bridge_test.m
	@mkdir -p build
	$(CC) $(CFLAGS) -Isrc -fobjc-arc -fsanitize=address,undefined src/bridge.m src/packet.c tests/bridge_test.m -framework Foundation -o $@

build/image_test: src/image.m src/capture.h src/packet.h src/document.c src/document.h tests/image_test.m
	@mkdir -p build
	$(CC) $(CFLAGS) -Isrc -fobjc-arc -fsanitize=address,undefined src/image.m src/document.c tests/image_test.m -framework Foundation -framework ImageIO -framework CoreGraphics -o $@

build/document_test: src/document.c src/document.h tests/document_test.c
	@mkdir -p build
	$(CC) $(CFLAGS) -Isrc -fsanitize=address,undefined src/document.c tests/document_test.c -o $@

build/raster_test: src/raster.c src/raster.h src/document.c src/packet.h tests/raster_test.c
	@mkdir -p build
	$(CC) $(CFLAGS) -Isrc -fsanitize=address,undefined src/raster.c src/document.c tests/raster_test.c -o $@

build/engine_test: src/engine.c src/engine.h src/packet.c tests/engine_test.c
	@mkdir -p build
	$(CC) $(CFLAGS) -Isrc -std=c11 -fsanitize=address,undefined src/engine.c src/packet.c tests/engine_test.c -o $@

build/ica_test: tests/ica_test.m macos/ICADevice.m src/raster.c src/document.c
	@mkdir -p build
	$(CC) $(CFLAGS) -Isrc -Imacos -fobjc-arc -fsanitize=address,undefined tests/ica_test.m src/raster.c src/document.c -framework Foundation -framework ICADevices -framework ImageCaptureCore -framework ImageIO -framework CoreGraphics -framework IOKit -o $@

test: build/packet_test build/bridge_test build/image_test build/document_test build/raster_test build/engine_test build/ica_test
	./build/packet_test
	./build/bridge_test
	./build/image_test
	./build/document_test
	./build/raster_test
	./build/engine_test
	./build/ica_test

analyze:
	$(CC) --analyze -fobjc-arc -mmacosx-version-min=14.0 src/main.m src/usb.m src/bridge.m src/packet.c src/authorize.m src/capture.m src/image.m src/document.c -Xanalyzer -analyzer-output=text -Xanalyzer -analyzer-werror
	$(CC) --analyze -fobjc-arc -mmacosx-version-min=14.0 -Isrc -Imacos macos/App.m macos/ICADevice.m macos/USBService.m macos/ServiceClient.m src/raster.c -Xanalyzer -analyzer-output=text -Xanalyzer -analyzer-werror

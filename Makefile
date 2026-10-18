CC = xcrun clang
CFLAGS = -Wall -Wextra -Werror -O2 -g -mmacosx-version-min=14.0
FRAMEWORKS = -framework Foundation -framework IOKit -framework IOUSBHost -framework Security -framework ImageIO -framework CoreGraphics

.PHONY: all clean test analyze
all: build/ds720d

build/ds720d: src/main.m src/usb.m src/usb.h src/packet.c src/packet.h src/bridge.m src/bridge.h src/transport.h src/authorize.m src/authorize.h src/capture.m src/capture.h src/image.m
	@mkdir -p build
	$(CC) $(CFLAGS) -fobjc-arc src/main.m src/usb.m src/packet.c src/bridge.m src/authorize.m src/capture.m src/image.m $(FRAMEWORKS) -o $@
	codesign --force --sign - $@

clean:
	rm -rf build

build/packet_test: src/packet.c src/packet.h tests/packet_test.c
	@mkdir -p build
	$(CC) $(CFLAGS) -Isrc -fsanitize=address,undefined src/packet.c tests/packet_test.c -o $@

build/bridge_test: src/bridge.m src/bridge.h src/transport.h src/packet.c tests/bridge_test.m
	@mkdir -p build
	$(CC) $(CFLAGS) -Isrc -fobjc-arc -fsanitize=address,undefined src/bridge.m src/packet.c tests/bridge_test.m -framework Foundation -o $@

build/image_test: src/image.m src/capture.h src/packet.h tests/image_test.m
	@mkdir -p build
	$(CC) $(CFLAGS) -Isrc -fobjc-arc -fsanitize=address,undefined src/image.m tests/image_test.m -framework Foundation -framework ImageIO -framework CoreGraphics -o $@

test: build/packet_test build/bridge_test build/image_test
	./build/packet_test
	./build/bridge_test
	./build/image_test

analyze:
	$(CC) --analyze -fobjc-arc -mmacosx-version-min=14.0 src/main.m src/usb.m src/bridge.m src/packet.c src/authorize.m src/capture.m src/image.m -Xanalyzer -analyzer-output=text -Xanalyzer -analyzer-werror

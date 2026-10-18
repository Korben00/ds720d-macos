#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Hardware-free regression check for BOT-shaped transfers over the real Tart channel.

Stop the physical USB/IP relay first: this test binds localhost:3240 but never
opens a USB device. No synthetic result is evidence of a physical scan.
"""
import argparse
import importlib.util
import json
import pathlib
import select
import shutil
import socket
import statistics
import subprocess
import sys
import threading
import time

COUNT = 128
SHAPES = ((79, 48), (48, 65584), (48, 61))  # USB/IP CBW, 64 KiB data, CSW


def exact(sock, count):
    result = bytearray()
    while len(result) < count:
        data = sock.recv(count - len(result))
        if not data:
            raise EOFError(f"short read: {len(result)} / {count}")
        result.extend(data)
    return result


def client():
    times = [[] for _ in SHAPES]
    with socket.create_connection(("127.0.0.1", 3240), timeout=10) as sock:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        start = time.perf_counter()
        for _ in range(COUNT):
            for index, (request, response) in enumerate(SHAPES):
                tick = time.perf_counter()
                sock.sendall(bytes(request))
                if any(exact(sock, response)):
                    raise ValueError("Synthetic response was corrupted")
                times[index].append((time.perf_counter() - tick) * 1000)
        elapsed = time.perf_counter() - start
    print(json.dumps({"cycles": COUNT, "seconds": elapsed,
        "mib_per_second": COUNT * 65536 / 1048576 / elapsed,
        "stages_ms": [{"median": statistics.median(t),
            "p95": sorted(t)[int(len(t) * .95)], "max": max(t)} for t in times]}))


def run(vm, tart, channel, nodelay):
    errors = []
    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 3240))
    listener.listen(1)
    listener.settimeout(15)

    def server():
        try:
            with listener:
                sock, _ = listener.accept()
                with sock:
                    sock.settimeout(15)
                    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                    for _ in range(COUNT):
                        for request, response in SHAPES:
                            exact(sock, request)
                            sock.sendall(bytes(response))
        except Exception as error:
            errors.append(error)

    server_thread = threading.Thread(target=server, daemon=True)
    server_thread.start()
    host, process = channel.connect(vm, tart, nodelay=nodelay, stderr=subprocess.PIPE)
    relay_thread = threading.Thread(target=channel.relay, args=(host, process), daemon=True)
    relay_thread.start()
    try:
        if not select.select([process.stderr], [], [], 15)[0]:
            raise TimeoutError("Guest endpoint did not become ready")
        ready = process.stderr.readline()
        if b"guest endpoint ready" not in ready:
            raise RuntimeError(ready.decode(errors="replace"))
        result = subprocess.run(
            [tart, "exec", "-i", vm, "python3", "-u", "-", "--client"],
            input=pathlib.Path(__file__).read_text(), text=True, capture_output=True,
            timeout=25, check=True,
        )
        return json.loads(result.stdout)
    finally:
        try:
            host.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        server_thread.join(5)
        relay_thread.join(5)
        if errors:
            raise errors[0]
        if server_thread.is_alive() or relay_thread.is_alive():
            raise RuntimeError("Benchmark channel failed to stop")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vm")
    parser.add_argument("--tart", default=shutil.which("tart"))
    parser.add_argument("--compare", action="store_true", help="Also reproduce the original Nagle delay")
    args = parser.parse_args()
    if not args.tart:
        parser.error("Tart executable not found")
    path = pathlib.Path(__file__).with_name("usbip-channel.py")
    spec = importlib.util.spec_from_file_location("channel", path)
    channel = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(channel)
    results = {}
    if args.compare:
        results["nagle_baseline"] = run(args.vm, args.tart, channel, False)
    results["corrected"] = run(args.vm, args.tart, channel, True)
    print(json.dumps(results, indent=2))
    if results["corrected"]["mib_per_second"] < 5:
        raise SystemExit("Transport below 5 MiB/s; investigate before scanning")


if __name__ == "__main__":
    if sys.argv[1:] == ["--client"]:
        client()
    else:
        main()

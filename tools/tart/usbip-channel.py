#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Carry one physical USB/IP attachment over Tart's private guest-agent channel."""
import argparse
import os
import shutil
import socket
import subprocess
import threading

# stdout is exclusively binary data. Diagnostic messages go to stderr.
GUEST = r'''
import os, socket, threading, sys
s=socket.socket()
s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(("127.0.0.1",3240))
s.listen(1)
print("Private USB/IP guest endpoint ready",file=sys.stderr,flush=True)
c,_=s.accept()
s.close()
if sys.argv[1] == "1":
    # Nagle + Linux delayed ACK otherwise stalls the tail of each 64 KiB block.
    c.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1)
def receive():
    try:
        while True:
            data=os.read(0,65536)
            if not data: break
            c.sendall(data)
    finally:
        try: c.shutdown(socket.SHUT_WR)
        except OSError: pass
threading.Thread(target=receive,daemon=True).start()
while True:
    data=c.recv(65536)
    if not data: break
    view=memoryview(data)
    while view:
        count=os.write(1,view)
        view=view[count:]
c.close()
'''


def connect(vm, tart, *, nodelay=True, stderr=None):
    """Return a running channel. nodelay=False is for the synthetic benchmark only."""
    host = socket.create_connection(("127.0.0.1", 3240))
    if nodelay:
        host.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    try:
        process = subprocess.Popen(
            [tart, "exec", "-i", vm, "python3", "-u", "-c", GUEST, "1" if nodelay else "0"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr, bufsize=0,
        )
    except BaseException:
        host.close()
        raise
    return host, process


def relay(host, process):
    def to_guest():
        try:
            while data := host.recv(65536):
                view = memoryview(data)
                while view:
                    count = os.write(process.stdin.fileno(), view)
                    view = view[count:]
        except (OSError, ValueError):
            pass  # Detaching the USB device closes the stream.
        finally:
            process.stdin.close()

    threading.Thread(target=to_guest, daemon=True).start()
    try:
        while data := os.read(process.stdout.fileno(), 65536):
            host.sendall(data)
    finally:
        try:
            host.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        host.close()
        if process.poll() is None:
            process.terminate()
        process.wait(timeout=10)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vm", help="Name of the running dedicated Tart Linux VM")
    parser.add_argument("--tart", default=shutil.which("tart"), help="Tart 2.41.1+ executable")
    args = parser.parse_args()
    if not args.tart:
        parser.error("Tart executable not found; use --tart /absolute/path/to/tart")
    relay(*connect(args.vm, args.tart))


if __name__ == "__main__":
    main()

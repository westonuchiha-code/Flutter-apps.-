#!/usr/bin/env python3
"""The way out of CRT TV that depends on nothing else working.

Run by the launcher next to the program: crt_tv_escape.py <program's pid>

It listens to every input device directly (not through the program, and not
through Batocera's hotkey service). Hold SELECT + START, or the HOME/GUIDE
button + START, on any controller for three seconds and the program is
closed, returning to the Batocera menu. It stops by itself when the program
does. Everything it notices is printed, which the launcher keeps in its log.
"""
import os
import select
import signal
import struct
import sys
import time

EVENT = struct.Struct('llHHi')  # struct input_event on 64-bit Linux
EV_KEY = 1
START = 315
# Buttons that, held together with START, mean "get me out".
WITH_START = {314: 'SELECT', 316: 'HOME'}
# Plain USB pads that only number their buttons: 9 and 10 are SELECT, START.
GENERIC_PAIR = (296, 297)
HOLD_SECONDS = 3.0
INPUT_DIR = os.environ.get('CRT_TV_INPUT_DIR', '/dev/input')


def say(message):
    print('escape: ' + message, flush=True)


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def device_name(path):
    try:
        with open('/sys/class/input/%s/device/name' % os.path.basename(path)) as f:
            return f.read().strip()
    except OSError:
        return os.path.basename(path)


class Device:
    def __init__(self, path, fd):
        self.path = path
        self.fd = fd
        self.name = device_name(path)
        self.down = set()
        self.pending = b''
        self.heard = False
        self.since = None

    def feed(self, data):
        data = self.pending + data
        whole = len(data) - len(data) % EVENT.size
        self.pending = data[whole:]
        for offset in range(0, whole, EVENT.size):
            _, _, kind, code, value = EVENT.unpack_from(data, offset)
            if kind != EV_KEY:
                continue
            if value:
                self.down.add(code)
                if not self.heard and code >= 256:
                    self.heard = True
                    say('first button from "%s": code %d' % (self.name, code))
            else:
                self.down.discard(code)

    def combo(self):
        if START in self.down:
            for code, label in WITH_START.items():
                if code in self.down:
                    return label + ' + START'
        if all(code in self.down for code in GENERIC_PAIR):
            return 'buttons 9 + 10'
        return None


def scan(devices):
    try:
        names = sorted(os.listdir(INPUT_DIR))
    except OSError:
        return
    for name in names:
        path = os.path.join(INPUT_DIR, name)
        if not name.startswith('event') or path in devices:
            continue
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError as error:
            devices[path] = None  # don't keep retrying or re-reporting it
            say('cannot open %s: %s' % (path, error.strerror))
            continue
        devices[path] = Device(path, fd)
        say('listening to %s "%s"' % (path, devices[path].name))


def main():
    pid = int(sys.argv[1])
    devices = {}
    last_scan = 0.0
    say('watching for SELECT + START (or HOME + START) held %d seconds' % HOLD_SECONDS)
    while alive(pid):
        now = time.monotonic()
        if now - last_scan >= 2.0:
            last_scan = now
            scan(devices)
        open_devices = [d for d in devices.values() if d is not None]
        by_fd = {d.fd: d for d in open_devices}
        try:
            ready, _, _ = select.select(list(by_fd), [], [], 0.25)
        except (OSError, ValueError):
            ready = []
        for fd in ready:
            device = by_fd[fd]
            try:
                data = os.read(fd, EVENT.size * 64)
            except BlockingIOError:
                continue
            except OSError:
                data = b''
            if not data:
                # Unplugged. Forget it so that it is picked up again later.
                say('lost %s "%s"' % (device.path, device.name))
                os.close(fd)
                del devices[device.path]
                continue
            device.feed(data)
        now = time.monotonic()
        for device in open_devices:
            combo = device.combo()
            if combo is None:
                device.since = None
                continue
            if device.since is None:
                device.since = now
            elif now - device.since >= HOLD_SECONDS:
                say('%s held on "%s": closing CRT TV' % (combo, device.name))
                try:
                    os.kill(pid, signal.SIGTERM)
                    for _ in range(20):
                        if not alive(pid):
                            break
                        time.sleep(0.1)
                    if alive(pid):
                        os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                return


if __name__ == '__main__':
    main()

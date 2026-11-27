#!/usr/bin/env python3
"""Collects the libraries CRT TV needs that a Batocera system doesn't have.

Batocera ships the mpv program but not libmpv, which the app is built on.
Starting from this machine's libmpv.so.2, this walks everything it depends
on. A library Batocera already has (by name, in a standard folder) is left
to Batocera; one it lacks is copied into the bundle, and then *its* needs
are followed the same way.

Usage: bundle_libs.py <batocera-system-libs.txt> <output folder>
"""
import os
import re
import shutil
import subprocess
import sys

STANDARD = ('/usr/lib/', '/usr/lib64/', '/lib/', '/lib64/')
START = ['libmpv.so.2']

# Replaced by a small stand-in built from rabbitmq_stub.c. Ubuntu's copy
# needs OpenSSL's ENGINE functions, which Batocera's OpenSSL is built
# without, so the whole program failed to load. It is only there because
# FFmpeg can speak a network protocol this app never uses.
STUBBED = {'librabbitmq.so.4'}

# The C and C++ runtime always comes from the system it runs on, whatever a
# list of that system says. A second copy beside the app means a loader and
# a C library that don't match each other: instant crashes.
NEVER = re.compile(
    r'^(ld-linux.*|libc|libm|libdl|libpthread|librt|libresolv|libutil|libanl|libnsl|libcrypt'
    r'|libnss_.*|libgcc_s|libstdc\+\+|libatomic|libgomp)\.so(\.|$)'
)


def batocera_has(list_file):
    names = set()
    for line in open(list_file, encoding='utf-8', errors='replace'):
        path = line.strip()
        folder, _, name = path.rpartition('/')
        # Only what the loader finds by default; not plugin sub-folders.
        if name and (folder + '/') in STANDARD:
            names.add(name)
    return names


def local_libs():
    found = {}
    out = subprocess.run(['ldconfig', '-p'], capture_output=True, text=True).stdout
    for line in out.splitlines():
        m = re.match(r'\s+(\S+) \(libc6,x86-64[^)]*\) => (\S+)', line)
        if m and m.group(1) not in found:
            found[m.group(1)] = m.group(2)
    return found


def needed(path):
    out = subprocess.run(['objdump', '-p', path], capture_output=True, text=True).stdout
    return re.findall(r'NEEDED\s+(\S+)', out)


def versions(path, prefix):
    out = subprocess.run(['objdump', '-T', path], capture_output=True, text=True).stdout
    return set(re.findall(prefix + r'_([0-9.]+)', out))


def newest(found):
    return max(found, key=lambda v: [int(p) for p in v.split('.')]) if found else None


def main():
    system = batocera_has(sys.argv[1])
    out_dir = sys.argv[2]
    here = local_libs()
    os.makedirs(out_dir, exist_ok=True)

    bundled, from_system, unresolved = {}, set(), set()
    queue = list(START)
    while queue:
        name = queue.pop()
        if name in bundled or name in from_system or name in unresolved:
            continue
        if name in STUBBED:
            continue
        if NEVER.match(name) or (name not in START and name in system):
            from_system.add(name)
            continue
        if name not in here:
            unresolved.add(name)
            continue
        bundled[name] = os.path.realpath(here[name])
        queue.extend(needed(bundled[name]))

    for name, path in sorted(bundled.items()):
        shutil.copy2(path, os.path.join(out_dir, name))
        os.chmod(os.path.join(out_dir, name), 0o755)

    glibc, cxx = set(), set()
    for path in bundled.values():
        glibc |= versions(path, 'GLIBC')
        cxx |= versions(path, 'GLIBCXX')
    size = sum(os.path.getsize(p) for p in bundled.values())
    print(f'bundled: {len(bundled)} libraries, {size / 1e6:.0f} MB')
    print(f'left to Batocera: {len(from_system)} libraries')
    print(f'needs glibc >= {newest(glibc)}, libstdc++ symbols up to GLIBCXX_{newest(cxx)}')
    if unresolved:
        print('UNRESOLVED (on neither system): ' + ', '.join(sorted(unresolved)))
    with open(os.path.join(out_dir, 'BUNDLED.txt'), 'w') as f:
        f.write('Libraries bundled for Batocera, copied from Ubuntu 24.04.\n')
        f.write('Batocera has no libmpv; these are libmpv and what it needs that Batocera lacks.\n\n')
        for name in sorted(bundled):
            f.write(name + '\n')
        f.write('\nExpected from the Batocera system:\n')
        for name in sorted(from_system):
            f.write(name + '\n')
    biggest = sorted(bundled.items(), key=lambda kv: -os.path.getsize(kv[1]))[:8]
    print('largest: ' + ', '.join(f'{n} {os.path.getsize(p) / 1e6:.0f}MB' for n, p in biggest))
    return 1 if unresolved else 0


if __name__ == '__main__':
    sys.exit(main())

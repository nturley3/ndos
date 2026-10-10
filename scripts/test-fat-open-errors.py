#!/usr/bin/env python3
"""Run real DOS file-open regression checks in an installed nDOS simulator app.

Usage: python3 scripts/test-fat-open-errors.py SIMULATOR_UDID
Requires a booted simulator with io.turley.ndos installed. Generates its own
floppy and DOS test program; no Windows installation files are required.
"""

import os
from pathlib import Path
import platform
import struct
import subprocess
import sys
import tempfile


def guest_program():
    # Assemble a tiny .COM program that exercises INT 21h, AH=3Dh (open).
    code = bytearray()
    labels = {}
    fixups = []

    def emit(*values):
        code.extend(values)

    def address(opcode, label):
        emit(opcode)
        fixups.append((len(code), label, False))
        emit(0, 0)

    def jump(opcode, label):
        emit(opcode)
        fixups.append((len(code), label, True))
        emit(0)

    for name, expected_error in (("missing", 2), ("missing_parent", 3),
                                 ("existing", None)):
        address(0xBA, name)  # mov dx, filename
        emit(0xB8, 0, 0x3D, 0xCD, 0x21)  # mov ax,3D00h; int 21h
        if expected_error is not None:
            jump(0x73, "fail")  # jnc fail
            emit(0x3D, expected_error, 0)  # cmp ax, expected_error
            jump(0x75, "fail")  # jne fail
        else:
            jump(0x72, "fail")  # jc fail
            emit(0x89, 0xC3, 0xB4, 0x3E, 0xCD, 0x21)  # close handle
            jump(0x72, "fail")

    address(0xBA, "pass_message")
    emit(0xB4, 9, 0xCD, 0x21, 0xB8, 0, 0x4C, 0xCD, 0x21)
    labels["fail"] = len(code)
    address(0xBA, "fail_message")
    emit(0xB4, 9, 0xCD, 0x21, 0xB8, 1, 0x4C, 0xCD, 0x21)
    for name, value in (
        ("missing", b"A:\\ABSENT.TXT\0"),
        ("missing_parent", b"A:\\ABSENT\\FILE.TXT\0"),
        ("existing", b"A:\\PRESENT.TXT\0"),
        ("pass_message", b"FAT_OPEN_REGRESSION_PASS\r\n$"),
        ("fail_message", b"FAT_OPEN_REGRESSION_FAIL\r\n$"),
    ):
        labels[name] = len(code)
        code.extend(value)
    for offset, name, relative in fixups:
        if relative:
            distance = labels[name] - offset - 1
            assert -128 <= distance <= 127
            code[offset] = distance & 255
        else:
            struct.pack_into("<H", code, offset, 0x100 + labels[name])
    return code


def floppy_image():
    image = bytearray(1474560)
    image[:11] = b"\xeb\x3c\x90MSDOS5.0"
    struct.pack_into("<HBHBHHBHHHII", image, 11,
                     512, 1, 1, 2, 224, 2880, 0xF0, 9, 18, 2, 0, 0)
    image[510:512] = b"\x55\xaa"
    for offset in (512, 5120):
        image[offset:offset + 5] = b"\xf0\xff\xff\xff\x0f"
    root = 19 * 512
    image[root:root + 11] = b"PRESENT TXT"
    image[root + 11] = 0x20
    struct.pack_into("<H", image, root + 26, 2)
    struct.pack_into("<I", image, root + 28, 1)
    image[33 * 512] = ord("x")
    return image


PROBE = r'''
#import <Foundation/Foundation.h>
#include <dlfcn.h>
@interface NSObject (FatOpenProbe)
+ (id)sharedInstance;
- (BOOL)canMountImage;
- (void)sendCommand:(NSString *)command;
@end
static void checkScreen(int tries) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        auto readByte = (unsigned char (*)(unsigned int))dlsym(RTLD_DEFAULT, "_Z9mem_readbj");
        if (!readByte) { NSLog(@"FAT_TEST_HARNESS_ERROR: no memory reader"); exit(1); }
        char screen[2001];
        for (int i=0; i<2000; ++i) { char c=readByte(0xb8000+2*i); screen[i]=c?c:' '; }
        screen[2000]=0;
        if (strstr(screen, "FAT_OPEN_REGRESSION_FAIL")) { NSLog(@"FAT_TEST_RESULT_FAIL"); exit(1); }
        if (strstr(screen, "FAT_OPEN_REGRESSION_PASS")) { NSLog(@"FAT_TEST_RESULT_PASS"); exit(0); }
        if (tries >= 30) { NSLog(@"FAT_TEST_HARNESS_ERROR: guest timeout"); exit(1); }
        checkScreen(tries+1);
    });
}
static void runWhenReady(int tries) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        id emulator=[NSClassFromString(@"DOSPadEmulator") sharedInstance];
        if (![emulator canMountImage]) {
            if (tries>=30) { NSLog(@"FAT_TEST_HARNESS_ERROR: no DOS prompt"); exit(1); }
            runWhenReady(tries+1); return;
        }
        NSString *path=NSProcessInfo.processInfo.environment[@"FAT_TEST_DIRECTORY"];
        NSString *command=[NSString stringWithFormat:@"mount -u a\nmount -u q\nmount q \"%@\"\nimgmount a \"%@/fixture.ima\" -t floppy\nq:\nfatcheck\n",path,path];
        [emulator sendCommand:command];
        checkScreen(0);
    });
}
__attribute__((constructor)) static void startProbe() { runWhenReady(0); }
'''


def main(device):
    def simctl(*args, **kwargs):
        return subprocess.run(["xcrun", "simctl", *args], **kwargs)

    container = simctl("get_app_container", device, "io.turley.ndos", "data",
                      check=True, capture_output=True, text=True).stdout.strip()
    with tempfile.TemporaryDirectory(prefix="ndos-fat-test-") as build_dir, \
            tempfile.TemporaryDirectory(prefix="fat-test-", dir=Path(container) / "Documents") as fixture_dir:
        build = Path(build_dir)
        fixture = Path(fixture_dir)
        (fixture / "fixture.ima").write_bytes(floppy_image())
        (fixture / "FATCHECK.COM").write_bytes(guest_program())
        (build / "probe.mm").write_text(PROBE)
        subprocess.run(["xcrun", "--sdk", "iphonesimulator", "clang++", "-arch",
                        platform.machine(), "-mios-simulator-version-min=18.0",
                        "-fobjc-arc", "-fblocks", "-dynamiclib", "-framework", "Foundation",
                        str(build / "probe.mm"), "-o", str(build / "probe.dylib")], check=True)
        env = dict(os.environ,
                   SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=str(build / "probe.dylib"),
                   SIMCTL_CHILD_FAT_TEST_DIRECTORY=fixture_dir)
        try:
            result = simctl("launch", "--terminate-running-process", "--console-pty",
                            device, "io.turley.ndos", env=env, capture_output=True,
                            text=True, timeout=70)
            output = result.stdout + result.stderr
            for line in output.splitlines():
                if "FAT_TEST_" in line:
                    print(line)
            if "FAT_TEST_RESULT_PASS" not in output:
                raise RuntimeError("FAT file-open regression failed\n" + output[-2500:])
        finally:
            simctl("terminate", device, "io.turley.ndos", capture_output=True)
            simctl("launch", device, "io.turley.ndos", check=True, capture_output=True)
    print("Missing file=2, missing parent=3, existing file opens: passed")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])

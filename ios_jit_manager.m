// Copyright 2025 Flycast Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "ios_jit_manager.h"

#if TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR

#include <unistd.h>
#include <sys/types.h>
#include <sys/utsname.h>
#include <math.h>
#include <string.h>
#include <stdio.h>

#define CS_OPS_STATUS 0
#define CS_DEBUGGED 0x10000000

// Properly declare csops for both C and C++
#ifdef __cplusplus
extern "C" {
#endif

int csops(pid_t pid, unsigned int ops, void* useraddr, size_t usersize);

#ifdef __cplusplus
}
#endif

// Port of StosDebug's ProcessInfo.detectedTXM (TXM_Checks.swift).
// Uses the hardware model, so it needs no filesystem access and works in a sandbox / LiveContainer.
static bool ios_hardware_has_txm(void) {
    struct utsname systemInfo;
    if (uname(&systemInfo) != 0) {
        return false;
    }
    const char* hw = systemInfo.machine;

    // iOS 27+: every device except these two iPads has TXM
    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){27, 0, 0}]) {
        return strcmp(hw, "iPad8,11") != 0 && strcmp(hw, "iPad8,12") != 0;
    }

    // iOS 26: decide by hardware generation
    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){26, 0, 0}]) {
        bool isPad = strncmp(hw, "iPad", 4) == 0;
        bool isPhone = strncmp(hw, "iPhone", 6) == 0;
        if (!isPad && !isPhone) {
            return false;
        }

        int major = 0, minor = 0;
        if (sscanf(hw + (isPad ? 4 : 6), "%d,%d", &major, &minor) != 2) {
            return false;
        }

        // Same math as StosDebug: major + minor / 10^(digits in minor)
        int digits = 1;
        for (int m = minor; m >= 10; m /= 10) digits++;
        double version = major + (double)minor / pow(10.0, digits);

        return isPad ? (version >= 14.5) : (version >= 14.2);
    }

    return false;
}

// ---- TXM detection, modelled on MeloCafe (stossy11/MeloCafe, CemuManager.swift) ----

// Firmware probe: the TXM image is present in the Preboot volume on TXM devices
static bool ios_txm_firmware_present(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    static NSString *const img = @"usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4";

    // returns the first entry of dir whose name has the given length
    NSString *(^entryWithLength)(NSString *, NSUInteger) = ^NSString *(NSString *dir, NSUInteger length) {
        NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *e in entries)
            if (e.length == length)
                return [dir stringByAppendingPathComponent:e];
        return nil;
    };

    NSString *boot = entryWithLength(@"/System/Volumes/Preboot", 36);
    if (boot != nil) {
        NSString *file = entryWithLength([boot stringByAppendingPathComponent:@"boot"], 96);
        if (file != nil)
            return access([[file stringByAppendingPathComponent:img] fileSystemRepresentation], F_OK) == 0;
    }
    NSString *file = entryWithLength(@"/private/preboot", 96);
    if (file != nil)
        return access([[file stringByAppendingPathComponent:img] fileSystemRepresentation], F_OK) == 0;
    return false;
}

// Chip name from the Metal device name ("Apple A15 GPU", "Apple M2 GPU"). Returns false if unknown.
static bool ios_chip_info(char *letter, int *number) {
    bool ok = false;
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device != nil) {
            const char *name = [[device.name uppercaseString] UTF8String];
            const char *p = name != NULL ? strstr(name, "APPLE ") : NULL;
            char l = 0;
            int n = 0;
            if (p != NULL && sscanf(p, "APPLE %c%d", &l, &n) == 2 && (l == 'A' || l == 'M')) {
                *letter = l;
                *number = n;
                ok = true;
            }
#if !__has_feature(objc_arc)
            [device release];
#endif
        }
    }
    return ok;
}

static char s_txmInfo[256] = "not evaluated";

const char *ios_txm_detection_info(void) {
    return s_txmInfo;
}

static bool ios_detect_txm(void) {
    NSProcessInfo *pi = [NSProcessInfo processInfo];
    char letter = 0;
    int number = 0;
    bool haveChip = ios_chip_info(&letter, &number);
    bool firmware = ios_txm_firmware_present();
    struct utsname u;
    uname(&u);
    bool model = ios_hardware_has_txm();
    bool result;
    const char *why;

    if ([pi isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){27, 0, 0}]) {
        // iOS 27+: everything newer than the A12 has TXM
        result = (haveChip && letter == 'A') ? number > 12 : true;
        why = "iOS 27+: chip rule";
    } else if (firmware) {
        result = true;
        why = "TrustedExecutionMonitor firmware found in Preboot";
    } else if ([pi isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){26, 6, 0}] && haveChip) {
        // iOS 26.6+: firmware probe can fail; fall back to the chip generation
        result = (letter == 'M') ? number >= 2 : number >= 15;
        why = "iOS 26.6+: chip rule (firmware not found)";
    } else if (!haveChip && [pi isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){26, 0, 0}]) {
        // Metal unavailable: model identifier heuristic (StosDebug)
        result = model;
        why = "model identifier rule (no Metal chip name, firmware not found)";
    } else {
        result = false;
        why = "firmware not found";
    }
    snprintf(s_txmInfo, sizeof(s_txmInfo), "model=%s chip=%c%d(valid=%d) firmware=%d modelRule=%d osAtLeast26=%d -> %s (%s)",
            u.machine, haveChip ? letter : '?', number, (int)haveChip, (int)firmware, (int)model,
            (int)[pi isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){26, 0, 0}], result ? "TXM" : "no TXM", why);
    return result;
}

bool ios_device_has_txm(void) {
    // Optional manual override, same idea as StosDebug's "forceTXM"
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"forceTXM"]) {
        snprintf(s_txmInfo, sizeof(s_txmInfo), "forceTXM user default set");
        return true;
    }
    static bool done = false;
    static bool result = false;
    if (!done) {
        result = ios_detect_txm();
        done = true;
    }
    return result;
}

#if defined(__aarch64__)
// Plain naked functions (no compiler involvement between the register setup and the brk): the universal.js
// script reads x16 (command), x0/x1 (arguments) when it stops on the brk, advances the pc past it, and for
// the prepare command writes the region address back into x0.
__attribute__((noinline, optnone, naked))
void *ios_txm_prepare_region(void *addr, size_t len) {
    __asm__ volatile("mov x16, #1\n"
                     "brk #0xf00d\n"
                     "ret");
}

__attribute__((noinline, optnone, naked))
void ios_txm_detach(void) {
    __asm__ volatile("mov x16, #0\n"
                     "brk #0xf00d\n"
                     "ret");
}
#else
void *ios_txm_prepare_region(void *addr, size_t len) { return NULL; }
void ios_txm_detach(void) {}
#endif

bool ios_process_is_debugged(void) {
    int flags;
    if (csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) != 0) {
        return false;
    }
    return (flags & CS_DEBUGGED) != 0;
}

bool ios_can_use_txm_jit(void) {
    static bool checked = false;
    static bool result = false;
    
    if (!checked) {
        checked = true;
        
        bool has_txm = ios_device_has_txm();
        bool is_debugged = ios_process_is_debugged();
        
        if (has_txm && !is_debugged) {
            NSLog(@"[Flycast] WARNING: TXM device detected but no debugger attached.");
            NSLog(@"[Flycast] JIT compilation will not work. Please attach StikDebug to enable JIT.");
            result = false;
        } else if (has_txm && is_debugged) {
            // Check if running under Xcode (which won't work with TXM)
            NSDictionary* environment = [[NSProcessInfo processInfo] environment];
            if ([environment objectForKey:@"XCODE"] != nil) {
                NSLog(@"[Flycast] ERROR: TXM device detected but running under Xcode.");
                NSLog(@"[Flycast] Xcode debugging is not compatible with TXM JIT.");
                NSLog(@"[Flycast] Please use StikDebug instead.");
                result = false;
            } else {
                NSLog(@"[Flycast] TXM device detected with debugger attached.");
                NSLog(@"[Flycast] Enabling TXM JIT mode with dual-mapped memory pool.");
                result = true;
            }
        } else {
            NSLog(@"[Flycast] Non-TXM device or iOS < 26. Using standard MAP_JIT mode.");
            result = false;
        }
    }
    
    return result;
}

#endif // TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR

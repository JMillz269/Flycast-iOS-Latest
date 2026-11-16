// Copyright 2025 Flycast Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#ifdef __APPLE__
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns true if device has TXM (iOS 26+ with TXM firmware)
bool ios_device_has_txm(void);

// Human readable explanation of how ios_device_has_txm() decided (for logs)
const char *ios_txm_detection_info(void);

// universal.js (StikDebug) protocol, "brk #0xf00d", command in x16.
// Prepare a JIT region: when addr is NULL the debugger allocates the RX region itself and returns its address
// (NULL on failure). When addr is not NULL it prepares that existing mapping.
void *ios_txm_prepare_region(void *addr, size_t len);
// Detach the debugger (command 0)
void ios_txm_detach(void);

// Returns true if process is being debugged
bool ios_process_is_debugged(void);

// Returns true if TXM is present AND debugger is attached (StikDebug)
// This is the function to call to determine if TXM JIT mode should be used
bool ios_can_use_txm_jit(void);

#ifdef __cplusplus
}
#endif

#endif // TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#endif // __APPLE__

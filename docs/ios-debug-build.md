# iOS debug / diagnostics build

Built by the **iOS Debug IPA (diagnostics)** workflow (`.github/workflows/build-ios-debug.yml`, artifact `Flycast-iOS-Debug`).
It is `CMAKE_BUILD_TYPE=Debug` with `-DENABLE_LOG=ON -DFLYCAST_DIAG=ON`, optimization level 1, symbols kept.

## What it does differently

* Full logging (all levels, all categories), **always written to a file**, no settings change needed.
* `NOTICE` "step" lines through the whole Vulkan start-up (`VulkanContext::InitInstance/InitDevice/CreateSwapChain`,
  `VulkanRenderer::Init`, `ScreenDrawer::Init`, attachments, render passes, pipelines, shader compiles, VMA allocations),
  plus a dump of the GPU: limits, memory heaps/types, features, formats, extensions.
  The last step line in the log is where a crash happened.
* A crash handler (`SIGSEGV/SIGBUS/SIGILL/SIGABRT/SIGTRAP/SIGFPE`, `std::terminate`, uncaught `NSException`) writes
  the signal, fault address, registers, the last step reached and a backtrace to `flycast-crash.txt`.
* MoltenVK logging is raised to debug level and **every Vulkan call is traced** (`MVK_CONFIG_TRACE_VULKAN_CALLS`).
  Its output (stderr) is copied to `mvk-stderr.log` (and still goes to the normal stderr / LiveContainer log).

## Files to collect

All are in the app's `Documents` folder (with LiveContainer: the container's Documents, reachable via the Files app
or LiveContainer's file browser):

| File | Content |
| --- | --- |
| `flycast.log` | Full Flycast log of the last run (`flycast.prev.log` = the run before) |
| `flycast-crash.txt` | Crash report, only exists if the app crashed (`.prev.txt` = previous run) |
| `mvk-stderr.log` | MoltenVK's own log, including the Vulkan call trace |

Please ask for **all three**, from a single launch that crashes. The call trace makes `mvk-stderr.log` large; zip it.

## Reading a crash report

`Last breadcrumb` is the last diagnostic step reached. The backtrace shows image-relative symbolication data
(`Image[0] slide`); with the `Flycast-Debug.dSYM.zip` from the same workflow run the addresses can be symbolicated with
`atos -o Flycast.app.dSYM/Contents/Resources/DWARF/Flycast -l <load address> <addr>`.

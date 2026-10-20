# Flycast

[![iOS Release IPA](https://github.com/JMillz269/Flycast-iOS-Latest/actions/workflows/build-ios.yml/badge.svg)](https://github.com/JMillz269/Flycast-iOS-Latest/actions/workflows/build-ios.yml)

<img src="shell/linux/flycast.png" alt="flycast logo" width="150"/>

**Flycast** is a multi-platform Sega Dreamcast, Naomi, Naomi 2, and Atomiswave emulator derived from [**reicast**](https://github.com/skmp/reicast-emulator).
<br>
<br>
### iOS

This fork only supports iOS. This fork is maintained by myself and myself only. This project was forked from the original Flycast repository and updated for iOS . This should support from iOS 9 - iOS 27. DO NOT POST BUG REPORTS/ISSUES/REQUESTS/ETC FOR THIS FORK TO THE ORIGINAL FLYCAST DEVELOPER. EVER. THIS FORK IS NOT SUPPORTED BY THEM. THEY DO NOT SUPPORT iOS.
<br>
<br>
<br>
ROM files go in Files, Documents, ROMS <br>
BIOS files go in Files, Documents, BIOS
<br>
<br>
<ul><li>Supports LiveContainer and direct install environments</li>
<li>On-screen controller will automatically hide when an MFI controller is used</li>
<li>Supports Universal.js for JIT using StikDebug/StosDebug for TXM capable iOS/iPadOS devices</li>
<li>non-TXM devices should be able to activate JIT as they normally would</li>
<li>Retroarch Achievement support (Retroarch Achievements will display on-screen underneath the on-screen controller overlay)</li>
<li>App allocates 64MB for JIT so it always falls within an allowed address range. App core should only use ~16MB anyway. We don't need much.</li>
<li>Fixed OpenMP iOS support. Can max out resolution settings on my iPhone 16 Pro Max at full speed</li>
<li>Fixed DSP and VMU sounds. In Audio settings, Enable DSP/Enable VMU Sounds no longer crashes the app when a game is launched</li>
<li>Retains all support for Dreamcast, Naomi, Naomi 2, and Atomiswave</ul></li>
<br>
<br>
<br>
<img width="2868" height="1320" alt="Image (1)" src="https://github.com/user-attachments/assets/e79cbe39-98f6-4c4c-88b4-e12e47d58e52" />
<br>
<br>
<img width="2868" height="1320" alt="Image" src="https://github.com/user-attachments/assets/e434d1bf-ccfc-4a37-8401-3497e5024f21" />




#### Build

```
$ git clone --recursive https://github.com/JMillz269/Flycast-iOS-Latest.git
$ cd Flycast-iOS-Latest
$ mkdir build && cd build
$ cmake ..
$ make
```

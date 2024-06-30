---
title: "Update LineageOS from 16.0 to 17.1 on the OnePlus 6T (fajita)"
date: 2020-05-10T17:46:06+02:00
draft: false
tags: android
---

Updating from 16.0 to 17.1 on A/B devices without data loss can be tricky, especially with the OnePlus 6T...

Here are my upgrade notes.
<!--more-->

First, ADB and fastboot should be functional [android-tools](https://www.archlinux.org/packages/community/x86_64/android-tools/))

An up-to-date Oxygen OS has to be sideloaded on both slots (a/b), this will bring updated firmwares and also, the compatibility with LineageOS 17.1.
The easiest solution is to sideload the Oxygen OS zip on one slot, and then sideload `copy-partitions.zip` in order to copy Oxygen OS to the other slot.

Then, we can sideload LineageOS 17.1 and Open Gapps (arm64), you can download the arm64 / nano package on [opengapps.org](https://opengapps.org/)

You will need:

* [an up-to-date Oxygen OS build](https://www.oneplus.com/fr/support/softwareupgrade/details?code=PM1574156215016)
* [an up-to-date LineageOS build](https://download.lineageos.org/fajita)
* [the file copy-partitions.zip](https://androidfilehost.com/?fid=4349826312261712574)

Because of compatibility issues, we need to use [unofficial recovery builds of twrp](https://forum.xda-developers.com/oneplus-6t/development/recovery-unofficial-twrp-touch-recovery-t3861482):

* [TWRP 3.3.1-32 Pie Unofficial by mauronofrio](https://sourceforge.net/projects/mauronofrio-twrp/files/Fajita/twrp-3.3.1-32-fajita-Pie-mauronofrio.img/download)
* [TWRP 3.3.1-32 Q Unofficial by mauronofrio](https://sourceforge.net/projects/mauronofrio-twrp/files/Fajita/twrp-3.3.1-32-fajita-Q-mauronofrio.img/download)


Downloads all these files, and start this procedure:

```bash
adb reboot bootloader
fastboot boot twrp-3.3.1-32-fajita-Pie-mauronofrio.img
adb shell twrp sideload
adb sideload OnePlus6TOxygen_34_OTA_044_all_2002220041_110bb9052a994b6f.zip
adb reboot bootloader
fastboot boot twrp-3.3.1-32-fajita-Q-mauronofrio.img
adb shell twrp sideload
adb sideload copy-partitions.zip
adb shell twrp sideload
adb sideload lineage-17.1-20200412-nightly-fajita-signed.zip
adb reboot bootloader
fastboot boot twrp-3.3.1-32-fajita-Q-mauronofrio.img
adb shell twrp sideload
adb sideload open_gapps-arm64-10.0-nano-20200412.zip
adb reboot
```

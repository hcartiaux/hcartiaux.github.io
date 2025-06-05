---
title: "My Archlinux installation notes"
date: 2025-05-13
draft: false
tags: [archlinux, linux, laptop, uefi, secureboot, tpm2, btrfs]
toc: true
---

I've just received my new `Dell Pro Max 14 MC14250`, and this is my installation notes for a modern Arch Linux installation, to support Secure Boot, Unified Kernel Images, `systemd-boot`, `btrfs` with `snapper` for snapshotting, and finalize the installation using `aconfmgr`, a simple configuration management system. The instructions are not detailed, the explanations are in the external resources listed at the end.

<!--more-->

## UEFI personal configuration

* Advanced Setup: on
* Boot Configuration: remove everything unneeded from the boot sequence
* Secure boot in audit mode (will be reverted after the installation)
* Enable SMART Reporting
* Connection: disable PXE, disable UEFI network and Bluetooth stack
* Power: type-C Connector Power - 15W
* Security: enable chassis intrusion, disable "Absolute"
* Passwords: set an admin password (necessary to boot to an external device or enter BIOS setup), disallow non-admin password changes
* Disable "SupportAssist Recovery"
* System Management: disable "OS Agent Requests"
* Keyboard: enable "Fn Lock Mode", choose "Lock Mode Standard"
* Virtualization: enable Intel TXT


## Base installation from the live system

Create an installation media:
* [follow the doc](https://wiki.archlinux.org/title/USB_flash_installation_medium)
* download the ISO
* verify the signature
* transfer it on a USB key using dd
* boot it (F12 for the UEFI boot menu)

### Keymap

```
loadkeys fr
```

### Network

I need a wifi network connection during installation time

```
iwctl
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "<ESSID>"
```


### Partition the local disk

Use cfdisk (`cfdisk /dev/nvme0n1p1`), create two partitions:

* `/dev/nvme0n1p1` - EFI partition, 4GB, we need space to store Unified Kernel Images and firmware update files.
* `/dev/nvme0n1p2` - Encrypted system partition, remaining space

### Format the partitions

Format the EFI partition:

```
mkfs.fat -F 32 /dev/nvme0n1p1
```

Encrypt and format the second partition

```
cryptsetup luksFormat /dev/nvme0n1p2
cryptsetup open /dev/nvme0n1p2 cryptroot
mkfs.btrfs /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt
```

### Mount all partitions

```
mount -o compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/home
mount -o compress=zstd,subvol=@home /dev/mapper/cryptroot /mnt/home
mkdir -p /mnt/efi
mount /dev/nvme0n1p1 /mnt/efi
```

### Bootstrap the system

```
pacstrap -K /mnt base base-devel linux linux-firmware intel-ucode btrfs-progs networkmanager vim git rsync openssh man-db systemd-ukify sbsigntools sbctl efitools efibootmgr
genfstab -U /mnt >> /mnt/etc/fstab
```

In `/mnt/etc/fstab`, for `/efi`, change the parameters `fmask=0022,dmask=0022` to `fmask=0077,dmask=0077`

### Time to chroot

```
arch-chroot /mnt
ln -sf /usr/share/zoneinfo/Europe/Luxembourg /etc/localtime
hwclock --systohc
systemctl enable NetworkManager
```

Edit `/etc/locale.gen` and uncomment `en_US.UTF-8`, then run this command:

```
locale-gen
```

Edit `/etc/locale.conf`, add:

```
LANG=en_US.UTF-8
```

Edit `/etc/vconsole.conf`, add:

```
KEYMAP=fr
```

Set the hostname:

```
echo hc-promax14 > /etc/hostname
```

Set the root password:

```
passwd
```

Create a user

```
useradd -m hcartiaux
passwd hcartiaux
usermod -G wheel hcartiaux
```

Give sudo permissions to the users in the `wheel` group:

```
visudo
%wheel ALL=(ALL:ALL) ALL
```

### UKI and Boot manager installation with Secure Boot

Create the file `/etc/kernel/uki.conf`:

```
[UKI]
OSRelease=@/etc/os-release
PCRBanks=sha256

[PCRSignature:initrd]
Phases=enter-initrd
PCRPrivateKey=/etc/kernel/pcr-initrd.key.pem
PCRPublicKey=/etc/kernel/pcr-initrd.pub.pem
```

Generate the keys used for Secure Boot

```
ukify genkey --config=/etc/kernel/uki.conf
```

Create the directory for the UKI files

```
mkdir -p /efi/EFI/Linux
```

Edit `/etc/mkinitcpio.conf`, add the necessary hooks (`systemd`, `sd-vconsole`, `sd-encrypt`):

```
HOOKS=(base systemd udev autodetect microcode modconf kms keyboard keymap consolefont sd-vconsole block sd-encrypt filesystems fsck)
```

Pass kernel parameters with files in `/etc/cmdline.d`. First, specify the encrypted root partition.
Replace the UUID with the output of `blkid | grep '/dev/nvme0n1p2' | sed 's/.*UID="\([^"]*\).*/\1/'`

```
root=/dev/mapper/cryptroot rootflags=rw,relatime,compress=zstd:3,ssd,space_cache=v2,subvol=/@ rd.luks.name=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX=cryptroot rd.luks.options=discard rw > /etc/cmdline.d/root.conf
```

For more security, disable the maintenance shell, add these parameters:

```
echo rd.shell=0 rd.emergency=reboot > /etc/cmdline.d/default.conf
```

Edit `/etc/mkinitcpio.d/linux.preset`:

```
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default' 'fallback')
default_uki="/efi/EFI/Linux/arch-linux.efi"
default_options="--splash=/usr/share/systemd/bootctl/splash-arch.bmp"
fallback_uki="/efi/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
```

Generate the UKIs:

```
mkinitcpio -p linux
```

Install the bootloader:

```
bootctl install
```

## Reboot !

Exit the chroot

```
exit
umount -R /mnt
reboot
```

And hopefully, boot the new system and login as root

### Secure Boot

#### Base

```
sbctl create-keys
sbctl enroll-keys -m --firmware-builtin --tpm-eventlog
sbctl status
sbctl verify
sbctl sign --save /efi/EFI/BOOT/BOOTX64.EFI
sbctl sign --save /efi/EFI/Linux/arch-linux-fallback.efi
sbctl sign --save /efi/EFI/Linux/arch-linux.efi
sbctl sign --save /efi/EFI/systemd/systemd-bootx64.efi
```

#### Firmware update preparation

Prepare the system for future firmware updates using the command `fwupdmgr`

```
pacman -S fwupd
pacman -S shim

sbctl sign -s /usr/lib/fwupd/efi/fwupdx64.efi -o /usr/lib/fwupd/efi/fwupdx64.efi.signed
cp /usr/share/shim/shimx64.efi /efi/EFI/systemd
cp /usr/lib/fwupd/efi/fwupdx64.efi /efi/EFI/systemd
sbctl sign --save /efi/EFI/systemd/fwupdx64.efi
sbctl sign --save /efi/EFI/systemd/shimx64.efi
```

#### Reboot

Reboot once again (Secure Boot in deployed mode)

Verify the output of `bootctl`.

### TPM Enroll

Enroll the TPM device

```
systemd-cryptenroll --tpm2-device=list
cryptsetup luksDump /dev/nvme0n1p2
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 --tpm2-public-key /etc/kernel/pcr-initrd.pub.pem  /dev/nvme0n1p2
```

Note: if the UEFI configuration changes, you may need to reenroll the TPM:

```
systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p2 --tpm2-pcrs=0+7
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 --tpm2-public-key /etc/kernel/pcr-initrd.pub.pem  /dev/nvme0n1p2
```

### Install and enable [AppArmor](https://wiki.archlinux.org/title/AppArmor)

```
pacman -S apparmor
systemctl enable apparmor
echo lsm=landlock,lockdown,yama,integrity,apparmor,bpf > /etc/cmdline.d/apparmor.conf
```

In the file `/etc/apparmor/parser.conf`, uncomment write-cache:

```
## Turn creating/updating of the cache on by default
write-cache
```

## Reboot again !

And login as user `hcartiaux`

### Install yay

```
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -s
sudo pacman -U yay*.tar.zst
```

### Using snapper for snapshotting

```
sudo pacman -S snapper snap-pac
sudo snapper -c root create-config /
sudo snapper create --description "Initial set-up"
```

### Install [aconfmgr](https://github.com/CyberShadow/aconfmgr)

```
sudo yay -S aconfmgr-git
mkdir ~/.config/
cd ~/.config/
git clone https://github.com/hcartiaux/aconfmgr.git
cd ~/.config/aconfmgr
aconfmgr apply
```

My configuration is [versioned on github](https://github.com/hcartiaux/aconfmgr).

## External resources

* [Modern Arch linux installation guide](https://gist.github.com/mjkstra/96ce7a5689d753e7a6bdd92cdc169bae)
* [Arch Linux install with full disk encryption using LUKS2 - Logical Volumes with LVM2 - Secure Boot - TPM2 Setup](https://github.com/joelmathewthomas/archinstall-luks2-lvm2-secureboot-tpm2)
* [Encrypting an entire system with TPM2 and Secure Boot](https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_system#LUKS_on_a_partition_with_TPM2_and_Secure_Boot)
* [UEFI and Secure Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot)
* [Snapper](https://wiki.archlinux.org/title/Snapper)
* [AppArmor](https://wiki.archlinux.org/title/AppArmor)


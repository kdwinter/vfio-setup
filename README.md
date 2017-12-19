# My VFIO setup

This is my personal VFIO setup. It is here in the hope that it can be
helpful to anyone else setting this up.

## Details

* Host OS: Arch Linux
* VM OS: Windows 7 on a physical SSD
* Guest GPU: NVIDIA GTX970
* Plain QEMU without libvirt
* SeaBIOS (no UEFI)
* Using two monitors, one being turned off in the host OS and switched to the guest GPU when starting the VM.
* Using Synergy (with server on the VM) to share keyboard and mouse. I recommend also having a backup keyboard connected, just in case.

To run this script as your user (not root), you have to create some udev
rules so that it can actually access the vfio/usb devices.

If you don't mind running as root, uncomment the export QEMU_PA_SERVER var
and remove any instance of "sudo" in the script, and also remove the chmod/chown
lines related to your disks in setup().

This page also assumes you've already set up your VFIO modules and ethernet bridge and such as well.
More relevant material can be found here:


https://forum.level1techs.com/t/ryzen-gpu-passthrough/116458/7 (original source of the main script)
https://wiki.archlinux.org/index.php/QEMU
https://bbs.archlinux.org/viewtopic.php?id=162768
https://reddit.com/r/VFIO
https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF

You can check your IOMMU groups with the included ```check_iommu.sh``` script.


## Setup

### Add your user to the kvm group

```
$ sudo usermod -a -G kvm $username
```

### Allow your user to run "ip" and "brctl" commands with sudo without prompting password:

```
$ visudo
```

Add these lines:

```
Cmnd_Alias     QEMU = /usr/bin/ip, /usr/bin/brctl
%kvm ALL=(root) NOPASSWD: QEMU
```

### Tell udev to allow users to access VFIO and specific USB devices.

You can find the necessary idVendor and idProduct strings by running:

```
$ sudo udevadm info -a -p $(udevadm info -q path -n /dev/input/by-id/<keyboard or mouse>)
```

Then, add the rules:

```
$ sudo vim /etc/udev/rules.d/10-qemu-hw-users.rules
```

```
# GPU
SUBSYSTEM=="vfio", TAG+="uaccess"
# Keyboard
SUBSYSTEM=="usb", ATTRS{idVendor}=="1b1c", ATTRS{idProduct}=="1b07", TAG+="uaccess"
# Mouse
SUBSYSTEM=="usb", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c085", TAG+="uaccess"
```

Then, let udev rescan devices by running (alternatively, you can reboot):

```
$ sudo udevadm control -R
$ sudo udevadm trigger
```

### Increase memory limits for your <username>

```
$ sudo vim /etc/security/limits.conf
```

Add these lines (with your username, and change the memory if needed, this is around 9GB):

```
<username>	hard	memlock	9000000
<username>	soft	memlock	9000000
```

### Edit the vars at the top of ```windows7vm.sh``` as needed for your configuration.


## Running

```
./windows7vm.sh
```


## License

Public domain.

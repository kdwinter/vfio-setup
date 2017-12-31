# My VFIO setup

This is my personal VFIO setup. It is here in the hope that some bits and
pieces can be helpful to anyone else setting up VFIO/PCI Passthrough.

## Details

* Host OS: Arch Linux
* VM OS: Windows 7 on a physical SSD
* Guest GPU: NVIDIA GTX970
* `qemu-patched` (for CPU pinning) from AUR without libvirt
* SeaBIOS (no UEFI)
* Dual monitor, one being turned off in host and switched to guest GPU when starting the VM.
* Using Synergy (server running in VM guest) to share keyboard and mouse. Recommend still having another backup keyboard connected to your host, in case something goes wrong.

To run this script as your user (not root), you have to create some udev
rules so that it can actually access the vfio/usb devices.

If you don't mind running as root, modify `windows7vm.sh` by uncommenting the `export QEMU_PA_SERVER` var, removing any instance of `sudo`, and also removing the `chmod`/`chown` lines related to your disks in `setup()`.

This page assumes you've already enabled IOMMU, set up your VFIO modules, ethernet bridge and such as well.
More relevant resources can be found here:

https://forum.level1techs.com/t/ryzen-gpu-passthrough/116458/7 (original source of the main script)  
https://wiki.archlinux.org/index.php/QEMU  
https://bbs.archlinux.org/viewtopic.php?id=162768  
https://reddit.com/r/VFIO  
https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF  

You can check your IOMMU groups with the included ```check_iommu.sh``` script.


## Setup

### Add your user to the kvm group

```
$ sudo usermod -a -G kvm <username>
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

### Tell udev to allow users to access VFIO and specific USB devices

You can find the necessary idVendor and idProduct strings by running:

```
$ sudo udevadm info -a -p $(udevadm info -q path -n /dev/input/by-id/<keyboard or mouse>)
```

You can also extract the vendor:product pairs from `lsusb`.

Then, add the rules (replace the ID's with your own):

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

### Increase memory limits for your user

```
$ sudo vim /etc/security/limits.conf
```

Add these lines (replace username with yours, and change the amount if needed, this is around 9GB):

```
username	hard	memlock	9000000
username	soft	memlock	9000000
```

### Edit the vars at the top of ```windows7vm.sh``` as needed for your configuration


## Running

```
./windows7vm.sh
```


## License

Public domain.

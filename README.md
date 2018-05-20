# My VFIO setup

This is my personal VFIO setup. It is here in the hope that some bits and
pieces can be helpful to anyone else setting up VFIO/PCI Passthrough.

## Details

* Host OS: Arch Linux x86_64
* VM OS: Windows 7 64-bit on a physical SSD. Still bootable by itself also
* Guest GPU: NVIDIA GTX970
* Using [`qemu-patched`](https://aur.archlinux.org/packages/qemu-patched/) for CPU pinning
* Not using libvirt
* Using BIOS mode instead of UEFI; mostly because my existing Windows drive was installed this way
* Dual monitor, one being turned off in host and switched to guest GPU when starting VM
* Using Synergy, server running in guest, to share keyboard and mouse. Recommend still having another backup keyboard connected to your host, in case something goes wrong
* Running QEMU as non-root user

This page assumes you've already enabled IOMMU, set up your VFIO modules, ethernet bridge and such as well.
If needed, you can check your IOMMU groups with the included `check_iommu.sh` script (taken from the [Arch Wiki](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF#Ensuring_that_the_groups_are_valid)).

More relevant resources can be found here:

https://forum.level1techs.com/t/ryzen-gpu-passthrough/116458/7 (original source of the main script)  
https://wiki.archlinux.org/index.php/QEMU  
https://bbs.archlinux.org/viewtopic.php?id=162768  
https://reddit.com/r/VFIO  
https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF  


## Prerequisites, configuration, and setup

### Add your user to the kvm group

```
$ sudo usermod -a -G kvm yourusername
```

### (optional/QoL) Allow your user to run "sudo ip" and "sudo brctl" commands **without** prompting password:

This is only necessary if you want the teardown function to run without
additional sudo password prompts.

```
$ visudo
```

Add these lines:

```
Cmnd_Alias     QEMU = /usr/bin/ip, /usr/bin/brctl
%kvm ALL=(root) NOPASSWD: QEMU
```

### Tell udev to allow non-root users to access VFIO and specific USB devices

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

### Edit `windows7vm.sh` to suit your configuration


## Running

```
./windows7vm.sh
```

## Known issues (TODO)

* VM audio is delayed by ~100ms, most noticable in Quake Live. Have not yet tried audio modes other than `hda` to see if that fixes the issue.
* Synergy does not fully play nice with i3. Pressing Windows+L while host has focus results in the guest receiving that combination and locking the screen.
* Synergy has to be stopped/paused on the host while playing certain games (even first-person shooters), to prevent the mouse from reaching into the host while playing.


## License

See UNLICENSE.

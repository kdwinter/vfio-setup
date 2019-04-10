#!/usr/bin/env bash
# vim:ts=4:sw=4:sts=4:et:ft=sh:
set -euo pipefail
shopt -s nullglob globstar

err() {
    say "$@" >&2
}

say() {
    echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")]: $*"
}

# QEMU 2.12 finally removed the `-usbdevice` option; `-device usb-host` has taken
# its place with a slightly different syntax. This is just a helper function
# that takes the 'old' product pairs, and returns them in the proper usb-host
# option format.
#
#   vendorproductpair_to_qemu "0001:0002" #=> "vendorid=0x0001,productid=0x0002"
#
vendorproductpair_to_qemu() {
    local vendorproductpair="$1"
    echo -n "vendorid=0x$(echo "$vendorproductpair" | cut -c1-4),productid=0x$(echo "$vendorproductpair" | cut -c6-10)"
}

# Arbitrary VM name
vmname="win7"

# Your host username (you can run this as root, but check README and/or just edit
# this script for that)
username="$(whoami)"

# Your host machine hostname (for Synergy; note that your Synergy server
# inside the VM needs to be setup to expect this client)
hostname="$(hostname)"

# Drives being used. Make sure the Windows drive is first
drives=("$(realpath "/dev/disk/by-id/ata-M4-CT256M4SSD2_00000000123609151EB7")")
#        "$(realpath "/dev/disk/by-id/ata-WDC_WD2500KS-00MJB0_WD-WCANK8625812")")

# TAP interface being created/bridged. Name it whatever
veth="vmtap0"

# Name of an existing bridge that already includes your internet connection
bridge="bridge0"

# GPU BIOS ROM (not necessary currently)
#romfile="/data/vms/nvidia_msi_gtx970.rom"

# USB keyboard ID (check lsusb)
#keyboard_id="1b1c:1b07"
#keyboard_id="045e:00db"
keyboard_id="04d9:0296"

# USB mouse ID (check lsusb)
#mouse_id="046d:c085"
mouse_id="04a5:8001"

# USB microphone ID
microphone_id="0d8c:0005"

# USB network dongle
usb_network_id="0b95:1790"

# GPU VFIO ids (check your iommu groups)
vfio_id_1="2e:00.0"
vfio_id_2="2e:00.1"

# Default primary monitor, also the one to be used by the VM
primary_monitor="DisplayPort-0"
primary_monitor_resolution="2560x1440"

# Secondary monitor that remains
secondary_monitor="DisplayPort-2"
secondary_monitor_resolution="2560x1440"

# Guest VM IP (for synergy)
vm_ip=""
if lsusb | grep -q "$usb_network_id"; then
    #vm_ip="192.168.0.131"
    vm_ip="192.168.178.24"
else
    vm_ip="192.168.0.239"
fi

# PulseAudio output
# You can find your sink/source by running:
# $ pactl list
#pulseaudio_sink="alsa_output.pci-0000_30_00.3.analog-stereo"
pulseaudio_sink="bluez_sink.00_16_94_21_C1_07.a2dp_sink"

# PulseAudio input
# NOTE: This is completely useless. Also passing microphone through via USB
#       instead
#pulseaudio_source="alsa_input.usb-BLUE_MICROPHONE_Blue_Snowball_201705-00.analog-mono"

# Socket for QEMU console
socket="$HOME/qemu-$vmname.sock"

if [ -e "$socket" ]; then
    err "✗ Bailing because a QEMU socket file exists for this VM at '$socket'."
    err "  Was there an unclean shutdown, or is the VM already running?"
    exit 1
fi

##############################################################################
# Standard PulseAudio ENV variables

export QEMU_AUDIO_DRV="pa"
export QEMU_PA_SAMPLES=4096
export QEMU_PA_SINK="$pulseaudio_sink"
#export QEMU_PA_SOURCE="$pulseaudio_source"
# Uncomment if running as root
#export QEMU_PA_SERVER="/run/user/1000/pulse/native"

##############################################################################

setup() {
    say "Beginning VM setup"

    # Remove these if running as root
    for drive in "${drives[@]}"; do
        say "---> Fixing $drive permissions"
        sudo chmod g-w "$drive"
        sudo chown "$username" "$drive"
    done
    unset drive

    say "Creating $veth tap device"
    sudo ip tuntap add dev "$veth" mode tap
    # user $username group kvm
    sudo ip link set "$veth" up
    #sudo ip addr add 192.168.0.223 dev "$veth"
    say "Adding $veth to $bridge"
    sudo brctl addif "$bridge" "$veth"

    say "Starting synergy"
    synergyc --debug ERROR --name "$hostname" "$vm_ip"

    say "Switching displays"
    xrandr --output "$primary_monitor" --off
    xrandr --output "$secondary_monitor" --mode "$secondary_monitor_resolution" --pos 0x0 --primary

    #say "Setting up Looking Glass"
    #sudo touch /dev/shm/looking-glass
    #sudo chown "$username":kvm /dev/shm/looking-glass
    #sudo chmod 660 /dev/shm/looking-glass
}

teardown() {
    # Still care if things fail here, but the whole list should be run through.
    set +e

    say "Removing $veth from $bridge"
    sudo brctl delif "$bridge" "$veth"
    say "Removing $veth tap device"
    sudo ip link set "$veth" down
    sudo ip tuntap del dev "$veth" mode tap

    say "Terminating synergy"
    killall synergyc

    say "Restoring displays"
    xrandr --output "$primary_monitor" --mode "$primary_monitor_resolution" --pos 0x0 --primary
    xrandr --output "$secondary_monitor" --mode "$secondary_monitor_resolution" --pos "$(echo -n "$primary_monitor_resolution" | sed 's/x.*//g')"x0

    # These might not be necessary for you, but after shutting down the VM and
    # regaining control of these USB devices, these settings (keymap, mouse sens)
    # need to be re-set also...
    say "Restoring USB keyboard and mouse settings (layout, rates, sensitivity)"
    setxkbmap be
    xset r rate 350 40
    xset m 0 0
    # Change this to the name of your mouse (if needed at all)
    while read -r mouse_id; do
        xinput set-prop "$mouse_id" 'libinput Accel Speed' 0 >/dev/null 2<&1
    done <<< "$(xinput list | grep "ZOWIE" | awk '{print $9}' | sed "s/id=//")"

    if [ -e "$socket" ]; then
        say "Removing zombie socket"
        rm -f "$socket"
    fi

    say "✓ VM teardown completed"

    set -e
}

quit() {
    # Install openbsd-netcat for this.
    echo "system_powerdown" | nc -U "$socket"
    err "✗ Terminated"
}

run_qemu() {
    say "Starting QEMU"

    drive_options=""
    for i in "${!drives[@]}"; do
        drive_options=" $drive_options -drive file=${drives[$i]},if=virtio,index=$i"
    done
    unset i

    usb_devices="-device usb-host,$(vendorproductpair_to_qemu "$keyboard_id") -device usb-host,$(vendorproductpair_to_qemu "$mouse_id") -device usb-host,$(vendorproductpair_to_qemu "$microphone_id")"

    # USB->Ethernet dongle
    if lsusb | grep -q "$usb_network_id"; then
        usb_devices="$usb_devices -device usb-host,$(vendorproductpair_to_qemu "$usb_network_id")"
    fi

    # Note that kvm=off and hv_vendor_id=whatever on the -cpu line are only
    # necessary for nvidia GPUs, to prevent their drivers from self-sabotaging
    # once they detect a virtualized environment (Error 43).
    exec qemu-system-x86_64 \
        -enable-kvm \
        -m 8G \
        -soundhw hda \
        -cpu host,kvm=off,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time,hv_vendor_id=whatever \
        -smp cores=6,threads=2,sockets=1,maxcpus=12 \
        -vcpu vcpunum=0,affinity=1 \
        -vcpu vcpunum=1,affinity=3 \
        -vcpu vcpunum=2,affinity=5 \
        -vcpu vcpunum=3,affinity=7 \
        -vcpu vcpunum=4,affinity=8 \
        -vcpu vcpunum=5,affinity=9 \
        -vcpu vcpunum=6,affinity=10 \
        -vcpu vcpunum=7,affinity=11 \
        -vcpu vcpunum=8,affinity=12 \
        -vcpu vcpunum=9,affinity=13 \
        -vcpu vcpunum=10,affinity=14 \
        -vcpu vcpunum=11,affinity=15 \
        $drive_options \
        -bios /usr/share/qemu/bios.bin \
        -machine q35,accel=kvm \
        -name $vmname \
        -net nic,macaddr=52:54:0F:1E:3D:4C,model=virtio \
        -net tap,ifname=$veth,script=no,downscript=no,vhost=on \
        -usb $usb_devices \
        -device usb-kbd -device usb-mouse \
        -device vfio-pci,host=$vfio_id_1,multifunction=on,x-vga=on \
        -device vfio-pci,host=$vfio_id_2 \
        -nographic \
        -vga none \
        -monitor unix:$socket,server,nowait

        #-netdev tap,fd=25,id=hostnet0 \
        #-device rtl8139,netdev=hostnet0,id=net0,mac=52:54:0F:1E:3D:4C,bus=pci.0,addr=0x3 \
        #-device ivshmem-plain,memdev=ivshmem \
        #-object memory-backend-file,id=ivshmem,share=on,mem-path=/dev/shm/looking-glass,size=32M \
        #-device vfio-pci,host=$vfio_id_1,multifunction=on,romfile=$romfile,x-vga=on \
        #-device virtio-mouse-pci,id=input0 \
        #-device virtio-keyboard-pci,id=input1 \
        #-object input-linux,id=mouse1,evdev=$mouse \
        #-object input-linux,id=kbd1,evdev=$kbd2 \
        #-object input-linux,id=kbd2,evdev=$kbd,grab_all=on,repeat=on \
        #-net bridge,br=$bridge \
        #-net user \
        #-net user,hostfwd=tcp::42323-:24800 \
        #-rtc base=localtime,clock=host \
}

##############################################################################
# Run stuff

setup

(run_qemu) &

trap "teardown" EXIT ERR INT
trap "quit" TERM

wait

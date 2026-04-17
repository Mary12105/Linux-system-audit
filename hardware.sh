#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# ── Helpers ─────────────────────────────────────────────
tag_kv() {
    printf "[%s]  %-20s %s\n" "$1" "$2:" "$3"
}

tag_raw() {
    printf "[%s]  %s\n" "$1" "$2"
}

tag_header() {
    printf "[%s:header]  %s\n" "$1" "$2"
}

# =======================================================
# CPU
# SHORT : model, architecture, core count
# FULL  : frequency, cache sizes, virtualization
# =======================================================
collect_cpu() {
    tag_header "HW:cpu" "CPU"

    if cmd_exists lscpu; then
        # --- short ---
        tag_kv "HW:cpu"      "Model"          "$(lscpu | grep 'Model name'          | cut -d: -f2)"
        tag_kv "HW:cpu"      "Architecture"   "$(lscpu | grep '^Architecture'       | cut -d: -f2)"
        tag_kv "HW:cpu"      "Cores"          "$(nproc)"

        # --- full ---
        tag_kv "HW:cpu:full" "Threads/core"   "$(lscpu | grep 'Thread(s) per core'  | cut -d: -f2)"
        tag_kv "HW:cpu:full" "Sockets"        "$(lscpu | grep 'Socket(s)'           | cut -d: -f2)"
        tag_kv "HW:cpu:full" "MHz (max)"      "$(lscpu | grep 'CPU max MHz'         | cut -d: -f2)"
        tag_kv "HW:cpu:full" "MHz (min)"      "$(lscpu | grep 'CPU min MHz'         | cut -d: -f2)"
        tag_kv "HW:cpu:full" "L1d cache"      "$(lscpu | grep 'L1d cache'           | cut -d: -f2)"
        tag_kv "HW:cpu:full" "L1i cache"      "$(lscpu | grep 'L1i cache'           | cut -d: -f2)"
        tag_kv "HW:cpu:full" "L2 cache"       "$(lscpu | grep 'L2 cache'            | cut -d: -f2)"
        tag_kv "HW:cpu:full" "L3 cache"       "$(lscpu | grep 'L3 cache'            | cut -d: -f2)"
        tag_kv "HW:cpu:full" "Virtualization" "$(lscpu | grep 'Virtualization'      | cut -d: -f2)"
    else
        tag_kv "HW:cpu" "Model" "$(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2)"
    fi
}

# =======================================================
# GPU
# SHORT : device name only
# FULL  : full lspci verbose block
# =======================================================
collect_gpu() {
    tag_header "HW:gpu" "GPU"

    if cmd_exists lspci; then
        # --- short ---
        lspci | grep -Ei 'vga|3d|display' | while read -r line; do
            tag_kv "HW:gpu" "Device" "$(echo "$line" | cut -d' ' -f3-)"
        done

        # --- full ---
        lspci -v | grep -A6 -Ei 'vga|3d|display' | while read -r line; do
            tag_raw "HW:gpu:full" "$line"
        done
    else
        tag_raw "HW:gpu" "No GPU info available"
    fi
}

# =======================================================
# RAM
# SHORT : total, used, free (physical)
# FULL  : swap stats, DIMM details via dmidecode
# =======================================================
collect_ram() {
    tag_header "HW:ram" "RAM"

    if cmd_exists free; then
        # --- short ---
        tag_kv "HW:ram"      "Total"      "$(free -h | awk '/Mem:/  {print $2}')"
        tag_kv "HW:ram"      "Used"       "$(free -h | awk '/Mem:/  {print $3}')"
        tag_kv "HW:ram"      "Free"       "$(free -h | awk '/Mem:/  {print $4}')"

        # --- full ---
        tag_kv "HW:ram:full" "Swap Total" "$(free -h | awk '/Swap:/ {print $2}')"
        tag_kv "HW:ram:full" "Swap Used"  "$(free -h | awk '/Swap:/ {print $3}')"
    fi

    # --- full : individual DIMM slots (requires root) ---
    if cmd_exists dmidecode; then
        dmidecode -t memory 2>/dev/null \
            | grep -E 'Size|Type:|Speed|Manufacturer|Locator' \
            | while read -r line; do
                tag_raw "HW:ram:full" "$line"
              done
    fi
}

# =======================================================
# DISK
# SHORT : disk name + size (top-level only), usage% per mount
# FULL  : full lsblk tree with FSTYPE/UUID, detailed df,
#         disk model/serial, partition table type
# =======================================================
collect_disk() {
    tag_header "HW:disk" "Disk"

    # --- short ---
    if cmd_exists lsblk; then
        lsblk -o NAME,SIZE,TYPE | grep 'disk' | while read -r line; do
            tag_raw "HW:disk" "$line"
        done
    fi

    if cmd_exists df; then
        df -h --output=source,size,pcent,target | tail -n +2 | while read -r line; do
            tag_raw "HW:disk" "$line"
        done
    fi

    # --- full ---
    if cmd_exists lsblk; then
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,UUID | tail -n +2 | while read -r line; do
            tag_raw "HW:disk:full" "$line"
        done
    fi

    if cmd_exists df; then
        df -h --output=source,size,used,avail,pcent,target | tail -n +2 | while read -r line; do
            tag_raw "HW:disk:full" "$line"
        done
    fi

    if cmd_exists lsblk; then
        lsblk -o NAME,MODEL,SERIAL 2>/dev/null | tail -n +2 | while read -r line; do
            tag_raw "HW:disk:full" "$line"
        done
    fi

    if cmd_exists fdisk; then
        fdisk -l 2>/dev/null | grep -E 'Disk /dev|Disklabel' | while read -r line; do
            tag_raw "HW:disk:full" "$line"
        done
    fi
}

# =======================================================
# NETWORK
# SHORT : interface name + IP address (ip -brief addr)
# FULL  : MAC addresses, gateway, routing table, DNS, stats
# =======================================================
collect_network() {
    tag_header "HW:net" "Network"

    if cmd_exists ip; then
        # --- short ---
        ip -brief addr | while read -r line; do
            tag_raw "HW:net" "$line"
        done

        # --- full ---
        ip -brief link | while read -r line; do
            tag_raw "HW:net:full" "$line"
        done

        tag_kv "HW:net:full" "Gateway" "$(ip route | grep default | awk '{print $3}')"

        ip route show | while read -r line; do
            tag_raw "HW:net:full" "$line"
        done

        ip -s link | grep -E 'LOWER_UP|RX:|TX:' | while read -r line; do
            tag_raw "HW:net:full" "$line"
        done
    fi

    # --- full : DNS servers ---
    if [ -f /etc/resolv.conf ]; then
        grep 'nameserver' /etc/resolv.conf | while read -r line; do
            tag_raw "HW:net:full" "$line"
        done
    fi
}

# =======================================================
# MOTHERBOARD
# SHORT : product name, vendor, BIOS version
# FULL  : board name/serial, BIOS date, chassis, UUID
# =======================================================
collect_motherboard() {
    tag_header "HW:board" "System"

    if [ -r /sys/class/dmi/id/product_name ]; then
        # --- short ---
        tag_kv "HW:board"      "Product"      "$(cat /sys/class/dmi/id/product_name)"
        tag_kv "HW:board"      "Vendor"        "$(cat /sys/class/dmi/id/sys_vendor)"
        tag_kv "HW:board"      "BIOS"          "$(cat /sys/class/dmi/id/bios_version)"

        # --- full ---
        tag_kv "HW:board:full" "Board Name"   "$(cat /sys/class/dmi/id/board_name   2>/dev/null)"
        tag_kv "HW:board:full" "Board Serial" "$(cat /sys/class/dmi/id/board_serial 2>/dev/null)"
        tag_kv "HW:board:full" "BIOS Date"    "$(cat /sys/class/dmi/id/bios_date    2>/dev/null)"
        tag_kv "HW:board:full" "Chassis"      "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)"
        tag_kv "HW:board:full" "System UUID"  "$(cat /sys/class/dmi/id/product_uuid 2>/dev/null)"
    else
        tag_raw "HW:board" "No system info available"
    fi
}

# =======================================================
# USB
# SHORT : one line per device (Bus/Device/ID/Name)
# FULL  : topology tree
# =======================================================
collect_usb() {
    tag_header "HW:usb" "USB"

    if cmd_exists lsusb; then
        # --- short ---
        lsusb | while read -r line; do
            tag_raw "HW:usb" "$line"
        done

        # --- full ---
        lsusb -t 2>/dev/null | while read -r line; do
            tag_raw "HW:usb:full" "$line"
        done
    else
        tag_raw "HW:usb" "lsusb not available"
    fi
}

# =======================================================
# MAIN
# =======================================================
collect_cpu
collect_gpu
collect_ram
collect_disk
collect_network
collect_motherboard
collect_usb

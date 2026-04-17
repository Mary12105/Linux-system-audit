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
# OS
# SHORT : distro name, kernel, arch, hostname, uptime
# FULL  : boot time, timezone, locale, SELinux/AppArmor,
#         kernel boot parameters
# =======================================================
collect_os() {
    tag_header "SW:os" "Operating System"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        # --- short ---
        tag_kv "SW:os" "Name" "$PRETTY_NAME"
    fi

    # --- short ---
    tag_kv "SW:os"      "Kernel" "$(uname -r)"
    tag_kv "SW:os"      "Arch"   "$(uname -m)"
    tag_kv "SW:os"      "Host"   "$(hostname)"
    tag_kv "SW:os"      "Uptime" "$(uptime -p 2>/dev/null || uptime)"

    # --- full ---
    tag_kv "SW:os:full" "Boot time"  "$(who -b 2>/dev/null | awk '{print $3, $4}')"
    tag_kv "SW:os:full" "Timezone"   "$(date +%Z)"
    tag_kv "SW:os:full" "Locale"     "$(locale | grep LANG= | cut -d= -f2)"

    if cmd_exists sestatus; then
        tag_kv "SW:os:full" "SELinux" "$(sestatus | head -1 | cut -d: -f2)"
    fi

    if cmd_exists aa-status; then
        tag_kv "SW:os:full" "AppArmor" "$(aa-status 2>/dev/null | head -1)"
    fi

    tag_raw "SW:os:full" "$(cat /proc/cmdline 2>/dev/null)"
}

# =======================================================
# PACKAGES
# SHORT : package manager name + total count
# FULL  : recently installed packages, available upgrades
# =======================================================
collect_packages() {
    tag_header "SW:pkg" "Packages"

    if cmd_exists dpkg; then
        # --- short ---
        tag_kv "SW:pkg"      "Manager" "dpkg"
        tag_kv "SW:pkg"      "Count"   "$(dpkg -l | grep -c '^ii')"

        # --- full ---
        if [ -f /var/log/dpkg.log ]; then
            grep ' install ' /var/log/dpkg.log | tail -10 | while read -r line; do
                tag_raw "SW:pkg:full" "$line"
            done
        fi

        if cmd_exists apt; then
            apt list --upgradable 2>/dev/null | grep -v 'Listing' | while read -r line; do
                tag_raw "SW:pkg:full" "$line"
            done
        fi

    elif cmd_exists rpm; then
        # --- short ---
        tag_kv "SW:pkg"      "Manager" "rpm"
        tag_kv "SW:pkg"      "Count"   "$(rpm -qa | wc -l)"

        # --- full ---
        rpm -qa --last 2>/dev/null | head -10 | while read -r line; do
            tag_raw "SW:pkg:full" "$line"
        done
    else
        tag_kv "SW:pkg" "Manager" "Unknown"
    fi
}

# =======================================================
# USERS
# SHORT : current user + session count
# FULL  : active session details, sudo members,
#         last logins, failed logins
# =======================================================
collect_users() {
    tag_header "SW:users" "Users"

    # --- short ---
    tag_kv "SW:users"      "Current"  "$(whoami)"
    tag_kv "SW:users"      "Sessions" "$(who | wc -l)"

    # --- full : active session details ---
    who | while read -r line; do
        tag_raw "SW:users:full" "$line"
    done

    # --- full : sudo group members ---
    tag_kv "SW:users:full" "Sudo members" "$(getent group sudo wheel 2>/dev/null | cut -d: -f4)"

    # --- full : recent logins ---
    if cmd_exists last; then
        last -n 10 2>/dev/null | while read -r line; do
            tag_raw "SW:users:full" "$line"
        done
    fi

    # --- full : failed logins (requires root) ---
    if cmd_exists lastb; then
        lastb -n 5 2>/dev/null | while read -r line; do
            tag_raw "SW:users:full" "$line"
        done
    fi
}

# =======================================================
# SERVICES
# SHORT : running service count + top 10 names
# FULL  : failed services, enabled (auto-start) services
# =======================================================
collect_services() {
    tag_header "SW:svc" "Services"

    if cmd_exists systemctl; then
        # --- short ---
        tag_kv "SW:svc"      "Running" "$(systemctl list-units --type=service --state=running --no-legend | wc -l)"

        systemctl list-units --type=service --state=running --no-legend \
            | head -10 \
            | while read -r line; do
                tag_raw "SW:svc" "$line"
              done

        # --- full : all running (no head limit) ---
        systemctl list-units --type=service --state=running --no-legend \
            | tail -n +11 \
            | while read -r line; do
                tag_raw "SW:svc:full" "$line"
              done

        # --- full : failed services ---
        systemctl list-units --type=service --state=failed --no-legend \
            | while read -r line; do
                tag_raw "SW:svc:full" "$line"
              done

        # --- full : enabled (auto-start) services ---
        systemctl list-unit-files --type=service --state=enabled --no-legend \
            | while read -r line; do
                tag_raw "SW:svc:full" "$line"
              done
    else
        tag_raw "SW:svc" "systemctl not available"
    fi
}

# =======================================================
# PROCESSES
# SHORT : total count + top 5 by CPU
# FULL  : top 10 by memory, zombie processes, process tree
# =======================================================
collect_processes() {
    tag_header "SW:proc" "Processes"

    # --- short ---
    tag_kv "SW:proc"      "Total" "$(ps aux | wc -l)"

    ps aux --sort=-%cpu | head -6 | while read -r line; do
        tag_raw "SW:proc" "$line"
    done

    # --- full : top 10 by memory ---
    ps aux --sort=-%mem | head -11 | while read -r line; do
        tag_raw "SW:proc:full" "$line"
    done

    # --- full : zombie processes ---
    ps aux | awk '$8=="Z"' | while read -r line; do
        tag_raw "SW:proc:full" "$line"
    done

    # --- full : process tree ---
    if cmd_exists pstree; then
        pstree -p 2>/dev/null | while read -r line; do
            tag_raw "SW:proc:full" "$line"
        done
    fi
}

# =======================================================
# PORTS
# SHORT : listening ports only, first 10, no PIDs
# FULL  : all listening with process names/PIDs,
#         established connections, socket summary
# =======================================================
collect_ports() {
    tag_header "SW:ports" "Ports"

    if cmd_exists ss; then
        # --- short ---
        ss -tuln | head -11 | while read -r line; do
            tag_raw "SW:ports" "$line"
        done

        # --- full : all listening with owning process ---
        ss -tulnp | while read -r line; do
            tag_raw "SW:ports:full" "$line"
        done

        # --- full : established connections ---
        ss -tunp | grep ESTAB | while read -r line; do
            tag_raw "SW:ports:full" "$line"
        done

        # --- full : socket summary ---
        ss -s | while read -r line; do
            tag_raw "SW:ports:full" "$line"
        done
    else
        tag_raw "SW:ports" "ss not available"
    fi
}

# =======================================================
# SECURITY
# SHORT : firewall status, sudo version
# FULL  : full firewall rules, SSH config key settings,
#         all user crontabs, SUID files (root only)
# =======================================================
collect_security() {
    tag_header "SW:sec" "Security"

    if cmd_exists ufw; then
        # --- short ---
        tag_kv "SW:sec"      "Firewall" "$(ufw status | head -1)"

        # --- full ---
        ufw status verbose 2>/dev/null | while read -r line; do
            tag_raw "SW:sec:full" "$line"
        done

    elif cmd_exists iptables; then
        # --- short ---
        tag_kv "SW:sec"      "Firewall" "iptables active"

        # --- full ---
        iptables -L -n -v 2>/dev/null | while read -r line; do
            tag_raw "SW:sec:full" "$line"
        done
    else
        tag_kv "SW:sec" "Firewall" "None"
    fi

    cmd_exists sudo && tag_kv "SW:sec" "Sudo" "$(sudo --version | head -1)"

    # --- full : SSH config key settings ---
    if [ -f /etc/ssh/sshd_config ]; then
        grep -E 'PermitRootLogin|PasswordAuthentication|Port' /etc/ssh/sshd_config \
            | while read -r line; do
                tag_raw "SW:sec:full" "$line"
              done
    fi

    # --- full : SUID/SGID files (requires root, can be slow) ---
    if [ "$(id -u)" -eq 0 ]; then
        find / -xdev -perm /6000 -type f 2>/dev/null | while read -r line; do
            tag_raw "SW:sec:full" "$line"
        done
    fi
}

# =======================================================
# MAIN
# =======================================================
collect_os
collect_packages
collect_users
collect_services
collect_processes
collect_ports
collect_security

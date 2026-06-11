#!/bin/bash
# ============================================================
#  CachyOS Security Hardening Script
#  - Remove telemetry
#  - Close unnecessary ports (UFW firewall)
#  - Harden the OS (AppArmor, sysctl, kernel hardened)
#  - Bluetooth is KEPT ENABLED
#  - Ends with pacman -Syu
#
#  Usage: sudo bash cachyos-harden.sh
# ============================================================

set -euo pipefail

# Must run as root
if [[ "$EUID" -ne 0 ]]; then
    echo "[!] Please run as root: sudo bash $0"
    exit 1
fi

echo ""
echo "============================================"
echo "   CachyOS Hardening & Privacy Script"
echo "============================================"
echo ""

# -------------------------------------------------------
# SECTION 1: REMOVE TELEMETRY PACKAGES
# -------------------------------------------------------
echo "[*] Removing known telemetry/tracking packages..."

TELEMETRY_PKGS=(
    "packagekit"           # Often used for background reporting
    "gnome-user-docs"      # GNOME telemetry helper docs component
    "switcheroo-control"   # GPU switching reporter
    "fwupd"                # Firmware update daemon (pings LVFS servers)
    "geoclue"              # Location/telemetry service
    "geoclue2"             # Geolocation service v2
    "gnome-remote-desktop" # Remote desktop/telemetry
    "orca"                 # Accessibility reporter
    "tracker"              # GNOME tracker/indexer (phones home)
    "tracker-miners"       # Associated tracker miner
    "zeitgeist"            # Activity logging daemon
)

for pkg in "${TELEMETRY_PKGS[@]}"; do
    if pacman -Qi "$pkg" &>/dev/null; then
        echo "  [-] Removing: $pkg"
        pacman -Rns --noconfirm "$pkg" 2>/dev/null || echo "  [!] Could not remove $pkg (may have dependencies), skipping."
    else
        echo "  [~] Not installed, skipping: $pkg"
    fi
done

# Disable systemd telemetry/reporting units if present
echo "[*] Disabling telemetry-related systemd services..."
TELEMETRY_SERVICES=(
    "fwupd.service"
    "fwupd-refresh.timer"
    "geoclue.service"
    "tracker-store.service"
    "tracker-miner-fs.service"
    "zeitgeist.service"
    "zeitgeist-datahub.service"
    "packagekit.service"
    "switcheroo-control.service"
    "whoopsie.service"     # Ubuntu crash reporter (if somehow present)
    "apport.service"       # Ubuntu crash reporter (if somehow present)
)

for svc in "${TELEMETRY_SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "^$svc"; then
        echo "  [-] Disabling: $svc"
        systemctl disable --now "$svc" 2>/dev/null || true
        systemctl mask "$svc" 2>/dev/null || true
    else
        echo "  [~] Service not found, skipping: $svc"
    fi
done

echo "[*] Telemetry cleanup done."
echo ""

# -------------------------------------------------------
# SECTION 2: FIREWALL SETUP (UFW) - Close Unnecessary Ports
# -------------------------------------------------------
echo "[*] Setting up UFW firewall..."

# Install UFW if not present
if ! command -v ufw &>/dev/null; then
    echo "  [+] Installing UFW..."
    pacman -S --noconfirm ufw
fi

# Reset UFW to clean state
ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allow only common necessary ports — adjust to your needs
echo "  [+] Allowing essential outbound-initiated services..."

# SSH (optional — commented out by default for security; uncomment if needed)
# ufw allow 22/tcp comment 'SSH'

# DNS (needed for name resolution)
ufw allow out 53/udp comment 'DNS'
ufw allow out 53/tcp comment 'DNS TCP'

# HTTP / HTTPS
ufw allow out 80/tcp  comment 'HTTP'
ufw allow out 443/tcp comment 'HTTPS'

# NTP (time sync)
ufw allow out 123/udp comment 'NTP'

# DHCP client
ufw allow out 67/udp comment 'DHCP'
ufw allow out 68/udp comment 'DHCP'

# Bluetooth uses its OWN stack (kernel/hardware), NOT TCP/IP ports
# So UFW does NOT affect Bluetooth — Bluetooth is safe and kept ON

# Block some commonly abused incoming ports explicitly
echo "  [-] Blocking unnecessary/dangerous incoming ports..."
ufw deny in 23/tcp   comment 'Block Telnet'
ufw deny in 25/tcp   comment 'Block SMTP inbound'
ufw deny in 135/tcp  comment 'Block MS RPC'
ufw deny in 137/udp  comment 'Block NetBIOS'
ufw deny in 138/udp  comment 'Block NetBIOS'
ufw deny in 139/tcp  comment 'Block NetBIOS'
ufw deny in 445/tcp  comment 'Block SMB'
ufw deny in 1900/udp comment 'Block UPnP'
ufw deny in 5353/udp comment 'Block mDNS (Avahi)'

# Enable UFW
ufw --force enable
systemctl enable ufw

echo "[*] UFW firewall configured and enabled."
echo ""

# -------------------------------------------------------
# SECTION 3: DISABLE UNNECESSARY SERVICES (Keep Bluetooth ON)
# -------------------------------------------------------
echo "[*] Disabling unnecessary/risky services..."

UNNECESSARY_SERVICES=(
    "avahi-daemon.service"   # mDNS/Bonjour discovery — potential info leak
    "avahi-daemon.socket"    # Avahi socket
    "cups.service"           # Printing — disable if not needed
    "cups.socket"            # CUPS socket
    "cups.path"              # CUPS path unit
    "sshd.service"           # SSH server — disable if not using remote login
    "rpcbind.service"        # NFS RPC — not needed on desktop
    "nfs-server.service"     # NFS server
    "rsyncd.service"         # Rsync daemon
    "telnet.service"         # Telnet (insecure)
    "vsftpd.service"         # FTP server
    "ftpd.service"           # FTP daemon
    "smbd.service"           # Samba
    "nmbd.service"           # NetBIOS name service
)

for svc in "${UNNECESSARY_SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "^$svc"; then
        echo "  [-] Disabling: $svc"
        systemctl disable --now "$svc" 2>/dev/null || true
        systemctl mask "$svc" 2>/dev/null || true
    else
        echo "  [~] Not found, skipping: $svc"
    fi
done

# !! BLUETOOTH IS EXPLICITLY KEPT ENABLED !!
echo "  [+] Keeping Bluetooth enabled (as requested)..."
systemctl enable --now bluetooth.service 2>/dev/null || true

echo "[*] Service hardening done."
echo ""

# -------------------------------------------------------
# SECTION 4: SYSCTL KERNEL HARDENING
# -------------------------------------------------------
echo "[*] Applying sysctl kernel hardening parameters..."

SYSCTL_CONF="/etc/sysctl.d/99-cachyos-harden.conf"

cat > "$SYSCTL_CONF" << 'EOF'
# ============================================
# CachyOS Security Hardening - sysctl config
# ============================================

# --- Network Hardening ---
# Prevent IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable ICMP redirects (prevent MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Disable sending ICMP redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Ignore bogus ICMP error responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# SYN flood protection
net.ipv4.tcp_syncookies = 1

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Disable IPv6 router advertisements (unless needed)
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# Log martian packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Disable IP forwarding (not a router)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Protect against time-wait assassination
net.ipv4.tcp_rfc1337 = 1

# --- Kernel Hardening ---
# Restrict dmesg access to root
kernel.dmesg_restrict = 1

# Restrict kernel pointer leaks
kernel.kptr_restrict = 2

# Restrict ptrace (anti-debugging for other processes)
kernel.yama.ptrace_scope = 2

# Disable magic SysRq (optional, uncomment for extra hardening)
# kernel.sysrq = 0

# Hide kernel symbol addresses
kernel.perf_event_paranoid = 3

# Disable unprivileged BPF (important for security)
kernel.unprivileged_bpf_disabled = 1

# Enable BPF JIT hardening
net.core.bpf_jit_harden = 2

# Restrict userfaultfd (helps prevent exploits)
vm.unprivileged_userfaultfd = 0

# --- Memory Hardening ---
# Randomize memory layout (ASLR) - max
kernel.randomize_va_space = 2

# Prevent core dump of setuid programs
fs.suid_dumpable = 0
EOF

sysctl --system > /dev/null 2>&1
echo "[*] sysctl hardening applied: $SYSCTL_CONF"
echo ""

# -------------------------------------------------------
# SECTION 5: APPARMOR
# -------------------------------------------------------
echo "[*] Setting up AppArmor..."

if ! pacman -Qi apparmor &>/dev/null; then
    echo "  [+] Installing AppArmor..."
    pacman -S --noconfirm apparmor
fi

systemctl enable --now apparmor.service

# Add AppArmor to kernel cmdline if not already there
GRUB_FILE="/etc/default/grub"
if [[ -f "$GRUB_FILE" ]]; then
    if ! grep -q "apparmor=1" "$GRUB_FILE"; then
        echo "  [+] Adding AppArmor to GRUB kernel parameters..."
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 apparmor=1 security=apparmor"/' "$GRUB_FILE"
        grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || echo "  [!] Could not regenerate GRUB config, do it manually."
    else
        echo "  [~] AppArmor already in GRUB parameters."
    fi
else
    echo "  [!] /etc/default/grub not found (maybe using systemd-boot). Add 'apparmor=1 security=apparmor' to your boot entry manually."
fi

echo "[*] AppArmor enabled."
echo ""

# -------------------------------------------------------
# SECTION 6: INSTALL HARDENED KERNEL (OPTIONAL)
# -------------------------------------------------------
echo "[*] Installing linux-cachyos-hardened kernel (optional but recommended)..."
echo "  [i] This kernel carries extra security patches."
echo "  [i] Note: Some features are restricted vs the default kernel."

read -r -p "  Install linux-cachyos-hardened kernel? [y/N]: " INSTALL_HARDENED
if [[ "$INSTALL_HARDENED" =~ ^[Yy]$ ]]; then
    pacman -S --noconfirm linux-cachyos-hardened linux-cachyos-hardened-headers
    echo "  [+] Hardened kernel installed. It will appear in your bootloader."
else
    echo "  [~] Skipping hardened kernel install."
fi
echo ""

# -------------------------------------------------------
# SECTION 7: ADDITIONAL PRIVACY TWEAKS
# -------------------------------------------------------
echo "[*] Applying additional privacy tweaks..."

# Disable coredumps globally
if ! grep -q "* hard core 0" /etc/security/limits.conf 2>/dev/null; then
    echo "* hard core 0" >> /etc/security/limits.conf
    echo "* soft core 0" >> /etc/security/limits.conf
fi

# Restrict /proc to owner only (hides process info from other users)
if ! grep -q "proc-security" /etc/fstab 2>/dev/null; then
    echo "proc /proc proc nosuid,nodev,noexec,hidepid=2,gid=proc 0 0" >> /etc/fstab
    echo "  [+] /proc hardened in /etc/fstab (reboot to apply)."
fi

# Lock down /tmp with noexec
if ! grep -q "tmpfs /tmp" /etc/fstab 2>/dev/null; then
    echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777 0 0" >> /etc/fstab
    echo "  [+] /tmp hardened in /etc/fstab (noexec, nosuid)."
fi

# Disable Avahi completely via config (belt-and-suspenders)
if [[ -f /etc/avahi/avahi-daemon.conf ]]; then
    sed -i 's/^#*use-ipv4=.*/use-ipv4=no/' /etc/avahi/avahi-daemon.conf 2>/dev/null || true
    sed -i 's/^#*use-ipv6=.*/use-ipv6=no/' /etc/avahi/avahi-daemon.conf 2>/dev/null || true
fi

echo "[*] Privacy tweaks applied."
echo ""

# -------------------------------------------------------
# SECTION 8: SYSTEM UPDATE (pacman -Syu)
# -------------------------------------------------------
echo "[*] Running full system update: pacman -Syu ..."
echo ""
pacman -Syu

echo ""
echo "============================================"
echo "   Hardening Complete!"
echo "============================================"
echo ""
echo " Summary of what was done:"
echo "  [1] Telemetry packages removed/masked"
echo "  [2] UFW firewall enabled (deny all incoming)"
echo "  [3] Unnecessary services disabled"
echo "  [4] Bluetooth KEPT ENABLED"
echo "  [5] sysctl kernel hardening applied"
echo "  [6] AppArmor enabled"
echo "  [7] /proc and /tmp hardened in fstab"
echo "  [8] System updated via pacman -Syu"
echo ""
echo " !! REBOOT REQUIRED for all changes to take effect !!"
echo ""
read -r -p " Reboot now? [y/N]: " REBOOT_NOW
if [[ "$REBOOT_NOW" =~ ^[Yy]$ ]]; then
    reboot
fi

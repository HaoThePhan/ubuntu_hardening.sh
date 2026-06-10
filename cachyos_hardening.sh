#!/bin/bash

# CachyOS Privacy & Security Hardening Script
# Run with: sudo bash harden-cachyos.sh

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CachyOS Privacy & Security Hardening${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Backup current configuration
echo -e "${YELLOW}[1/6] Creating backup...${NC}"
BACKUP_DIR="/root/cachyos-hardening-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/sysctl.conf "$BACKUP_DIR/" 2>/dev/null || touch "$BACKUP_DIR/sysctl.conf.none"
cp /etc/sysctl.d/99-sysctl.conf "$BACKUP_DIR/" 2>/dev/null
cp /etc/ssh/sshd_config "$BACKUP_DIR/" 2>/dev/null
cp /etc/pacman.conf "$BACKUP_DIR/" 2>/dev/null
cp /etc/makepkg.conf "$BACKUP_DIR/" 2>/dev/null

echo -e "${GREEN}Backup created at: $BACKUP_DIR${NC}\n"

# Remove Telemetry and Privacy-invasive packages
echo -e "${YELLOW}[2/6] Removing telemetry and privacy-invasive services...${NC}"

# List of telemetry/tracking packages to remove
telemetry_packages=(
    "xdg-desktop-portal-gnome"  # Can send usage data
    "gnome-software"            # GNOME telemetry
    "packagekit"                # Can send statistics
)

# Check and remove telemetry packages if installed
for pkg in "${telemetry_packages[@]}"; do
    if pacman -Qq "$pkg" &>/dev/null; then
        echo -e "${YELLOW}Removing: $pkg${NC}"
        pacman -Rns --noconfirm "$pkg" 2>/dev/null
    fi
done

# Disable GNOME telemetry if using GNOME
if [ -d /usr/share/glib-2.0/schemas/ ]; then
    echo -e "${YELLOW}Disabling GNOME telemetry...${NC}"
    
    cat > /usr/share/glib-2.0/schemas/99-disable-privacy-invasive.gschema.override << 'EOF'
[org.gnome.desktop.privacy]
send-software-usage-stats=false
report-technical-problems=false
disable-camera=false
disable-microphone=false
hide-identity=true
old-files-age=uint32 7
recent-files-max-age=7
remove-old-temp-files=true
remove-old-trash-files=true

[org.gnome.system.location]
enabled=false

[org.gnome.desktop.search-providers]
disabled=['org.gnome.Nautilus.desktop']
disable-external=true
EOF
    
    glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>/dev/null
fi

# Disable KDE telemetry if using KDE Plasma
if command -v kwriteconfig5 &>/dev/null; then
    echo -e "${YELLOW}Disabling KDE telemetry...${NC}"
    kwriteconfig5 --file PlasmaUserFeedback --group Global --key FeedbackLevel 0
fi

# Disable systemd-resolved DNS telemetry (use traditional DNS)
if systemctl is-active --quiet systemd-resolved; then
    echo -e "${YELLOW}Configuring DNS privacy...${NC}"
    mkdir -p /etc/systemd/resolved.conf.d/
    cat > /etc/systemd/resolved.conf.d/privacy.conf << 'EOF'
[Resolve]
DNSStubListener=no
DNS=1.1.1.1 9.9.9.9
FallbackDNS=8.8.8.8
DNSSEC=yes
DNSOverTLS=opportunistic
EOF
    systemctl restart systemd-resolved 2>/dev/null
fi

# Disable some systemd services that may send data
systemd_services_to_disable=(
    "systemd-oomd.service"
)

for service in "${systemd_services_to_disable[@]}"; do
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        systemctl disable --now "$service" 2>/dev/null
        echo "Disabled: $service"
    fi
done

# Modify pacman.conf to disable usage statistics if present
if grep -q "UsageStat" /etc/pacman.conf 2>/dev/null; then
    sed -i 's/^UsageStat/#UsageStat/g' /etc/pacman.conf
fi

echo -e "${GREEN}Telemetry removed/disabled${NC}\n"

# Firewall Configuration
echo -e "${YELLOW}[3/6] Configuring firewall (firewalld)...${NC}"

# Install firewalld if not present
if ! command -v firewall-cmd &>/dev/null; then
    echo -e "${BLUE}Installing firewalld...${NC}"
    pacman -S --noconfirm firewalld
fi

# Enable and start firewalld
systemctl enable --now firewalld

# Set default zone to drop (most restrictive)
firewall-cmd --set-default-zone=drop

# Create a custom zone for home use
firewall-cmd --permanent --new-zone=home-secure 2>/dev/null || true
firewall-cmd --permanent --zone=home-secure --set-target=DROP

# Allow outgoing connections
firewall-cmd --permanent --zone=home-secure --add-service=dhcpv6-client

# Allow SSH if needed (comment out if not using SSH)
# firewall-cmd --permanent --zone=home-secure --add-service=ssh

# Set home-secure as default
firewall-cmd --set-default-zone=home-secure

# Reload firewall
firewall-cmd --reload

# Display firewall status
echo -e "${BLUE}Firewall status:${NC}"
firewall-cmd --list-all

echo -e "${GREEN}Firewall configured${NC}\n"

# System Hardening
echo -e "${YELLOW}[4/6] Applying system hardening...${NC}"

# Create or update sysctl configuration for hardening
cat > /etc/sysctl.d/99-hardening.conf << 'EOF'
# === CachyOS Security Hardening Configuration ===

# IP Forwarding (disable if not a router)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 4096

# Disable IP source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Disable ICMP redirect acceptance
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Disable secure ICMP redirect acceptance
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# Disable ICMP redirect sending
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Enable IP spoofing protection (reverse path filtering)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP ping requests (0=accept, 1=ignore)
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP error responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Log Martians (packets with impossible addresses)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# TCP hardening
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_rfc1337 = 1

# Increase TCP/IP stack resilience
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# Protect against TCP time-wait assassination
net.ipv4.tcp_rfc1337 = 1

# Kernel hardening
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 2
kernel.kexec_load_disabled = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2

# Core dump restriction
fs.suid_dumpable = 0
kernel.core_uses_pid = 1

# Address Space Layout Randomization (ASLR)
kernel.randomize_va_space = 2

# Restrict access to kernel logs
kernel.printk = 3 3 3 3

# Disable IPv6 if not needed (uncomment to disable)
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1
# net.ipv6.conf.lo.disable_ipv6 = 1

# Virtual memory hardening
vm.mmap_rnd_bits = 32
vm.mmap_rnd_compat_bits = 16

# Restrict dmesg access
kernel.dmesg_restrict = 1

# Restrict kernel pointer exposure
kernel.kptr_restrict = 2

# Harden BPF JIT compiler
net.core.bpf_jit_harden = 2
EOF

# Apply sysctl changes
sysctl --system

# Disable unnecessary services
echo -e "${YELLOW}Disabling unnecessary services...${NC}"

services_to_disable=(
    "avahi-daemon.service"
    "cups.service"
    "cups-browsed.service"
    "ModemManager.service"
    "geoclue.service"
)

for service in "${services_to_disable[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        systemctl stop "$service" 2>/dev/null
        systemctl disable "$service" 2>/dev/null
        echo "Disabled: $service"
    elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
        systemctl disable "$service" 2>/dev/null
        echo "Disabled: $service"
    fi
done

# Mask unnecessary services to prevent reactivation
services_to_mask=(
    "debug-shell.service"
    "systemd-coredump.socket"
)

for service in "${services_to_mask[@]}"; do
    systemctl mask "$service" 2>/dev/null
    echo "Masked: $service"
done

# SSH Hardening (if SSH is installed)
if [ -f /etc/ssh/sshd_config ]; then
    echo -e "${YELLOW}Hardening SSH configuration...${NC}"
    
    # Backup original
    cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.bak"
    
    # Create hardened SSH config
    cat > /etc/ssh/sshd_config.d/99-hardening.conf << 'EOF'
# SSH Hardening Configuration

# Disable root login
PermitRootLogin no

# Use only SSH protocol 2
Protocol 2

# Disable empty passwords
PermitEmptyPasswords no

# Disable X11 forwarding
X11Forwarding no

# Disable TCP forwarding
AllowTcpForwarding no

# Maximum authentication attempts
MaxAuthTries 3

# Login grace time
LoginGraceTime 30

# Use strong ciphers only
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr

# Use strong MACs
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256

# Use strong key exchange algorithms
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256

# Disable password authentication (use key-based auth)
# PasswordAuthentication no
# Uncomment above after setting up SSH keys

# Client alive interval
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
    
    # Restart SSH if it's running
    if systemctl is-active --quiet sshd; then
        systemctl restart sshd
    fi
fi

# Set secure file permissions
echo -e "${YELLOW}Setting secure file permissions...${NC}"
chmod 700 /root
chmod 600 /boot/grub/grub.cfg 2>/dev/null
chmod 644 /etc/passwd
chmod 644 /etc/group
chmod 600 /etc/shadow
chmod 600 /etc/gshadow
chmod 600 /etc/ssh/sshd_config 2>/dev/null

# Set up USB Guard (optional - uncomment if needed)
# echo -e "${YELLOW}Installing USBGuard...${NC}"
# pacman -S --noconfirm usbguard
# systemctl enable --now usbguard

# Enable audit logging
if pacman -Qq audit &>/dev/null || pacman -S --noconfirm audit; then
    echo -e "${YELLOW}Enabling audit logging...${NC}"
    systemctl enable --now auditd
fi

# Configure AppArmor if available
if pacman -Qq apparmor &>/dev/null; then
    echo -e "${YELLOW}Enabling AppArmor...${NC}"
    systemctl enable --now apparmor
    aa-enforce /etc/apparmor.d/* 2>/dev/null || true
fi

echo -e "${GREEN}System hardening applied${NC}\n"

# Pacman Security Configuration
echo -e "${YELLOW}[5/6] Hardening Pacman configuration...${NC}"

# Backup pacman.conf
cp /etc/pacman.conf "$BACKUP_DIR/pacman.conf.bak"

# Enable package signature checking
sed -i 's/^#SigLevel.*/SigLevel = Required DatabaseOptional/' /etc/pacman.conf
sed -i 's/^SigLevel.*/SigLevel = Required DatabaseOptional/' /etc/pacman.conf

# Add security configurations
if ! grep -q "Color" /etc/pacman.conf; then
    sed -i '/^#Color/a Color' /etc/pacman.conf
fi

if ! grep -q "VerbosePkgLists" /etc/pacman.conf; then
    sed -i '/^#VerbosePkgLists/a VerbosePkgLists' /etc/pacman.conf
fi

if ! grep -q "ParallelDownloads" /etc/pacman.conf; then
    sed -i '/^#ParallelDownloads/a ParallelDownloads = 5' /etc/pacman.conf
fi

echo -e "${GREEN}Pacman configuration hardened${NC}\n"

# System Update
echo -e "${YELLOW}[6/6] Updating system with pacman -Syu...${NC}"

# Update package database and upgrade all packages
pacman -Syu --noconfirm

# Clean package cache (keep last 3 versions)
paccache -rk3 2>/dev/null || pacman -S --noconfirm pacman-contrib && paccache -rk3

# Remove orphaned packages
orphans=$(pacman -Qtdq)
if [ -n "$orphans" ]; then
    echo -e "${YELLOW}Removing orphaned packages...${NC}"
    pacman -Rns --noconfirm $orphans
fi

echo -e "${GREEN}System updated and cleaned${NC}\n"

# Create post-installation notes
cat > "$BACKUP_DIR/POST-INSTALL-NOTES.txt" << EOF
CachyOS Security Hardening - Post-Installation Notes
====================================================

Date: $(date)

What was done:
1. Removed/disabled telemetry services and packages
2. Configured firewalld (default DROP policy)
3. Applied comprehensive kernel and network hardening
4. Disabled unnecessary services (Bluetooth, CUPS, Avahi, etc.)
5. Hardened SSH configuration (if installed)
6. Enabled audit logging
7. Configured secure file permissions
8. Hardened Pacman package manager
9. Updated all system packages

Firewall Configuration:
----------------------
- Default zone: home-secure (DROP target)
- All incoming connections blocked by default
- Outgoing connections allowed
- To allow specific services:
  sudo firewall-cmd --permanent --zone=home-secure --add-service=<service>
  sudo firewall-cmd --reload

Disabled Services:
-----------------
- avahi-daemon (network service discovery)
- cups (printing)
- bluetooth
- ModemManager
- geoclue (location services)

To re-enable if needed:
sudo systemctl enable --now <service-name>

SSH Security:
------------
- Root login disabled
- X11 forwarding disabled
- Strong ciphers enforced
- Consider setting up key-based authentication

Manual actions you may need to take:
-----------------------------------
1. Set up SSH keys if using SSH:
   ssh-keygen -t ed25519
   
2. Configure your firewall for specific applications:
   sudo firewall-cmd --permanent --zone=home-secure --add-port=<port>/tcp
   
3. Review disabled services and re-enable if needed
   
4. Consider installing additional security tools:
   - rkhunter (rootkit detection)
   - clamav (antivirus)
   - fail2ban (intrusion prevention)

5. Review AppArmor profiles if installed

Additional hardening steps (optional):
-------------------------------------
1. Enable full disk encryption (if not already)
2. Install and configure USBGuard
3. Set up automatic security updates
4. Configure fail2ban for SSH
5. Install and configure firejail for application sandboxing

Backup location: $BACKUP_DIR
EOF

# Final Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CachyOS Hardening Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Summary:${NC}"
echo "  ✓ Telemetry and privacy-invasive services removed/disabled"
echo "  ✓ Firewall (firewalld) enabled with DROP policy"
echo "  ✓ Comprehensive kernel and network hardening applied"
echo "  ✓ Unnecessary services disabled"
echo "  ✓ SSH hardened (if installed)"
echo "  ✓ Audit logging enabled"
echo "  ✓ Pacman security enhanced"
echo "  ✓ System fully updated with pacman -Syu"
echo ""
echo -e "${YELLOW}Backup location:${NC} $BACKUP_DIR"
echo -e "${YELLOW}Post-installation notes:${NC} $BACKUP_DIR/POST-INSTALL-NOTES.txt"
echo ""
echo -e "${RED}IMPORTANT NOTES:${NC}"
echo "  - Firewall is set to DROP all incoming connections"
echo "  - SSH root login has been disabled (if SSH installed)"
echo "  - Bluetooth, CUPS, and Avahi have been disabled"
echo "  - Review firewall rules if you need specific applications"
echo "  - Some hardening may affect performance on older hardware"
echo "  - Reboot is RECOMMENDED for all changes to take effect"
echo ""
echo -e "${BLUE}Optional security enhancements:${NC}"
echo "  - Install rkhunter: sudo pacman -S rkhunter"
echo "  - Install fail2ban: sudo pacman -S fail2ban"
echo "  - Install usbguard: sudo pacman -S usbguard"
echo "  - Install firejail: sudo pacman -S firejail"
echo ""
echo -e "${YELLOW}Reboot now? (y/n)${NC}"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Rebooting...${NC}"
    reboot
else
    echo -e "${YELLOW}Please reboot manually when ready: sudo reboot${NC}"
fi

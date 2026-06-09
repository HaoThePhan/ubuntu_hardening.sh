#!/bin/bash

# Ubuntu Desktop Privacy & Security Hardening Script
# Run with: sudo bash harden-ubuntu.sh

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Ubuntu Privacy & Security Hardening${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Backup current configuration
echo -e "${YELLOW}[1/6] Creating backup...${NC}"
BACKUP_DIR="/root/ubuntu-hardening-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/sysctl.conf "$BACKUP_DIR/" 2>/dev/null
cp /etc/ssh/sshd_config "$BACKUP_DIR/" 2>/dev/null
echo -e "${GREEN}Backup created at: $BACKUP_DIR${NC}\n"

# Remove Telemetry and Privacy-invasive packages
echo -e "${YELLOW}[2/6] Removing telemetry and privacy-invasive services...${NC}"

# Stop and disable apport (crash reporting)
systemctl stop apport.service 2>/dev/null
systemctl disable apport.service 2>/dev/null
systemctl mask apport.service 2>/dev/null

# Remove popularity-contest
apt-get purge -y popularity-contest 2>/dev/null

# Remove Ubuntu report and whoopsie (error reporting)
apt-get purge -y whoopsie apport apport-symptoms 2>/dev/null

# Disable error reporting
sed -i 's/enabled=1/enabled=0/g' /etc/default/apport 2>/dev/null

# Remove Amazon integration (older Ubuntu versions)
apt-get purge -y ubuntu-web-launchers 2>/dev/null

# Disable online search results in Unity/GNOME
if [ -d /usr/share/glib-2.0/schemas/ ]; then
    cat > /usr/share/glib-2.0/schemas/99-disable-privacy-invasive.gschema.override << EOF
[com.ubuntu.update-notifier]
show-apport-crashes=false

[com.canonical.Unity.Lenses]
remote-content-search='none'

[org.gnome.desktop.privacy]
send-software-usage-stats=false
report-technical-problems=false
EOF
    glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>/dev/null
fi

# Disable apport in kernel
echo "kernel.core_pattern=|/bin/false" >> /etc/sysctl.conf

# Remove canonical-census (data collection)
apt-get purge -y canonical-census 2>/dev/null

echo -e "${GREEN}Telemetry removed${NC}\n"

# Firewall Configuration
echo -e "${YELLOW}[3/6] Configuring firewall (UFW)...${NC}"

# Install UFW if not present
apt-get install -y ufw

# Reset UFW to default
ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH (if needed - comment out if not using SSH)
# ufw allow 22/tcp

# Enable UFW
ufw --force enable

# Display firewall status
ufw status verbose

echo -e "${GREEN}Firewall configured${NC}\n"

# System Hardening
echo -e "${YELLOW}[4/6] Applying system hardening...${NC}"

# Network hardening via sysctl
cat >> /etc/sysctl.conf << EOF

# IP Forwarding (disable if not a router)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Syn flood protection
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

# Enable IP spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP ping requests
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP error responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Log Martians (packets with impossible addresses)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Disable IPv6 (if not needed - comment out if you use IPv6)
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1
# net.ipv6.conf.lo.disable_ipv6 = 1

# TCP hardening
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_rfc1337 = 1

# Kernel hardening
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
kernel.kexec_load_disabled = 1
fs.suid_dumpable = 0
EOF

# Apply sysctl changes
sysctl -p

# Disable unnecessary services
echo -e "${YELLOW}Disabling unnecessary services...${NC}"
services_to_disable=(
    "avahi-daemon.service"
    "cups.service"
    "cups-browsed.service"
    "bluetooth.service"
)

for service in "${services_to_disable[@]}"; do
    systemctl stop "$service" 2>/dev/null
    systemctl disable "$service" 2>/dev/null
    echo "Disabled: $service"
done

# SSH Hardening (if SSH is installed)
if [ -f /etc/ssh/sshd_config ]; then
    echo -e "${YELLOW}Hardening SSH configuration...${NC}"
    
    # Backup original
    cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.bak"
    
    # Apply secure settings
    sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/#PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
    sed -i 's/X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config
    
    # Restart SSH
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
fi

# Set secure file permissions
chmod 700 /root
chmod 600 /boot/grub/grub.cfg 2>/dev/null
chmod 644 /etc/passwd
chmod 644 /etc/group
chmod 600 /etc/shadow
chmod 600 /etc/gshadow

echo -e "${GREEN}System hardening applied${NC}\n"

# Remove unnecessary packages
echo -e "${YELLOW}[5/6] Removing unnecessary packages...${NC}"
apt-get autoremove -y
apt-get autoclean -y
echo -e "${GREEN}Cleanup complete${NC}\n"

# System Update
echo -e "${YELLOW}[6/6] Updating system...${NC}"
apt-get update
apt-get upgrade -y
apt-get dist-upgrade -y
apt-get autoremove -y
apt-get autoclean -y
echo -e "${GREEN}System updated${NC}\n"

# Final Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Hardening Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Summary:${NC}"
echo "  ✓ Telemetry and privacy-invasive services removed"
echo "  ✓ Firewall (UFW) enabled with default deny incoming"
echo "  ✓ Network and kernel hardening applied"
echo "  ✓ Unnecessary services disabled"
echo "  ✓ System updated and cleaned"
echo ""
echo -e "${YELLOW}Backup location:${NC} $BACKUP_DIR"
echo ""
echo -e "${RED}IMPORTANT:${NC}"
echo "  - Review firewall rules if you need specific ports open"
echo "  - SSH root login has been disabled (if SSH installed)"
echo "  - Some services like Bluetooth and Avahi have been disabled"
echo "  - Reboot recommended for all changes to take effect"
echo ""
echo -e "${YELLOW}Reboot now? (y/n)${NC}"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    reboot
fi

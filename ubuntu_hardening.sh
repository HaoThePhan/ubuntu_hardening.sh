#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (sudo)." 
   exit 1
fi

echo "--- Starting Ubuntu Hardening and Telemetry Removal ---"

# 1. REMOVE TELEMETRY & TRACKING
echo "[*] Removing telemetry and error reporting packages..."
# Apport: Error reporting
# Whoopsie: Ubuntu error tracker
# Popularity-contest: Sends anonymous app usage stats
apt-get purge -y apport apport-gtk whoopsie popularity-contest ubuntu-report
# Disable data collection via settings
ubuntu-report send no || true

# 2. HARDENING THE NETWORK (Firewall)
echo "[*] Configuring UFW (Firewall)..."
apt-get install -y ufw
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
# If you need specific ports (e.g., SSH), uncomment the line below:
# ufw allow ssh
ufw --force enable

# 3. KERNEL HARDENING (Sysctl)
echo "[*] Applying kernel security tweaks..."
cat <<EOF > /etc/sysctl.d/99-hardened.conf
# Ignore ICMP broadcast requests (prevents Smurf attacks)
net.ipv4.icmp_echo_ignore_broadcasts = 1
# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
# Block SYN flood attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5
# Log Martians (suspicious packets)
net.ipv4.conf.all.log_martians = 1
# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
EOF
sysctl -p /etc/sysctl.d/99-hardened.conf

# 4. DISABLING UNNECESSARY SERVICES
echo "[*] Disabling unnecessary services..."
# Disable Avahi (Network discovery - can reveal info about your system)
systemctl stop avahi-daemon.service || true
systemctl disable avahi-daemon.service || true
# Disable CUPS (Printing - only disable if you don't use a printer)
# systemctl stop cups.service && systemctl disable cups.service

# 5. SHARED MEMORY HARDENING
echo "[*] Securing /run/shm..."
if ! grep -q "/run/shm" /etc/fstab; then
    echo "none /run/shm tmpfs defaults,ro,nosuid,noexec 0 0" >> /etc/fstab
fi

# 6. SYSTEM UPDATES & CLEANUP
echo "[*] Running system updates and cleanup..."
apt-get update
apt-get full-upgrade -y
apt-get autoremove -y
apt-get autoclean -y

echo "--- Hardening Complete! ---"
echo "It is recommended to reboot your system to apply all changes."

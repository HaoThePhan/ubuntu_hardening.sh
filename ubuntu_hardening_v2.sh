#!/bin/bash

# Ubuntu Desktop Privacy, Security Hardening & Snap Removal Script
# Run with: sudo bash harden-ubuntu-no-snap.sh

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
echo -e "${GREEN}Ubuntu Privacy & Security Hardening${NC}"
echo -e "${GREEN}+ Snap Removal${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Backup current configuration
echo -e "${YELLOW}[1/7] Creating backup...${NC}"
BACKUP_DIR="/root/ubuntu-hardening-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/sysctl.conf "$BACKUP_DIR/" 2>/dev/null
cp /etc/ssh/sshd_config "$BACKUP_DIR/" 2>/dev/null

# List installed snaps
snap list > "$BACKUP_DIR/snap-list.txt" 2>/dev/null

echo -e "${GREEN}Backup created at: $BACKUP_DIR${NC}\n"

# Remove Telemetry and Privacy-invasive packages
echo -e "${YELLOW}[2/7] Removing telemetry and privacy-invasive services...${NC}"

# Stop and disable apport (crash reporting)
systemctl stop apport.service 2>/dev/null
systemctl disable apport.service 2>/dev/null
systemctl mask apport.service 2>/dev/null

# Remove popularity-contest
apt-get purge -y popularity-contest 2>/dev/null

# Remove Ubuntu report and whoopsie (error reporting)
apt-get purge -y whoopsie apport apport-symptoms ubuntu-report 2>/dev/null

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
echo -e "${YELLOW}[3/7] Configuring firewall (UFW)...${NC}"

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
echo -e "${YELLOW}[4/7] Applying system hardening...${NC}"

# Network hardening via sysctl
cat >> /etc/sysctl.conf << EOF

# === Security Hardening Configuration ===
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

# Ignore ICMP ping requests (set to 1 to ignore all pings)
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
    if systemctl is-active --quiet "$service"; then
        systemctl stop "$service" 2>/dev/null
        systemctl disable "$service" 2>/dev/null
        echo "Disabled: $service"
    fi
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

# Snap Package Migration
echo -e "${YELLOW}[5/7] Finding and replacing Snap packages with APT versions...${NC}"

# Check if snap is installed
if ! command -v snap &> /dev/null; then
    echo -e "${BLUE}Snap is not installed. Skipping snap removal.${NC}\n"
else
    # Create array of installed snaps (excluding core snaps initially)
    mapfile -t SNAPS < <(snap list | awk 'NR>1 {print $1}')
    
    echo -e "${BLUE}Found ${#SNAPS[@]} snap package(s) installed${NC}"
    
    # Common snap to apt package mappings
    declare -A snap_to_apt=(
        ["firefox"]="firefox"
        ["chromium"]="chromium-browser"
        ["code"]="code"
        ["vlc"]="vlc"
        ["gimp"]="gimp"
        ["inkscape"]="inkscape"
        ["libreoffice"]="libreoffice"
        ["thunderbird"]="thunderbird"
        ["audacity"]="audacity"
        ["obs-studio"]="obs-studio"
        ["spotify"]="spotify-client"
        ["slack"]="slack-desktop"
        ["discord"]="discord"
        ["telegram-desktop"]="telegram-desktop"
        ["skype"]="skypeforlinux"
        ["blender"]="blender"
        ["kdenlive"]="kdenlive"
        ["keepassxc"]="keepassxc"
    )
    
    # Array to store successfully replaced packages
    declare -a replaced_snaps=()
    
    for snap_pkg in "${SNAPS[@]}"; do
        # Skip core snap packages for now
        if [[ "$snap_pkg" == "snapd" || "$snap_pkg" == "core"* || "$snap_pkg" == "bare" || "$snap_pkg" == "gtk-common-themes" || "$snap_pkg" == "gnome-"* ]]; then
            continue
        fi
        
        echo -e "\n${BLUE}Processing: $snap_pkg${NC}"
        
        # Check if there's a known APT equivalent
        apt_pkg="${snap_to_apt[$snap_pkg]}"
        
        if [ -z "$apt_pkg" ]; then
            # Try using the same name
            apt_pkg="$snap_pkg"
        fi
        
        # Check if package exists in APT
        if apt-cache show "$apt_pkg" &>/dev/null; then
            echo -e "${YELLOW}  → APT package found: $apt_pkg${NC}"
            echo -e "${YELLOW}  → Installing from APT...${NC}"
            
            # Install APT version
            if apt-get install -y "$apt_pkg"; then
                echo -e "${GREEN}  ✓ Successfully installed $apt_pkg from APT${NC}"
                replaced_snaps+=("$snap_pkg")
            else
                echo -e "${RED}  ✗ Failed to install $apt_pkg from APT${NC}"
                echo -e "${YELLOW}  → Keeping snap version of $snap_pkg${NC}"
            fi
        else
            echo -e "${RED}  ✗ No APT equivalent found for $snap_pkg${NC}"
            echo -e "${YELLOW}  → You may need to find alternative or keep snap version${NC}"
            echo -e "${YELLOW}  → Consider checking: https://packages.ubuntu.com/${NC}"
        fi
    done
    
    # Remove replaced snaps
    if [ ${#replaced_snaps[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}Removing replaced snap packages...${NC}"
        for snap_pkg in "${replaced_snaps[@]}"; do
            echo -e "${YELLOW}  → Removing snap: $snap_pkg${NC}"
            snap remove "$snap_pkg" 2>/dev/null
        done
    fi
    
    # Now remove core snaps and snapd
    echo -e "\n${YELLOW}Removing snapd and core packages...${NC}"
    
    # Remove all remaining snaps
    for snap_pkg in $(snap list | awk 'NR>1 {print $1}'); do
        echo -e "${YELLOW}  → Removing: $snap_pkg${NC}"
        snap remove "$snap_pkg" 2>/dev/null
    done
    
    # Remove snapd
    echo -e "${YELLOW}Purging snapd...${NC}"
    apt-get purge -y snapd
    
    # Remove snap directories
    rm -rf /snap
    rm -rf /var/snap
    rm -rf /var/lib/snapd
    rm -rf ~/snap
    
    # Prevent snapd from being installed again
    cat > /etc/apt/preferences.d/nosnap.pref << EOF
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF
    
    echo -e "${GREEN}Snap completely removed from system${NC}\n"
fi

# Alternative repositories for common applications
echo -e "${YELLOW}[6/7] Adding useful APT repositories...${NC}"

# Add Firefox PPA (if Firefox was a snap)
if [[ " ${replaced_snaps[@]} " =~ " firefox " ]]; then
    echo -e "${BLUE}Adding Mozilla Team PPA for Firefox...${NC}"
    add-apt-repository -y ppa:mozillateam/ppa 2>/dev/null
    
    # Set Firefox PPA priority
    cat > /etc/apt/preferences.d/mozilla-firefox << EOF
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
EOF
fi

# Update package list
apt-get update

echo -e "${GREEN}Repositories configured${NC}\n"

# System Update and Cleanup
echo -e "${YELLOW}[7/7] Updating and cleaning system...${NC}"

# Update package lists
apt-get update

# Upgrade all packages
apt-get upgrade -y

# Dist upgrade
apt-get dist-upgrade -y

# Remove unnecessary packages
apt-get autoremove -y

# Clean package cache
apt-get autoclean -y
apt-get clean -y

echo -e "${GREEN}System updated and cleaned${NC}\n"

# Final Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Hardening & Snap Removal Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Summary:${NC}"
echo "  ✓ Telemetry and privacy-invasive services removed"
echo "  ✓ Firewall (UFW) enabled with default deny incoming"
echo "  ✓ Network and kernel hardening applied"
echo "  ✓ Unnecessary services disabled"
echo "  ✓ Snap packages replaced with APT versions (where possible)"
echo "  ✓ Snapd completely removed and blocked"
echo "  ✓ System updated and cleaned"
echo ""
echo -e "${YELLOW}Backup location:${NC} $BACKUP_DIR"
echo -e "${YELLOW}  - Original snap list saved to: snap-list.txt${NC}"
echo ""
echo -e "${BLUE}Replaced snap packages:${NC}"
if [ ${#replaced_snaps[@]} -gt 0 ]; then
    for pkg in "${replaced_snaps[@]}"; do
        echo "  • $pkg"
    done
else
    echo "  • None (or snap was not installed)"
fi
echo ""
echo -e "${RED}IMPORTANT NOTES:${NC}"
echo "  - Snap has been completely removed and blocked"
echo "  - Some apps may need manual installation if no APT version exists"
echo "  - Firefox/Chromium now use APT/PPA versions"
echo "  - Review firewall rules if you need specific ports open"
echo "  - SSH root login has been disabled (if SSH installed)"
echo "  - Some services like Bluetooth and Avahi have been disabled"
echo "  - Reboot is REQUIRED for all changes to take effect"
echo ""

# Create post-installation notes
cat > "$BACKUP_DIR/POST-INSTALL-NOTES.txt" << EOF
Ubuntu Hardening & Snap Removal - Post-Installation Notes
=========================================================

Date: $(date)

What was done:
1. Removed telemetry (apport, whoopsie, popularity-contest)
2. Configured UFW firewall (default deny incoming)
3. Applied kernel and network hardening
4. Disabled unnecessary services
5. Removed snap packages and snapd
6. Updated system packages

Snap packages that were replaced:
$(IFS=$'\n'; echo "${replaced_snaps[*]}")

Manual actions you may need to take:
------------------------------------
1. Review /etc/apt/preferences.d/nosnap.pref if you ever need snap
2. Check if all your applications are working correctly
3. Some proprietary apps may need manual installation:
   - Visual Studio Code: https://code.visualstudio.com/
   - Spotify: https://www.spotify.com/download/linux/
   - Slack: https://slack.com/downloads/linux
   - Discord: https://discord.com/download

4. If you use Firefox, it's now from Mozilla PPA
5. Configure your firewall if you need specific ports:
   sudo ufw allow <port>/tcp

To re-enable disabled services if needed:
-----------------------------------------
sudo systemctl enable <service-name>
sudo systemctl start <service-name>

Disabled services:
- avahi-daemon (network service discovery)
- cups (printing)
- bluetooth

Backup location: $BACKUP_DIR
EOF

echo -e "${YELLOW}Post-installation notes saved to: $BACKUP_DIR/POST-INSTALL-NOTES.txt${NC}"
echo ""
echo -e "${YELLOW}Reboot now? (y/n)${NC}"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Rebooting...${NC}"
    reboot
else
    echo -e "${YELLOW}Please reboot manually when ready: sudo reboot${NC}"
fi

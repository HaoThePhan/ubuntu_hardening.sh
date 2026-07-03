#!/bin/bash
#Check if the laptop is running on AC power
if [ -d /sys/class/power_supply ]; then
  #look for any AC adapter that is online(1 = plugged in)
  if ! grep -q "^1$" /sys/class/power_supply/*/online 2>/dev/null; then
    echo "System is running on battery. Aborting Maintenance to save power"
    exit 0
  fi
fi

echo "AC power detected. Starting system maintenance..."
#Run the update and cleanup chain
apt update
apt upgrade -y
apt autoremove
apt autoclean
flatpak update -y
flatpak uninstall --unused -y
journalctl --vacuum-time=14d

echo "Maintenance Complete!"

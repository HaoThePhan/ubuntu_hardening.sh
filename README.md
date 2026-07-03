# ubuntu_hardening.sh
remove ubuntu telemetry, close unnecessary port and install necessary maintenance.

method: Systemd Timers using unattended-upgrades
#to check if it is active or install it, run:
sudo apt install unattended-upgrades

step 1: Create the maintenance script

sudo nano /usr/local/bin/system-maintenance.sh

#pass the script system-maintenance.sh to the file
#after that
sudo chmod +x /usr/local/bin/system-maintenance.sh

step 2: Create the Systemd service

sudo nano /etc/systemd/system/system-maintenance.service
#pass the script system-maintenance.service in the file
step 3: Create the Weekly Timer

sudo nano /etc/systemd/system/system-maintenance.timer
#pass the script system-maintenance.timer in the file

Step 4: Enable and test
#Reload systemd to detect the new files
sudo systemctl daemon-reload

#Enable and start the timer
sudo systemctl enable --now system-maintenance.timer
  - to check the status of timer ( and see when it is scheduled to run next):
systemctl list-timers --all| grep maintenance
  - to manually test the script (it will output the text so you can see it working)
sudo /usr/local/bin/system-maintenance.sh

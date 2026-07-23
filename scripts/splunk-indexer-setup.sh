#!/bin/bash
# Reference setup script - SPLK01 Splunk Enterprise indexer
# Not fully unattended: Splunk's first-run license acceptance and admin
# account creation are interactive and cannot be fully scripted with
# --seed-passwd alone on this version. Documented here for repeatability
# and as README/interview reference material, not a one-shot executable.

# 1. Update system
sudo apt update && sudo apt upgrade -y

# 2. Set timezone to match the domain/host (important for log correlation
#    across DC01/FS01/SPLK01 - see docs/Troubleshooting-Log.md)
sudo timedatectl set-timezone America/Edmonton

# 3. Download Splunk Enterprise .deb (get current link from splunk.com/download)
wget -O splunk.deb "PASTE_CURRENT_DOWNLOAD_LINK_HERE"

# 4. Install
sudo dpkg -i splunk*.deb

# 5. Start Splunk - interactive: accept license (y), then create an admin
#    username and password when prompted.
#    --run-as-root is REQUIRED here: without it, this Splunk version prints
#    a deprecation warning and silently exits, with no error and no
#    indication anything failed. See docs/Troubleshooting-Log.md.
sudo /opt/splunk/bin/splunk start --accept-license --run-as-root

# 6. Enable Splunk to start automatically on boot
sudo /opt/splunk/bin/splunk enable boot-start

# 7. Verify it's running
sudo /opt/splunk/bin/splunk status

# 8. Any future restart also requires --run-as-root explicitly:
sudo /opt/splunk/bin/splunk restart --run-as-root

# 9. Confirm the receiving port is actually bound. Splunk Web's "Configure
#    receiving" page can show port 9997 as Enabled while splunkd has not
#    actually opened the socket until a full restart occurs - this caught
#    us once during the build. Confirm directly at the OS level:
sudo ss -tulnp | grep 9997
# Expect a line showing splunkd listening on 0.0.0.0:9997

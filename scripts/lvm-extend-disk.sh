#!/bin/bash
# Reference: extending SPLK01's root filesystem to use previously
# unallocated LVM space. The VM was created with a 40GB virtual disk,
# but only ~19GB was ever allocated to the root logical volume, leaving
# the rest unused and sitting in the volume group. This surfaced when
# Splunk searches began failing due to hitting the 5000MB free-space
# safety threshold. See docs/Troubleshooting-Log.md for the full story.

# 1. Confirm there's actually unused free space in the volume group
sudo vgs
# Look at the VFree column

# 2. Extend the logical volume to use all remaining free space
sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv

# 3. Resize the filesystem to actually fill the newly extended volume
#    (extending the LV alone does not grow the filesystem on top of it)
sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv

# 4. Verify
df -h
# The / line should now show close to the full disk size, with much
# more free space available.

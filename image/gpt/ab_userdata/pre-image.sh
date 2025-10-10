#!/bin/bash

set -eu

fs=$1
genimg_in=$2

[[ -d "$fs" ]] || exit 0


# Load pre-defined UUIDs
. ${genimg_in}/img_uuids


# Set up the partition layout for tryboot support. Partition numbering
# relates directly to the layout in genimage.cfg.in

cat << EOF > "${genimg_in}/autoboot.txt"
[all]
tryboot_a_b=1
boot_partition=2
[tryboot]
boot_partition=3
EOF


# Write genimage template
cat genimage.cfg.in | sed \
   -e "s|<IMAGE_DIR>|$IGconf_image_outputdir|g" \
   -e "s|<IMAGE_NAME>|$IGconf_image_name|g" \
   -e "s|<IMAGE_SUFFIX>|$IGconf_image_suffix|g" \
   -e "s|<BOOT_SIZE>|$IGconf_image_boot_part_size|g" \
   -e "s|<SYSTEM_SIZE>|$IGconf_image_system_part_size|g" \
   -e "s|<DATA_SIZE>|$IGconf_image_data_part_size|g" \
   -e "s|<SECTOR_SIZE>|$IGconf_device_sector_size|g" \
   -e "s|<SLOTP>|'$(readlink -ef slot-post-process.sh)'|g" \
   -e "s|<MKE2FSCONF>|'$(readlink -ef mke2fs.conf)'|g" \
   -e "s|<BOOT_LABEL>|$BOOT_LABEL|g" \
   -e "s|<SYSTEM_UUID>|$SYSTEM_UUID|g" \
   > ${genimg_in}/genimage.cfg

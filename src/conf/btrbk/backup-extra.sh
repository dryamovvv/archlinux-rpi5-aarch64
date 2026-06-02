#!/bin/bash
set -e

BACKUP_DIR=/mnt/backup/rpi5

if [ ! -d "$BACKUP_DIR" ]; then
	echo "ERROR: $BACKUP_DIR not mounted"
	exit 1
fi

# Find root LUKS device dynamically (works on SD/mmcblk0 and NVMe)
LUKS_PART=$(dmsetup deps cryptroot -o blkdevname | tail -1 | awk '{print $NF}' | tr -d '()')
LUKS_PART="/dev/$LUKS_PART"

echo "=== Backup LUKS header: $LUKS_PART ==="
rm -f "$BACKUP_DIR/luks-header-$(basename "$LUKS_PART").bin"
cryptsetup luksHeaderBackup "$LUKS_PART" \
	--header-backup-file "$BACKUP_DIR/luks-header-$(basename "$LUKS_PART").bin"
echo "OK"

echo "=== Backup ESP (boot) ==="
mkdir -p "$BACKUP_DIR/boot"
tar -cf - -C /boot . | tar -xf - -C "$BACKUP_DIR/boot/"
echo "OK"

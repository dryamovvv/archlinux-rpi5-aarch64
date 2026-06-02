#!/bin/bash

BACKUP_DEV=""
BACKUP_PART=""
BACKUP_MOUNT="/mnt/backup"
KEYFILE="/root/backup-usb.key"
SERVICE_FILE="/etc/systemd/system/backup-usb.service"
BTRBK_CONF="/etc/btrbk/btrbk.conf"
BTRBK_TIMER="btrbk.timer"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

confirm() {
	local prompt="$1"
	local yn
	printf '%s (y/N) ' "$prompt"
	read -r yn
	case "${yn,,}" in
	y | yes) return 0 ;;
	*) return 1 ;;
	esac
}

find_backup_drive() {
	info "Searching for USB backup drives..."

	for dev in $(lsblk -ndo NAME,TYPE | awk '$2=="disk"{print $1}'); do
		[[ "$dev" == zram* ]] && continue
		[[ "$dev" == mmcblk* ]] && continue
		[[ "$dev" == nvme* ]] && continue

		local fullpath="/dev/$dev"
		local size=$(lsblk -ndo SIZE "$fullpath" 2>/dev/null)

		if [[ -n "$size" ]]; then
			info "Found removable drive: $fullpath ($size)"
			BACKUP_DEV="$fullpath"
			BACKUP_PART=$(lsblk -ndo NAME "$fullpath" | tail -1)
			BACKUP_PART="/dev/$BACKUP_PART"
			return 0
		fi
	done

	error "No USB backup drive found."
	warn "Connect a USB SSD/HDD and run this script again."
	exit 1
}

check_existing() {
	if cryptsetup isLuks "$BACKUP_PART" 2>/dev/null; then
		info "$BACKUP_PART is already LUKS-encrypted"

		if cryptsetup open --test-passphrase --key-file="$KEYFILE" "$BACKUP_PART" 2>/dev/null; then
			info "Existing keyfile works"
		elif cryptsetup open --test-passphrase --tries=1 "$BACKUP_PART" 2>/dev/null <<<""; then
			info "User password works"
		else
			warn "No known key can open $BACKUP_PART"
			info "You will be asked for the existing passphrase later."
		fi

		# Try to open and check if already configured
		cryptsetup close backup-usb 2>/dev/null || true
		if cryptsetup open "$BACKUP_PART" backup-usb 2>/dev/null; then
			if mount /dev/mapper/backup-usb "$BACKUP_MOUNT" 2>/dev/null; then
				if [[ -d "$BACKUP_MOUNT/rpi5" ]]; then
					info "Backup drive already has rpi5 data directory"
					umount "$BACKUP_MOUNT"
					cryptsetup close backup-usb
					return 0
				fi
				umount "$BACKUP_MOUNT"
			fi
			cryptsetup close backup-usb
		fi

		return 1
	fi

	error "$BACKUP_PART is NOT encrypted with LUKS."
	local fstype=$(lsblk -ndo FSTYPE "$BACKUP_PART" 2>/dev/null || echo "unknown")
	warn "Current filesystem: ${fstype:-none}"

	local has_data=$(lsblk -ndo FSAVAIL "$BACKUP_PART" 2>/dev/null)
	if [[ -z "$has_data" || "$has_data" == "0" ]]; then
		info "Partition appears empty or unformatted"
		confirm "Format $BACKUP_PART with LUKS? All data will be lost!" "N" && return 2
	else
		warn "Partition HAS DATA: $(lsblk -ndo FSUSED "$BACKUP_PART") used"
		confirm "DESTROY all data on $BACKUP_PART with LUKS format?" "N" && return 2
	fi

	return 1
}

format_drive() {
	info "Formatting $BACKUP_PART with LUKS2..."

	info "Enter LUKS passphrase for the backup drive:"
	if ! cryptsetup luksFormat --type luks2 "$BACKUP_PART"; then
		error "LUKS format failed"
		exit 1
	fi

	info "LUKS format complete"
	return 0
}

setup_keyfile() {
	if [[ -f "$KEYFILE" ]]; then
		info "Keyfile $KEYFILE already exists"
		cryptsetup luksAddKey --force-password "$BACKUP_PART" "$KEYFILE" 2>&1 ||
			warn "Keyfile already in LUKS or failed to add"
	else
		info "Generating keyfile: $KEYFILE"
		dd if=/dev/urandom of="$KEYFILE" bs=64 count=1 2>/dev/null
		chmod 0400 "$KEYFILE"
		cryptsetup luksAddKey "$BACKUP_PART" "$KEYFILE"
		info "Keyfile added to LUKS"
	fi
}

setup_user_password() {
	echo ""
	info "Set a user password for the backup drive (separate from system password)"
	info "You can use this instead of the keyfile to unlock the drive manually."
	echo ""

	if cryptsetup luksChangeKey --force-password "$BACKUP_PART" 2>&1 | head -3; then
		info "User password set"
	else
		cryptsetup luksAddKey "$BACKUP_PART" 2>&1
		info "User password added"
	fi
}

setup_service() {
	local device_by_id=""

	# Use PARTUUID if available, otherwise UUID
	local partuuid=$(blkid -s PARTUUID -o value "$BACKUP_PART" 2>/dev/null || true)
	if [[ -n "$partuuid" ]]; then
		device_by_id="/dev/disk/by-partuuid/$partuuid"
	else
		local uuid=$(blkid -s UUID -o value "$BACKUP_PART" 2>/dev/null || true)
		device_by_id="/dev/disk/by-uuid/$uuid"
	fi

	info "Writing $SERVICE_FILE"
	mkdir -p /mnt/btrfs
	cat >"$SERVICE_FILE" <<SERVICEEOF
[Unit]
Description=Encrypted USB backup mount
After=local-fs.target
Before=btrbk.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/usr/bin/mkdir -p /mnt/btrfs
ExecStartPre=/usr/bin/mount -o subvolid=5 /dev/mapper/cryptroot /mnt/btrfs
ExecStartPre=/usr/sbin/cryptsetup open --key-file=$KEYFILE $device_by_id backup-usb
ExecStart=/usr/bin/mount -o noatime,compress=zstd /dev/mapper/backup-usb $BACKUP_MOUNT
ExecStop=/usr/bin/umount $BACKUP_MOUNT
ExecStopPost=/usr/sbin/cryptsetup close backup-usb
ExecStopPost=/usr/bin/umount /mnt/btrfs

[Install]
WantedBy=multi-user.target
SERVICEEOF

	systemctl daemon-reload
	systemctl enable backup-usb.service
	info "backup-usb.service enabled"
}

setup_btrfs() {
	mkdir -p "$BACKUP_MOUNT"
	if cryptsetup open "$BACKUP_PART" backup-usb 2>/dev/null; then
		if ! blkid /dev/mapper/backup-usb 2>/dev/null | grep -q btrfs; then
			info "Creating btrfs on /dev/mapper/backup-usb (label: backup)"
			mkfs.btrfs -f -L backup /dev/mapper/backup-usb
		fi

		mount /dev/mapper/backup-usb "$BACKUP_MOUNT"
		mkdir -p "$BACKUP_MOUNT/rpi5"
		info "Backup directory ready: $BACKUP_MOUNT/rpi5"
		umount "$BACKUP_MOUNT"
		cryptsetup close backup-usb
	else
		error "Failed to open LUKS device"
		exit 1
	fi
}

enable_timer() {
	systemctl enable --now "$BTRBK_TIMER" 2>/dev/null || {
		systemctl enable "$BTRBK_TIMER"
		info "btrbk.timer enabled (will start on next boot)"
	}
	info "btrbk.timer enabled"
}

verify() {
	info "Verifying setup..."
	systemctl start backup-usb.service
	systemctl is-active backup-usb.service >/dev/null || {
		error "backup-usb.service failed"
		systemctl status backup-usb.service --no-pager
		systemctl stop backup-usb.service 2>/dev/null || true
		exit 1
	}

	btrbk run 2>&1 || {
		error "btrbk run failed"
		systemctl stop backup-usb.service 2>/dev/null || true
		exit 1
	}

	info "Backup verified successfully"
	info "Data stored in: $BACKUP_MOUNT/rpi5/"

	systemctl stop backup-usb.service 2>/dev/null || true
}

# --- Main ---
echo ""
echo "====================================="
echo " RPi5 Arch Linux Backup Setup"
echo "====================================="
echo ""

[[ $EUID -eq 0 ]] || {
	error "Run as root"
	exit 1
}

# Check dependencies
for cmd in cryptsetup btrfs systemctl btrbk; do
	command -v "$cmd" >/dev/null 2>&1 || {
		error "$cmd not found. Install it: pacman -S $cmd"
		exit 1
	}
done

find_backup_drive

echo ""
info "Target drive: $BACKUP_DEV"
info "Partition:    $BACKUP_PART"
echo ""

check_existing
result=$?

case $result in
0)
	info "Backup drive already configured"
	confirm "Re-run setup to refresh keyfile and services?" "N" || exit 0
	setup_keyfile
	setup_service
	enable_timer
	;;
2)
	info "Formatting new backup drive..."
	format_drive
	setup_keyfile
	setup_user_password
	setup_btrfs
	setup_service
	enable_timer
	;;
*)
	error "Cannot proceed with $BACKUP_PART in its current state"
	exit 1
	;;
esac

verify

echo ""
info "====================================="
info "Backup setup complete!"
info "====================================="
info "Backup runs: daily at 00:00 via btrbk.timer"
info "LUKS header: $BACKUP_MOUNT/rpi5/luks-header-*"
info "Manual run:  systemctl start backup-usb.service && btrbk run"
echo ""

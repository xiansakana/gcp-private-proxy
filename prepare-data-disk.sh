#!/bin/bash
set -euo pipefail
disk=/dev/disk/by-id/google-private-proxy-data
test -b "$disk"
device=$(readlink -f "$disk")
test "$(lsblk -bdn -o SIZE "$device" | xargs)" = 214748364800
test "$(lsblk -nr -o NAME "$device" | wc -l)" = 1
test -z "$(lsblk -dn -o MOUNTPOINTS "$device")"
filesystem=$(blkid -s TYPE -o value "$device" || true)
if [ -z "$filesystem" ]; then
  signatures=$(wipefs -n --noheadings --output TYPE "$device")
  test -z "$signatures"
  mkfs.ext4 -m 1 -L service-data "$device"
else
  test "$filesystem" = ext4
  test "$(blkid -s LABEL -o value "$device")" = service-data
fi
uuid=$(blkid -s UUID -o value "$device")
install -d -m 755 /srv/data
cp -a /etc/fstab "$(mktemp /etc/fstab.before-service-data.XXXXXX)"
if ! grep -q "UUID=$uuid " /etc/fstab; then
  printf 'UUID=%s /srv/data ext4 defaults,nofail 0 2\n' "$uuid" >> /etc/fstab
fi
systemctl daemon-reload
findmnt --verify --verbose
mount /srv/data
install -d -m 755 /srv/data/containers /srv/data/databases
touch /srv/data/.write-test
sync /srv/data/.write-test
unlink /srv/data/.write-test
findmnt /srv/data
df -h / /srv/data
free -h
nproc
systemctl is-active sing-box

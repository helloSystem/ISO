#!/bin/sh

PATH="/rescue"

#echo "==> Remount rootfs as read-write"
mount -u -w /

#echo "==> Make mountpoints"
mkdir -p /cdrom /union /usr

#echo "==> Mount cdrom"
mount_cd9660 /dev/iso9660/FURYBSD /cdrom

mdmfs -P -F /cdrom/data/usr.uzip -o ro md.uzip /usr

#echo "==> Mount swap-based memdisk"
mdmfs -s 512m md /union || exit 1 
mount -t unionfs /union /usr

kenv init_shell="/bin/sh"
exit 0

#!/rescue/sh

PATH="/rescue"

if [ "`ps -o command 1 | tail -n 1 | ( read c o; echo ${o} )`" = "-s" ]; then
	echo "==> Running in single-user mode"
	SINGLE_USER="true"
fi

if [ "$SINGLE_USER" = "true" ]; then
	echo "Starting interactive shell before doing anything ..."
	sh
fi

echo "==> Remount rootfs as read-write"
mount -u -w /

echo "==> Make mountpoints"
mkdir -p /cdrom
mkdir -p /sysroot
mkdir -p /memdisk

echo "Waiting for FURYBSD media to initialize"
while : ; do
    [ -e "/dev/iso9660/FURYBSD" ] && echo "found /dev/iso9660/FURYBSD" && break
    sleep 1
done

echo "==> Mount /cdrom"
mount_cd9660 /dev/iso9660/FURYBSD /cdrom

echo "==> Mount /sysroot"
mdmfs -P -F /cdrom/data/system.uzip -o ro md.uzip /sysroot # FIXME: This does not seem to work; why?

if [ "$SINGLE_USER" = "true" ]; then
	echo -n "Enter memdisk size used for read-write access in the live system: "
	read MEMDISK_SIZE
else
	MEMDISK_SIZE="2048"
fi

echo "==> Mount unionfs"
mdmfs -s "${MEMDISK_SIZE}m" md /memdisk || exit 1
mount -t unionfs /memdisk /sysroot

echo "==> Change into /sysroot"
mount -t devfs devfs /sysroot/dev
chroot /sysroot /usr/local/bin/furybsd-init-helper

if [ "$SINGLE_USER" = "true" ]; then
	echo "Starting interactive shell after chroot ..."
	sh
fi

kenv init_shell="/rescue/sh"
exit 0

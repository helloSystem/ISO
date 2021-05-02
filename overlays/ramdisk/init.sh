#!/rescue/sh

PATH="/rescue"

if [ "`ps -o command 1 | tail -n 1 | ( read c o; echo ${o} )`" = "-s" ]; then
	echo "==> Running in single-user mode"
	SINGLE_USER="true"
	kenv boot_mute="NO"
fi

if [ "`ps -o command 1 | tail -n 1 | ( read c o; echo ${o} )`" = "-v" ]; then
	echo "==> Running in verbose mode"
	kenv boot_mute="NO"
fi

# Silence messages if boot_mute="YES" is set
if [ "$(kenv boot_mute)" = "YES" ] ; then
      exec 1>>/dev/null 2>&1
fi

set -x

echo "==> Ramdisk /init.sh running"

echo "==> Remount rootfs as read-write"
mount -u -w /

echo "==> Make mountpoints"
mkdir -p /cdrom /memdisk /sysroot

echo "Waiting for Live media to appear"
while : ; do
    [ -e "/dev/iso9660/LIVE" ] && echo "found /dev/iso9660/LIVE" && break
    sleep 1
done

echo "==> Mount cdrom"
mount_cd9660 -o ro /dev/iso9660/LIVE /cdrom

if [ "$SINGLE_USER" = "true" ]; then
        echo "Starting interactive shell in temporary rootfs ..."
        exit 0
fi

echo "==> Preparing r/o device (md1)"
mdconfig -a -t vnode -o readonly -f /cdrom/data/system.uzip -u 1
ls -lh /dev/md1*

echo "==> Mount swap-based memdisk (md2)"
# Make a swap-based memdisk (md2) with the exact same size as system.uzip
x=$(cat /cdrom/data/system.bytes)
mdconfig -a -t swap -s ${x}b -u 2 >/dev/null 2>/dev/null # Note the 'b' suffix to the -s option
ls -lh /dev/md2*

echo "==> Combine r/o (md1.uzip) and r/w (md2) devices using geom_rowr"
LD_LIBRARY_PATH=/lib GEOM_LIBRARY_PATH=/cdrom/lib/geom /sbin/geom rowr create rowr0 md1.uzip md2 || /sbin/geom rowr help

echo "==> Mounting combined device (/dev/rowr0) at /sysroot"
ls -lh /dev/rowr0
mount /dev/rowr0 /sysroot || echo "Could not mount /dev/rowr0 to /sysroot" >/dev/tty
ls -lh /sysroot/

echo "==> Mount /sysroot/sysroot/boot"
# https://github.com/helloSystem/ISO/issues/4#issuecomment-800636914
mkdir -p /sysroot/sysroot/boot
mount -t nullfs /sysroot/boot /sysroot/sysroot/boot

echo "==> Change into /sysroot"
mount -t devfs devfs /sysroot/dev
chroot /sysroot /usr/local/bin/furybsd-init-helper

if [ "$SINGLE_USER" = "true" ]; then
	echo "Starting interactive shell after chroot ..."
	sh
fi

kenv init_path="/rescue/init"
kenv init_shell="/rescue/sh"
kenv init_script="/init.sh"
kenv init_chroot="/sysroot"

echo "==> Set kernel module path for chroot"
sysctl kern.module_path=/sysroot/boot/kernel

echo "==> Exit ramdisk init.sh"
exit 0

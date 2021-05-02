#!/bin/sh

# Exit on errors
set -e

# Determine the version of the running host system.
# Building ISOs for other major versions than the running host system
# is not supported and results in broken images anyway
version=$(uname -r | cut -d "-" -f 1-2) # "12.2-RELEASE" or "13.0-CURRENT"

if [ "${version}" = "13.0-CURRENT" ] ; then
  # version="13.0-RC3"
  version="13.0-RELEASE"
fi

VER=$(uname -r | cut -d "-" -f 1) # "12.2" or "13.0"
MAJOR=$(uname -r | cut -d "." -f 1) # "12" or "13"

# Dwnload from either https://download.freebsd.org/ftp/releases/
#                  or https://download.freebsd.org/ftp/snapshots/
VERSIONSUFFIX=$(uname -r | cut -d "-" -f 2) # "RELEASE" or "CURRENT"
FTPDIRECTORY="releases" # "releases" or "snapshots"
if [ "${VERSIONSUFFIX}" = "CURRENT" ] ; then
  FTPDIRECTORY="snapshots"
fi
# RCs are in the 'releases' ftp directory; hence check if $VERSIONSUFFIX begins with 'RC' https://serverfault.com/a/252406
if [ "${VERSIONSUFFIX#RC}"x = "${VERSIONSUFFIX}x" ]  ; then
  FTPDIRECTORY="releases"
fi

echo "${FTPDIRECTORY}"

# pkgset="branches/2020Q1" # TODO: Use it
desktop=$1
tag=$2
export cwd=$(realpath | sed 's|/scripts||g')
workdir="/usr/local"
livecd="${workdir}/furybsd"
if [ -z "${arch}" ] ; then
  arch=amd64
fi
cache="${livecd}/${arch}/cache"
base="${cache}/${version}/base"
export packages="${cache}/packages"
iso="${livecd}/iso"
  if [ -n "$CIRRUS_CI" ] ; then
    # On Cirrus CI ${livecd} is in tmpfs for speed reasons
    # and tends to run out of space. Writing the final ISO
    # to non-tmpfs should be an acceptable compromise
    iso="${CIRRUS_WORKING_DIR}/artifacts"
  fi
export uzip="${livecd}/uzip"
export cdroot="${livecd}/cdroot"
ramdisk_root="${cdroot}/data/ramdisk"
vol="furybsd"
label="LIVE"
export DISTRIBUTIONS="kernel.txz base.txz"

# Only run as superuser
if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

# Make sure git is installed
# We only need this in case we decide to pull in ingredients from
# other git repositories; this is currently not the case
# if [ ! -f "/usr/local/bin/git" ] ; then
#   echo "Git is required"
#   echo "Please install it with pkg install git or pkg install git-lite first"
#   exit 1
# fi

if [ -z "${desktop}" ] ; then
  export desktop=xfce
fi
edition=$(echo $desktop | tr '[:lower:]' '[:upper:]')
export edition
if [ ! -f "${cwd}/settings/packages.${desktop}" ] ; then
  echo "${cwd}/settings/packages.${desktop} is missing, exiting"
  exit 1
fi

# Get the version tag
if [ -z "$2" ] ; then
  rm /usr/local/furybsd/tag >/dev/null 2>/dev/null || true
  export vol="${VER}"
else
  rm /usr/local/furybsd/version >/dev/null 2>/dev/null || true
  echo "${2}" > /usr/local/furybsd/tag
  export vol="${VER}-${tag}"
fi

# Get the short git SHA
SHA=$(echo ${CIRRUS_CHANGE_IN_REPO}| cut -c1-7)

# The environment variable BUILDNUMBER may have been set; if so, use it
if [ ! -z "${BUILDNUMBER}" ] ; then
  isopath="${iso}/${desktop}-${BUILDNUMBER}-${vol}-${arch}.iso"
elif [ ! -z "${SHA}" ] ; then
  isopath="${iso}/${desktop}-${SHA}-${vol}-${arch}.iso"
else
  isopath="${iso}/${desktop}-${vol}-${arch}.iso"
fi

# For helloSystem, we are using a different naming scheme for the ISOS
if [ "${desktop}" = "hello" ] ; then
  if [ -f overlays/uzip/hello/manifest ] ; then
    HELLO_VERSION=$(grep "^version:" overlays/uzip/hello/manifest | xargs | cut -d " " -f 2 | cut -d "_" -f 1)
    # If we are building hello, then set version number of the 'hello' transient package
    # based on environment variable set e.g., by Cirrus CI
    if [ ! -z $BUILDNUMBER ] ; then
      echo "Injecting $BUILDNUMBER" into manifest
      sed -i -e 's|\(^version:       .*_\).*$|\1'$BUILDNUMBER'|g' "${cwd}/overlays/uzip/hello/manifest"
      rm "${cwd}/overlays/uzip/hello/manifest-e"
      cat "${cwd}/overlays/uzip/hello/manifest"
      isopath="${iso}/${desktop}-${HELLO_VERSION}_${BUILDNUMBER}-FreeBSD-${VER}-${arch}.iso"
    else
      isopath="${iso}/${desktop}-${HELLO_VERSION}_git${SHA}-FreeBSD-${VER}-${arch}.iso"
    fi
  fi
fi

cleanup()
{
  if [ -n "$CIRRUS_CI" ] ; then
    # On CI systems there is no reason to clean up which takes time
    return 0
  else
    umount ${uzip}/var/cache/pkg >/dev/null 2>/dev/null || true
    umount ${uzip}/dev >/dev/null 2>/dev/null || true
    if [ -d "${livecd}" ] ;then
      chflags -R noschg ${uzip} ${cdroot} >/dev/null 2>/dev/null || true
      rm -rf ${uzip} ${cdroot} >/dev/null 2>/dev/null || true
    fi
    rm ${livecd}/pool.img >/dev/null 2>/dev/null || true
    rm -rf ${cdroot} >/dev/null 2>/dev/null || true
  fi
}

workspace()
{

  # Mount a  temporary filesystem image at "${uzip}" so that we can clean up afterwards more easily
  # dd if=/dev/zero of=test.img bs=1M count=512
  # mdconfig -a -t vnode -f test.img -u 9
  # newfs /dev/md9
  # mount /dev/md9 "${uzip}"

  mkdir -p "${livecd}" "${base}" "${iso}" "${packages}" "${uzip}" "${ramdisk_root}/dev" "${ramdisk_root}/etc" >/dev/null 2>/dev/null
  #truncate -s 3g "${livecd}/pool.img"
  #mdconfig -f "${livecd}/pool.img" -u 0
  sync ### Needed?


}

base()
{
  # TODO: Signature checking
  if [ ! -f "${base}/base.txz" ] ; then 
    cd ${base}
    fetch https://download.freebsd.org/ftp/${FTPDIRECTORY}/${arch}/${version}/base.txz
  fi
  
  if [ ! -f "${base}/kernel.txz" ] ; then
    cd ${base}
    fetch https://download.freebsd.org/ftp/${FTPDIRECTORY}/${arch}/${version}/kernel.txz
  fi
  cd ${base}
  tar -zxvf base.txz -C ${uzip}
  tar -zxvf kernel.txz -C ${uzip}
  touch ${uzip}/etc/fstab
}

pkg_add_from_url()
{
      url=$1
      pkg_cachesubdir=$2
      abi=${3+env ABI=$3}

      pkgfile=${url##*/}
      if [ ! -e ${uzip}${pkg_cachedir}/${pkg_cachesubdir}/${pkgfile} ]; then
        fetch -o ${uzip}${pkg_cachedir}/${pkg_cachesubdir}/ $url
      fi
      IGNORE_OSVERSION=yes /usr/local/sbin/pkg-static -c "${uzip}" install -y $(/usr/local/sbin/pkg-static query -F ${uzip}${pkg_cachedir}/${pkg_cachesubdir}/${pkgfile} %dn)
      IGNORE_OSVERSION=yes $abi /usr/local/sbin/pkg-static -c "${uzip}" add ${pkg_cachedir}/${pkg_cachesubdir}/${pkgfile}
      IGNORE_OSVERSION=yes /usr/local/sbin/pkg-static -c "${uzip}" lock -y $(/usr/local/sbin/pkg-static query -F ${uzip}${pkg_cachedir}/${pkg_cachesubdir}/${pkgfile} %o)
}

packages()
{
  # NOTE: Also adjust the Nvidia drivers accordingly below. TODO: Use one set of variables
  if [ $MAJOR -eq 12 ] ; then
    # echo "Major version 12, hence using release_2 packages since quarterly can be missing packages from one day to the next"
    # sed -i -e 's|quarterly|release_2|g' "${uzip}/etc/pkg/FreeBSD.conf"
    # rm -f "${uzip}/etc/pkg/FreeBSD.conf-e"
    echo "Major version 12, hence using quarterly packages to see whether it performs better than release_2"
  elif [ $MAJOR -eq 13 ] ; then
    echo "Major version 13, hence using quarterly packages since release_2 will probably not have compatible Intel driver"
  else
    echo "Other major version, hence changing /etc/pkg/FreeBSD.conf to use latest packages"
    sed -i -e 's|quarterly|latest|g' "${uzip}/etc/pkg/FreeBSD.conf"
    rm -f "${uzip}/etc/pkg/FreeBSD.conf-e"
  fi
  cp /etc/resolv.conf ${uzip}/etc/resolv.conf
  mkdir ${uzip}/var/cache/pkg
  mount_nullfs ${packages} ${uzip}/var/cache/pkg
  mount -t devfs devfs ${uzip}/dev
  # FIXME: In the following line, the hardcoded "i386" needs to be replaced by "${arch}" - how?
  for p in common-${MAJOR} ${desktop}; do
    sed '/^#/d;/\!i386/d;/^cirrus:/d;/^https:/d' "${cwd}/settings/packages.$p" | \
      xargs /usr/local/sbin/pkg-static -c "${uzip}" install -y
    pkg_cachedir=/var/cache/pkg
    # Install packages beginning with 'cirrus:'
    mkdir -p ${uzip}${pkg_cachedir}/furybsd-cirrus
    for url in $(sed -ne "s,^cirrus:,https://api.cirrus-ci.com/v1/artifact/,;s,%%ARCH%%,$arch,;s,%%VER%%,$VER,p" "${cwd}/settings/packages.$p"); do
        pkg_add_from_url "$url" furybsd-cirrus
    done
    # Install packages beginning with 'https:'
    mkdir -p ${uzip}${pkg_cachedir}/furybsd-https
    for url in $(grep -e '^https' "${cwd}/settings/packages.$p"); do
        # ABI=freebsd:12:$arch in an attempt to use package built on 12 for 13
        pkg_add_from_url "$url" furybsd-https "freebsd:12:$arch"
    done
  done
  # Install the packages we have generated in pkg() that are listed in transient-packages-list
  ls -lh "${packages}/transient/"
  while read -r p; do
    # FIXME: Is there something like "/usr/local/sbin/pkg-static add" that can be used
    # to install local packages (not from a repository) that will
    # resolve dependencies from the repositories?
    # The following will just fail in the case of unmet dependencies
    /usr/local/sbin/pkg-static -r ${uzip} add "${packages}/transient/${p}" # pkg-static add has no -y
  done <"${packages}/transient/transient-packages-list"
  
  # /usr/local/sbin/pkg-static -c ${uzip} info > "${cdroot}/data/system.uzip.manifest"
  # Manifest of installed packages ordered by size in bytes
  /usr/local/sbin/pkg-static -c ${uzip} query "%sb\t%n\t%v\t%c" | sort -r -s -n -k 1,1 > "${cdroot}/data/system.uzip.manifest"
  cp "${cdroot}/data/system.uzip.manifest" "${isopath}.manifest"
}

rc()
{
  if [ ! -f "${uzip}/etc/rc.conf" ] ; then
    touch ${uzip}/etc/rc.conf
  fi
  if [ ! -f "${uzip}/etc/rc.conf.local" ] ; then
    touch ${uzip}/etc/rc.conf.local
  fi
  cat "${cwd}/settings/rc.conf.common" | xargs chroot "${uzip}" sysrc -f /etc/rc.conf.local
  cat "${cwd}/settings/rc.conf.${desktop}" | xargs chroot "${uzip}" sysrc -f /etc/rc.conf.local
}


repos()
{
  # This is just an example of how a git repo needs to be structured
  # so that it can be consumed directly here
  # if [ ! -d "${cwd}/overlays/uzip/furybsd-common-settings" ] ; then
  #   git clone https://github.com/probonopd/furybsd-common-settings.git ${cwd}/overlays/uzip/furybsd-common-settings
  # else
  #   cd ${cwd}/overlays/uzip/furybsd-common-settings && git pull
  # fi
  true
}

user()
{
  mkdir -p ${uzip}/usr/home/liveuser/Desktop
  # chroot ${uzip} echo furybsd | chroot ${uzip} pw mod user root -h 0
  chroot ${uzip} pw useradd liveuser -u 1000 \
  -c "Live User" -d "/home/liveuser" \
  -g wheel -G operator -m -s /usr/local/bin/zsh -k /usr/share/skel -w none
  chroot ${uzip} pw groupadd liveuser -g 1000
  # chroot ${uzip} echo furybsd | chroot ${uzip} pw mod user liveuser -h 0
  chroot ${uzip} chown -R 1000:1000 /usr/home/liveuser
  chroot ${uzip} pw groupmod wheel -m liveuser
  chroot ${uzip} pw groupmod video -m liveuser
  chroot ${uzip} pw groupmod webcamd -m liveuser
}

dm()
{
  case $desktop in
    'kde')
      ;;
    'gnome')
      ;;
    'lumina')
      ;;
    'mate')
      chroot ${uzip} sed -i '' -e 's/memorylocked=128M/memorylocked=256M/' /etc/login.conf
      chroot ${uzip} cap_mkdb /etc/login.conf
      ;;
    'xfce')
      ;;
  esac
}

# Generate transient packages for the selected overlays
pkg()
{
  mkdir -p "${packages}/transient"
  cd "${packages}/transient"
  rm -f *.txz # Make sure there are no leftover transient packages from earlier runs
  while read -r p; do
    sh -ex "${cwd}/scripts/build-pkg.sh" -m "${cwd}/overlays/uzip/${p}"/manifest -d "${cwd}/overlays/uzip/${p}/files"
  done <"${cwd}"/settings/overlays.common
  if [ -f "${cwd}/settings/overlays.${desktop}" ] ; then
    while read -r p; do
      sh -ex "${cwd}/scripts/build-pkg.sh" -m "${cwd}/overlays/uzip/${p}"/manifest -d "${cwd}/overlays/uzip/${p}/files"
    done <"${cwd}/settings/overlays.${desktop}"
  fi
  cd -
}

# Put Nvidia driver at location in which initgfx expects it
initgfx()
{
  if [ "${arch}" != "i386" ] ; then
    MAJOR=$(uname -r | cut -d "." -f 1)
    if [ $MAJOR -lt 14 ] ; then
      PKGS="quarterly"
    else
      PKGS="latest"
    fi
    # for ver in '' 390 340 304; do
    for ver in ''; do # Only use NVIDIA version 440 for now to reduce ISO image size
        pkgfile=$(/usr/local/sbin/pkg-static -c ${uzip} rquery %n-%v.txz nvidia-driver${ver:+-$ver})
        fetch -o "${cache}/" "https://pkg.freebsd.org/FreeBSD:${MAJOR}:amd64/${PKGS}/All/${pkgfile}"
        mkdir -p "${uzip}/usr/local/nvidia/${ver:-440}/"
        tar xfC "${cache}"/${pkgfile} "${uzip}/usr/local/nvidia/${ver:-440}/"
        ls "${uzip}/usr/local/nvidia/${ver:-440}/+COMPACT_MANIFEST"
    done
  fi

  ls

  rm ${uzip}/etc/resolv.conf
  umount ${uzip}/var/cache/pkg
  umount ${uzip}/dev
}

script()
{
  if [ -e "${cwd}/settings/script.${desktop}" ] ; then
    # cp "${cwd}/settings/script.${desktop}" "${uzip}"/tmp/script
    # chmod +x "${uzip}"/tmp/script
    # chroot "${uzip}" /tmp/script
    # rm "${uzip}"/tmp/script
    "${cwd}/settings/script.${desktop}"
  fi
}

uzip() 
{
  ( cd "${uzip}" ; ln -s . ./sysroot ) # Workaround for low-level tools trying to load things from /sysroot; https://github.com/helloSystem/ISO/issues/4#issuecomment-787062758
  install -o root -g wheel -m 755 -d "${cdroot}"
  # geom_rowr needs some free extra space on the r/o filesystem, otherwise it reports
  # no free space for the combined /dev/rowrX filesystem
  makefs -b '20%' -f '20%' "${cdroot}/data/system.ufs" "${uzip}"
  wc -c < "${cdroot}/data/system.ufs" > "${cdroot}/data/system.bytes" # Size in bytes, needed by init.sh
  mkuzip -o "${cdroot}/data/system.uzip" "${cdroot}/data/system.ufs"
  rm -f "${cdroot}/data/system.ufs"
  
}

ramdisk() 
{
  cp -R "${cwd}/overlays/ramdisk/" "${ramdisk_root}"
  # Copy the 'geom' command and its dependencies needed to mount using geom_rowr
  mkdir -p "${ramdisk_root}"/sbin "${ramdisk_root}"/lib
  cp "${uzip}"/sbin/geom "${ramdisk_root}"/sbin/
  cp "${uzip}"/lib/libgeom.so.5 "${ramdisk_root}"/lib/
  cp "${uzip}"/lib/libutil.so.9 "${ramdisk_root}"/lib/
  cp "${uzip}"/lib/libc.so.7 "${ramdisk_root}"/lib/
  cp "${uzip}"/lib/libbsdxml.so.4 "${ramdisk_root}"/lib/
  cp "${uzip}"/lib/libsbuf.so.6 "${ramdisk_root}"/lib/
  # TODO: Replace the lines above with something more robust that won't break
  # when the dependencies of the 'geom' command change
  cd "${uzip}" && tar -cf - rescue | tar -xf - -C "${ramdisk_root}"
  touch "${ramdisk_root}/etc/fstab"
  cp ${uzip}/etc/login.conf ${ramdisk_root}/etc/login.conf
  makefs -b '10%' "${cdroot}/data/ramdisk.ufs" "${ramdisk_root}"
  gzip -f "${cdroot}/data/ramdisk.ufs"
  rm -rf "${ramdisk_root}"
}

boot() 
{
  cp -R "${cwd}/overlays/boot/" "${cdroot}"
  cd "${uzip}" && tar -cf - boot | tar -xf - -C "${cdroot}"
  # Remove all modules from the ISO that is not required before the root filesystem is mounted
  # The whole directory /boot/modules is unnecessary
  rm -rf "${cdroot}"/boot/modules/*
  # Remove modules in /boot/kernel that are not loaded at boot time
  find "${cdroot}"/boot/kernel -name '*.ko' \
    -not -name 'cryptodev.ko' \
    -not -name 'firewire.ko' \
    -not -name 'geom_uzip.ko' \
    -not -name 'opensolaris.ko' \
    -not -name 'tmpfs.ko' \
    -not -name 'xz.ko' \
    -not -name 'zfs.ko' \
    -not -name 'geom_rowr.ko' \
    -delete
  # Add geom_rowr kernel module for combining read-only with read-write device
  # Note that this also requires a library geom_rowr.so
  wget -c -q "https://github.com/helloSystem/ISO/releases/download/assets/geom_rowr.tar.gz"
  tar xf geom_rowr.tar.gz
  cp "${VER}"/geom_rowr.ko "${cdroot}"/boot/kernel/
  ls "${cdroot}"/boot/kernel/geom_rowr.ko || exit 1
  mkdir -p "${cdroot}"/lib/geom/
  cp "${VER}"/geom_rowr.so "${cdroot}"/lib/geom/
  ls "${cdroot}"/lib/geom/geom_rowr.so || exit 1
  rm -rf "12.2" "13.0" "geom_rowr.tar.gz"
  # Compress the kernel
  gzip "${cdroot}"/boot/kernel/kernel
  # Compress the remaining modules
  find "${cdroot}"/boot/kernel -type f -name '*.ko' -exec gzip {} \;
  sync ### Needed?
}

tag()
{
  if [ -n "$CIRRUS_CI" ] ; then
    SHA=$(echo "${CIRRUS_CHANGE_IN_REPO}" | head -c 7)
    URL="https://${CIRRUS_REPO_CLONE_HOST}/${CIRRUS_REPO_FULL_NAME}/commit/${SHA}"
    echo "${URL}"
    echo "${URL}" > "${cdroot}/.url"
    echo "${URL}" > "${uzip}/.url"
    echo "Setting extended attributes 'url' and 'sha' on '/.url'"
    setextattr user sha "${SHA}" "${uzip}/.url"
    setextattr user url "${URL}" "${uzip}/.url"
    setextattr user build "${BUILDNUMBER}" "${uzip}/.url"
  fi
}

image()
{
  sh "${cwd}/scripts/mkisoimages-${arch}.sh" -b "${label}" "${isopath}" "${cdroot}"
  sync ### Needed?
  md5 "${isopath}" > "${isopath}.md5"
  echo "$isopath created"
}

split()
{
  # units -o "%0.f" -t "2 gigabytes" "bytes"
  THRESHOLD_BYTES=2147483647
  # THRESHOLD_BYTES=1999999999
  ISO_SIZE=$(stat -f%z "${isopath}")
  if [ $ISO_SIZE -gt $THRESHOLD_BYTES ] ; then
    echo "Size exceeds GitHub Releases file size limit; splitting the ISO"
    sudo split -d -b "$THRESHOLD_BYTES" -a 1 "${isopath}" "${isopath}.part"
    echo "Split the ISO, deleting the original"
    rm "${isopath}"
    ls -l "${isopath}"*
  fi
}

cleanup
workspace
repos
pkg
base
packages
initgfx
rc
user
dm
script
tag
uzip
ramdisk
boot
image

if [ -n "$CIRRUS_CI" ] ; then
  # On Cirrus CI we want to upload to GitHub Releases which has a 2 GB file size limit,
  # hence we need to split the ISO there if it is too large
  split
fi

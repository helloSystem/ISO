#!/bin/sh

# Exit on errors
set -e

# Workaround for cases when the running kernel doesn't exactly match the kernel on the ISO
export IGNORE_OSVERSION=yes

# Determine the version of the running host system.
# Building ISOs for other major versions than the running host system
# is not supported and results in broken images anyway
version=$(uname -r | cut -d "-" -f 1-2) # "12.2-RELEASE" or "13.0-CURRENT"
echo "Host system version: ${version}"

if [ "${version}" = "13.0-RELEASE" ] ; then
  # version="13.0-RC3"
  # version="13.0-RELEASE"
  version="13.2-RELEASE"
fi

VER=$(echo "${version}" | cut -d "-" -f 1) # "12.2" or "13.0"
MAJOR=$(echo "${version}" | cut -d "." -f 1) # "12" or "13"

# Download from either https://download.freebsd.org/ftp/releases/
#                  or https://download.freebsd.org/ftp/snapshots/
VERSIONSUFFIX=$(uname -r | cut -d "-" -f 2) # "RELEASE" or "CURRENT"
FTPDIRECTORY="releases" # "releases" or "snapshots"
if [ "${VERSIONSUFFIX}" = "CURRENT" ] ; then
  FTPDIRECTORY="snapshots"
fi
# RCs are in the 'releases' ftp directory; hence check if $VERSIONSUFFIX begins with 'RC' https://serverfault.com/a/252406
if [ "${VERSIONSUFFIX#RC}"x != "${VERSIONSUFFIX}x" ]  ; then
  FTPDIRECTORY="releases"
fi

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
export uzip="${livecd}/uzip"
export cdroot="${livecd}/cdroot"
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
      sed -i '' -e 's|\(^version:       .*_\).*$|\1'$BUILDNUMBER'|g' "${cwd}/overlays/uzip/hello/manifest"
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

  mkdir -p "${livecd}" "${base}" "${iso}" "${packages}" "${uzip}" "${cdroot}" >/dev/null 2>/dev/null
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
      abi=${3+env ABI=$3} # Set $abi to "env ABI=$3" only if a third argument is provided
      echo "pkg_add_from_url: ${url}"

      pkgfile=${url##*/}
      if [ ! -e ${uzip}${pkg_cachedir}/${pkg_cachesubdir}/${pkgfile} ]; then
        fetch -o ${uzip}${pkg_cachedir}/${pkg_cachesubdir}/ $url
      fi
      deps=$(/usr/local/sbin/pkg-static query -F ${uzip}${pkg_cachedir}/${pkg_cachesubdir}/${pkgfile} %dn)
      if [ ! -z "${deps}" ] ; then
        env IGNORE_OSVERSION=yes /usr/local/sbin/pkg-static -c "${uzip}" install -y $(/usr/local/sbin/pkg-static query -F ${uzip}${pkg_cachedir}/${pkg_cachesubdir}/${pkgfile} %dn)
      fi
      $abi env IGNORE_OSVERSION=yes /usr/local/sbin/pkg-static -c "${uzip}" add ${pkg_cachedir}/${pkg_cachesubdir}/${pkgfile}
      env IGNORE_OSVERSION=yes /usr/local/sbin/pkg-static -c "${uzip}" lock -y $(/usr/local/sbin/pkg-static query -F ${uzip}${pkg_cachedir}/${pkg_cachesubdir}/${pkgfile} %o)
}

packages()
{
  cat > "${uzip}/etc/pkg/GhostBSD.conf" <<\\EOF
GhostBSD_PKG: {
  url: "http://pkg.ghostbsd.org/stable/${ABI}/latest",
  enabled: yes
}
EOF
  sed -i '' -e 's|enabled: yes|enabled: no|g' "${uzip}/etc/pkg/FreeBSD.conf"
  # NOTE: Also adjust the Nvidia drivers accordingly below. TODO: Use one set of variables
  if [ $MAJOR -eq 12 ] ; then
    # echo "Major version 12, hence using release_2 packages since quarterly can be missing packages from one day to the next"
    # sed -i '' -e 's|quarterly|release_2|g' "${uzip}/etc/pkg/GhostBSD.conf"
    echo "Major version 12, using quarterly packages"
  elif [ $MAJOR -eq 13 ] ; then
    echo "Major version 13, using quarterly packages"
    # sed -i '' -e 's|quarterly|release_1|g' "${uzip}/etc/pkg/GhostBSD.conf"
  elif [ $MAJOR -eq 14 ] ; then
    echo "Major version 14, hence changing /etc/pkg/GhostBSD.conf to use latest packages"
    sed -i '' -e 's|quarterly|latest|g' "${uzip}/etc/pkg/GhostBSD.conf"
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
      # First, try installing this using the real major version, then try to install package built for major version 12
      pkg_add_from_url "$url" furybsd-https || pkg_add_from_url "$url" furybsd-https "freebsd:12:$arch"
    done
  done
  # Install the packages we have generated in pkg() that are listed in transient-packages-list
  ls -lh "${packages}/transient/"
  while read -r p; do
    # FIXME: Is there something like "/usr/local/sbin/pkg-static add" that can be used
    # to install local packages (not from a repository) that will
    # resolve dependencies from the repositories?
    # The following will just fail in the case of unmet dependencies
    ### /usr/local/sbin/pkg-static -r ${uzip} add "${packages}/transient/${p}" # pkg-static add has no -y
    /usr/local/sbin/pkg -r ${uzip} add "${packages}/transient/${p}"
  done <"${packages}/transient/transient-packages-list"
  
  # Manifest of installed packages ordered by size in bytes
  /usr/local/sbin/pkg-static -c ${uzip} query "%sb\t%n\t%v\t%c" | sort -r -s -n -k 1,1 > "${isopath}.manifest"
  # zip local.sqlite and put in output directory next to the ISO
  zip pkg.zip ${uzip}/var/db/pkg/local.sqlite
  mv pkg.zip "${isopath}.pkg.zip"
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
  # This is now done ad-hoc at boot time because we would
  # need to constuct $HOME from skel anyway
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
  /usr/local/sbin/pkg-static -c ${uzip} update # Needed if we are shipping additional repos 
  if [ "${arch}" != "i386" ] ; then
    if [ $MAJOR -lt 14 ] ; then
      PKGS="quarterly"
      # PKGS="latest" # This must match what we specify in packages()
    else
      PKGS="latest"
    fi

    # 390 needed for Nvidia Quadro 2000, https://github.com/helloSystem/hello/discussions/241#discussioncomment-1599131
    # 340 needed for Nvidia 320M
    for ver in '' 390 340 304; do
        # pkgfile=$(/usr/local/sbin/pkg-static -c ${uzip} rquery %n-%v.txz nvidia-driver${ver:+-$ver})
        pkgfile=$(/usr/local/sbin/pkg-static -c ${uzip} rquery %n-%v.pkg nvidia-driver${ver:+-$ver})
        fetch -o "${cache}/" "https://pkg.freebsd.org/FreeBSD:${MAJOR}:amd64/${PKGS}/All/${pkgfile}"
        mkdir -p "${uzip}/usr/local/nvidia/${ver:-latest}/"
        tar xfC "${cache}"/${pkgfile} "${uzip}/usr/local/nvidia/${ver:-latest}/"
        ls "${uzip}/usr/local/nvidia/${ver:-latest}/+COMPACT_MANIFEST"
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
  rm "${uzip}"/var/db/pkg/repo-*BSD.sqlite || true
  find "${uzip}" -type d -name '__pycache__' -delete || true
}

developer()
{
  # Remove files that are non-essential to the working of
  # the system, especially files only needed by developers
  # and non-localized documentation not understandable to
  # non-English speakers and put them into developer.img
  # TODO: Find more files to be removed; the largest files
  # in a directory can be listed with
  # ls -lhS /usr/lib | head
  # Tools like filelight and sysutils/k4dirstat might also be helpful

  # Clean up locally in this function in case the user did not run cleanup()
  if [ -d "${livecd}" ] ;then
    chflags -R noschg ${cdroot} >/dev/null 2>/dev/null || true
    rm -rf ${cdroot} >/dev/null 2>/dev/null || true
  fi

  cd  "${uzip}"
  rm -rf /root/.cache 2>/dev/null 2>&1 | true
  
  # Create a spec file that describes the whole filesystem
  mtree -p  . -c > "${livecd}"/spec

  # Create a spec file with one line for each file, directory, and symlink
  mtree -C -R nlink,time,size -f "${livecd}"/spec > "${livecd}"/spec.annotated

  # Annotate all developer-oriented files with '# developery<rule_id>'
  # The annotations are numbered with <rule_id> so that we can see which rule
  # was responsible for flagging something as a developer-oriented file
  sed -i '' -e 's|^\./Install.*|& # developer|' "${livecd}"/spec.annotated
  sed -i '' -e 's|.*/doc/.*|& # developer1|' "${livecd}"/spec.annotated
  sed -i '' -e 's|.*/docs/.*|& # developer2|' "${livecd}"/spec.annotated
  sed -i '' -e 's|.*\.la.*|& # developer3|' "${livecd}"/spec.annotated
  sed -i '' -e 's|.*/man/.*|& # developer4|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/include/.*|& # developer5|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/local/include/.*|& # developer6|' "${livecd}"/spec.annotated
  sed -i '' -e 's|.*\.h\ .*|& # developer7|' "${livecd}"/spec.annotated
  sed -i '' -e 's|.*\.a\ .*|& # developer8|' "${livecd}"/spec.annotated
  sed -i '' -e 's|.*\.o\ .*|& # developer9|' "${livecd}"/spec.annotated
  sed -i '' -e 's|.*-doc/.*|& # developer10|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./Applications/Developer/.*|& # developer11|' "${livecd}"/spec.annotated
  sed -i '' -e 's|.*/debug/.*|& # developer12|' "${livecd}"/spec.annotated
  sed -i '' -e 's|.*/src/.*|& # developer13|' "${livecd}"/spec.annotated
  sed -i '' -e 's|.*/git-core/.*|& # developer14|' "${livecd}"/spec.annotated
  sed -i '' -e 's|.*/git/.*|& # developer15|' "${livecd}"/spec.annotated
  sed -i '' -e 's|.*/devhelp/.*|& # developer16|' "${livecd}"/spec.annotated
  sed -i '' -e 's|.*/examples/.*|& # developer17|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/bin/svn.*|& # developer18|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/bin/clang.*|& # developer19|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/bin/c++.*|& # developer20|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/bin/cpp.*|& # developer21|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/bin/cc.*|& # developer22|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/bin/lldb.*|& # developer23|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/local/bin/ccxx.*|& # developer24|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/bin/llvm.*|& # developer25|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/bin/ld.lld.*|& # developer26|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/bin/ex\ .*|& # developer27|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/bin/nex\ .*|& # developer28|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/bin/nvi\ .*|& # developer29|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/bin/vi\ .*|& # developer30|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/bin/view\ .*|& # developer31|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/local/llvm.*/bin/.*|& # developer32|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/local/llvm.*/include/.*|& # developer33|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/local/llvm.*/libexec/.*|& # developer34|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/local/llvm.*/share/.*|& # developer35|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/local/llvm.*/lib/clang/.*|& # developer36|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/local/llvm.*/lib/cmake/.*|& # developer37|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/local/llvm.*/lib/python.*|& # developer38|' "${livecd}"/spec.annotated
  # 'libLLVM-*.so*' must NOT be deleted as it is needed for graphics drivers
  sed -i '' -e 's|^\./usr/lib/clang/.*/include/.*|& # developer39|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/local/llvm.*/lib/libclang.*|& # developer40|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/local/llvm.*/lib/liblldb.*|& # developer41|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/local/lib/python.*/test/.*|& # developer42|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/local/share/info/.*|& # developer43|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/local/share/gir-.*|& # developer44|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./Applications/Utilities/BuildNotify.app.*|& # developer45|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./Applications/Autostart/BuildNotify.app.*|& # developer46|' "${livecd}"/spec.annotated
  sed -i '' -e 's|^\./usr/sbin/portsnap\ .*|& # developer47|' "${livecd}"/spec.annotated
  
  cp "${livecd}"/spec.annotated "${livecd}"/spec.user
  cp "${livecd}"/spec.annotated "${livecd}"/spec.developer

  # Delete the annotated lines from spec.developer and spec.user, respectively
  sed -i '' -e '/# developer/!d' "${livecd}"/spec.developer
  # Add back all directories, otherwise we get permissions issues
  grep " type=dir " "${livecd}"/spec.annotated >> "${livecd}"/spec.developer
  grep "^\./\.hidden" "${livecd}"/spec.annotated >> "${livecd}"/spec.developer
  cat "${livecd}"/spec.developer | sort | uniq > "${livecd}"/spec.developer.sorted
  sed -i '' '/^$/d' "${livecd}"/spec.developer.sorted # Remove empty lines
  sed -i '' -e '/# developer/d' "${livecd}"/spec.user
  sed -i '' '/^$/d' "${livecd}"/spec.user # Remove empty lines
  echo "$(cat "${livecd}"/spec.developer.sorted | wc -l) items for developer image"
  echo "$(cat "${livecd}"/spec.user | wc -l) items for user image"

  # Create the developer image
  makefs -o label="Developer" -R 262144 "${iso}/developer.ufs" "${livecd}"/spec.developer.sorted
  developerimagename=$(basename $(echo ${isopath} | sed -e 's|.iso$|.developer.img|g'))
  if [ $MAJOR -gt 13 ] ; then
    mkuzip -o "${iso}/${developerimagename}" "${iso}/developer.ufs"
  else
    # Use zstd when possible, which is available in FreeBSD beginning with 13 but broken in 14 (FreeBSD bug 267082)
    mkuzip -A zstd -C 15 -d -s 262144 -o "${iso}/${developerimagename}" "${iso}/developer.ufs"
  fi
  rm "${iso}/developer.ufs"
  md5 "${iso}/${developerimagename}" > "${iso}/${developerimagename}.md5"

  cd -

}

uzip() 
{
  install -o root -g wheel -m 755 -d "${cdroot}"
  ( cd "${uzip}" ; makefs -b 75% -f 75% -R 262144 "${cdroot}/rootfs.ufs" ../spec.user )
  mkdir -p "${cdroot}/boot/"
  if [ $MAJOR -gt 13 ] ; then
    mkuzip -o "${cdroot}/boot/rootfs.uzip" "${cdroot}/rootfs.ufs"
  else
    # Use zstd when possible, which is available in FreeBSD beginning with 13 but broken in 14 (FreeBSD bug 267082)
    mkuzip -A zstd -C 15 -d -s 262144 -o "${cdroot}/boot/rootfs.uzip" "${cdroot}/rootfs.ufs"
  fi

  rm -f "${cdroot}/rootfs.ufs"
  
}

boot() 
{
  mkdir -p "${cdroot}"/bin/ ; cp "${uzip}"/bin/freebsd-version "${cdroot}"/bin/
  cp "${uzip}"/COPYRIGHT "${cdroot}"/
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
    -not -name 'tmpfs.ko' \
    -not -name 'xz.ko' \
    -delete
  # Compress the kernel
  gzip -f "${cdroot}"/boot/kernel/kernel || true
  rm "${cdroot}"/boot/kernel/kernel || true
  # Compress the modules in a way the kernel understands
  find "${cdroot}"/boot/kernel -type f -name '*.ko' -exec gzip -f {} \;
  find "${cdroot}"/boot/kernel -type f -name '*.ko' -delete
  mkdir -p "${cdroot}"/dev "${cdroot}"/etc # TODO: Create all the others here as well instead of keeping them in overlays/boot
  cp "${uzip}"/etc/login.conf  "${cdroot}"/etc/ # Workaround for: init: login_getclass: unknown class 'daemon'
  cd "${uzip}" && tar -cf - rescue | tar -xf - -C "${cdroot}" # /rescue is full of hardlinks
  if [ $MAJOR -gt 12 ] ; then
    # Must not try to load tmpfs module in FreeBSD 13 and later, 
    # because it will prevent the one in the kernel from working
    sed -i '' -e 's|^tmpfs_load|# load_tmpfs_load|g' "${cdroot}"/boot/loader.conf
    rm "${cdroot}"/boot/kernel/tmpfs.ko*
  fi
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
    # setextattr user sha "${SHA}" "${uzip}/.url" # Does not work on tmpfs
    # setextattr user url "${URL}" "${uzip}/.url"
    # setextattr user build "${BUILDNUMBER}" "${uzip}/.url"
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
developer
uzip
boot
image

if [ -n "$CIRRUS_CI" ] ; then
  # On Cirrus CI we want to upload to GitHub Releases which has a 2 GB file size limit,
  # hence we need to split the ISO there if it is too large
  split
fi

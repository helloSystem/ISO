#!/bin/sh

set -e
set -x

HERE="$(dirname "$(readlink -f "${0}")")"/../../

# During Development!
# HERE=/media/Developer

if [ ! -e "${HERE}" ] ; then
  echo "${HERE} does not exist" >&2
  exit 1
fi

# As the first thing, only answer with
# INSTALLER_MIB_NEEDED=1234567890
# then immediately exit
# if INSTALLER_PRINT_MIB_NEEDED is set. This is needed for the graphical installer frontend
if [ -n "${INSTALLER_PRINT_MIB_NEEDED}" ] ; then
  kbytes=$(df -k "${HERE}" | awk '{ print $3 }' | tail -n 1)
  mib=$(echo "${kbytes}/1024" | bc) # Convert kbytes to MiB
  echo "INSTALLER_MIB_NEEDED=${mib}"
  exit 0
fi

if [ -e "${INSTALLER_TARGET_MOUNTPOINT}" ] ; then
  cpdup -o -v "${HERE}" "${INSTALLER_TARGET_MOUNTPOINT}" # Allow to overwrite but not to delete anything
  # CAUTION: This is DANGEROUS if permissions on the image are insufficient, because then permissions
  # on the system will be changed accordingly
else
  echo "${INSTALLER_TARGET_MOUNTPOINT} does not exist" >&2
  exit 1
fi

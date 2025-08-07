#!/bin/bash

set -eu

rootpath() {
   local dir=$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")
   if [[ -f "${dir}/LICENSE" ]] ; then
      echo "$dir"
   elif [[ -d /usr/share/rpi-image-gen ]] ; then
      echo /usr/share/rpi-image-gen
   else
      >&2 echo "FATAL: cannot locate project root" ; exit 1
   fi
}
IGTOP=$(rootpath)
source "${IGTOP}/lib/dependencies.sh"
depf=("${IGTOP}/depends")
for f in "$@" ; do
   depf+=($(realpath -e "$f"))
done
dependencies_install "${depf[@]}"

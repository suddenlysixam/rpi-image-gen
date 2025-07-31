#!/bin/bash

set -u

if igconf isset image_pmap ; then
   [[ -f "${IGconf_image_assetdir}/device/provisionmap-${IGconf_image_pmap}.json" ]] || \
      die "pmap not found"
fi

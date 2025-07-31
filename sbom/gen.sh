#!/bin/bash
# shellcheck disable=SC2154

set -eu

rootfs=$1
outdir=$2

igconf isy sbom_enable || exit 0

[[ $(igconf getval sbom_provider) == syft ]] || exit 0

SYFTCFG=$(realpath -e $(igconf getval sbom_syft_config)) || die "Invalid syft config"

SYFT_VER=v1.27.1

# If host has syft, use it
if ! hash syft 2>/dev/null; then
   curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
      | sh -s -- -b "${IGconf_sys_workroot}"/host/bin "${SYFT_VER}"
fi

SYFT=$(syft --version 2>/dev/null) || die "syft is unusable"

msg "SBOM: $SYFT scanning $rootfs"

syft -c "$SYFTCFG"  scan dir:"$rootfs" \
   --base-path "$rootfs" \
   --source-name "$IGconf_image_name" \
   --source-version "${IGconf_image_version}" \
   > "${outdir}/${IGconf_image_name}.sbom"

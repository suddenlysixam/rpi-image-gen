#!/bin/bash

set -uo pipefail


rootpath() {
   if [[ -d /usr/share/rpi-image-gen ]] ; then
      readlink -f /usr/share/rpi-image-gen
   else
      readlink -f "$(dirname "$0")"
   fi
}


IGCMD=build


help()
{
cat <<-EOF >&2
Filesystem and image generation utility.

Usage:
  $(basename $(readlink -f "$0")) [cmd] [options]

Supported commands:
  build [options]
EOF
}


help_build()
{
cat <<-EOF >&2
Usage
  $(basename $(readlink -f "$0")) [options] [-- IGconf_key=value ...]

Options:
  [-c <config>]    Path to config file.
  [-S <src dir>]   Directory holding custom sources of config, profile, image
                   layout and layers.
  [-B <build dir>] Use this as the root directory for generation and build.
                   Sets IGconf_sys_workroot.
  [-I]             Interactive. Prompt at different stages.

  Developer Options
  [-r]             Establish configuration, build rootfs, exit after post-build.
  [-i]             Establish configuration, skip rootfs, run hooks, generate image.

  IGconf Variable Overrides:
    Use -- to separate options from overrides.
    Any number of key=value pairs can be provided.
    Use single quotes to enable variable expansion.
EOF
}


parse_build()
{
   while getopts "B:c:hiIrS:" flag ; do
      case "$flag" in
         B)
            BUILD_DIR=$(realpath --canonicalize-missing "$OPTARG")
            [[ -d "$BUILD_DIR" ]] || { usage ; die "Invalid build dir: $BUILD_DIR" ; }
            ;;
         c)
            INCONFIG="$OPTARG"
            ;;
         h)
            help_build ; exit 0
            ;;
         i)
            ONLY_IMAGE=1
            ;;
         I)
            INTERACTIVE=y
            ;;
         S)
            SRC_DIR=$(realpath --canonicalize-missing "$OPTARG")
            [[ -d "$SRC_DIR" ]] || { usage ; die "Invalid source dir: $SRC_DIR" ; }
            ;;
         r)
            ONLY_ROOTFS=1
            ;;
         h|?|*)
            help_build ; exit 1
            ;;
      esac
   done
}


case $IGCMD in
   build)
      parse_$IGCMD "$@"
      shift $((OPTIND-1))
      ;;
   ""|"-h"|"--help"|*) help ; exit 1 ;;
esac


# Load helpers
source $(rootpath)/scripts/common


# Config is mandatory
[[ -z ${INCONFIG+x} ]] && die "No config file specified"


# Check deps
source $(rootpath)/scripts/dependencies_check
dependencies_check $(rootpath)/depends || exit 1
#source $(rootpath)/scripts/core
#source "$(rootpath)/bin/igconf"



# Dynamic component path resolution
resolve_path() {
   local target="$1"

   [[ -n "$target" ]] || { err "target path required" ; return 1; }

   local cpath

   # Handle absolute paths directly
   if [[ "$target" == /* ]]; then
       if cpath=$(realpath --canonicalize-existing "$target" 2>/dev/null); then
           echo "$cpath"
           return 0
       else
           err "path '$target' not found"
           return 1
       fi
   fi

   # Handle relative paths with search logic
   local -a search_paths

   if [[ ! "$(rootpath)" -ef "$SRC_DIR" ]] ; then
      search_paths+=("$(readlink -f "$SRC_DIR")")
   fi
   search_paths+=($(rootpath))

   local candidate
   for base in "${search_paths[@]}"; do
      candidate="${base}/${target}"
      if cpath=$(realpath --canonicalize-existing "$candidate" 2>/dev/null); then
         echo "$cpath"
         return 0
      fi
   done

   warn "'$target' not found in any search path)"
   return 1
}


# General purpose
IGTMP=$(mktemp -d) || die "mktemp error"
trap 'rm -rf $IGTMP' EXIT


# Handle opt switches
: "${SRC_DIR:=$(readlink -f .)}"
BUILD_DIR=${BUILD_DIR:-}
: "${INTERACTIVE:=n}"

OVRF=${IGTMP}/overrides.env
> "$OVRF"
declare -A IGOVERRIDES
[[ -n "$BUILD_DIR" ]] && IGOVERRIDES[IGconf_sys_workroot]="$BUILD_DIR"
{
   for key in "${!IGOVERRIDES[@]}"; do
      echo "$key=${IGOVERRIDES[$key]}"
   done
} > "$OVRF"


# Handle arg overrides
for arg in "$@"; do
   if [[ "$arg" =~ ^IGconf_[a-zA-Z_][a-zA-Z0-9_]*=.* ]]; then
       key="${arg%%=*}"
       value="${arg#*=}"
       IGOVERRIDES["$key"]="$value"
       printf '%s="%s"\n' "$key" "$value" >> "$OVRF"
       msg "Override: $key=$value"
   else
       die "Invalid argument format: $arg (expected IGconf_key=value)"
   fi
done


# PATH
if [[ ! "$(rootpath)" -ef "$SRC_DIR" ]] ; then
   [[ -d "${SRC_DIR}/bin" ]] && PATH="${SRC_DIR}/bin:$PATH"
fi
PATH="$(rootpath)/bin:$PATH"
export PATH


###############################################################################
# Stage 1: Input parameter assembly
#   Read config file, aggregate and prioritise cmdline overrides.
#   Establish dynamic component paths.
#   Begin construction of the configuration environment.
#
CFG=$(resolve_path $INCONFIG) || die "Bad config spec: $INCONFIG"
msg "\nCONFIG $CFG"
IGENVF=${IGTMP}/ig.env
> "$IGENVF"
ig config "$CFG" --overrides "$OVRF" --write-to "$IGENVF" || die "Config parse failed"

! grep -q '^IGconf_device' "$IGENVF" && die "Config provides no device info"
! grep -q '^IGconf_image' "$IGENVF" && die "Config provides no image info"
! grep -q '^IGconf_layer' "$IGENVF" && die "Config provides no layer info"

# Propagate other variables
META_HOOKS="$(rootpath)/meta-hooks"
RPI_TEMPLATES="$(rootpath)/templates/rpi"
for v in RPI_TEMPLATES META_HOOKS ; do
   printf '%s="%s"\n' "$v" "${!v}" >> "$IGENVF"
done


# Validate
( env -i bash -c 'set -eu; source "$1"' _ "$IGENVF" ) || die "parameter assembly"


###############################################################################
# Stage 2: Layers
#   Set up search paths - policy:
#     <src>/{device,image,meta}
#     <root>/{device,image,meta}
#   Collect layers specified by the config file.
#   Validate all layers.
#   Write out aggregated configuration env.
#   Generate the layer build order.
#
_path=()
for d in device image meta ; do
   if [[ ! "$(rootpath)" -ef "$SRC_DIR" ]] ; then
      [[ -d "${SRC_DIR}/${d}" ]] && _path+=($(realpath -e "${SRC_DIR}/${d}"))
   fi
done
_path+=($(realpath -e "$(rootpath)/device"))
_path+=($(realpath -e "$(rootpath)/image"))
_path+=($(realpath -e "$(rootpath)/meta"))

LAYER_PATH="$(IFS=:; echo "${_path[*]}")"


collect_layers() {
   local key="$1" val="$2"
   case $key in
      IGconf_device_layer|IGconf_image_layer|IGconf_layer_*)
         IGLAYERS+=("$val")
         ;;
   esac
}
IGLAYERS=()
mapfile_kv "$IGENVF" collect_layers


msg "\nLAYER VALIDATE : ${IGLAYERS[@]}"
msg "SEARCH ${LAYER_PATH[@]}"


runenv "$IGENVF" ig layer \
   --path "${LAYER_PATH[@]}" \
   --apply-env "${IGLAYERS[@]}" \
   --write-out "${IGTMP}/all-layers.env"  || die

cat "${IGTMP}/all-layers.env" >> "$IGENVF"


runenv "$IGENVF" ig layer \
   --path "${LAYER_PATH[@]}" \
   --validate "${IGLAYERS[@]}" || die


runenv "$IGENVF" ig layer \
   --path "${LAYER_PATH[@]}" \
   --build-order "${IGLAYERS[@]}" \
   --full-paths --output ${IGTMP}/layers.order || die


# Expand and save the final env
mapfile -t _vars < <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*' "$IGENVF")

FINALENV="${IGTMP}/final.env"
env -i bash -c '
  set -aeu    # Strict eval policy catches out of order layer variables
  source "$1"
  shift
  for n in "$@"; do
    printf "%s=\"%s\"\n" "$n" "${!n}"
  done
' _ "$IGENVF"  "${_vars[@]}" > "$FINALENV"  || die "layer env assembly"



###############################################################################
# Stage 3: Configuration
#   Vars
#   Output dirs
#   PATH
#   Prepare bdebstrap args
#     Layers, APT options, etc
#
set_kv() {
   local key="$1" val="$2"
   case $key in
      IGconf_device_assetdir|\
      IGconf_image_assetdir|\
      IGconf_image_target|\
      IGconf_image_outputdir|\
      IGconf_image_deploydir|\
      IGconf_sys_workroot)
         declare -g "$key"="$val"
         ;;
    esac
}
# Set these variables in the shell to simply further processing
mapfile_kv "$FINALENV" set_kv

# Output dirs
mkdir -p "$IGconf_image_outputdir" "$IGconf_image_deploydir" "$IGconf_sys_workroot"
mkdir -p "${IGconf_sys_workroot}/host/bin"
PATH="${IGconf_sys_workroot}/host/bin:$PATH"
export PATH


ENV_BDEBSTRAP=()
ENV_BDEBSTRAP+=('--force')
ENV_BDEBSTRAP+=('--env' PATH="$PATH")
ENV_BDEBSTRAP+=('--env' IGTOP="$(rootpath)")


has_mmdebstrap () {
python3 - <<'PY' "$1"
import sys, yaml
with open(sys.argv[1], "rb") as f:
    data = yaml.safe_load(f)
ok = isinstance(data, dict) and data.get("mmdebstrap")
sys.exit(0 if ok else 1)
PY
}


# Add layer only if it defines an mmdebstrap mapping
add_layer() {
   local layer="$1"
   local file="$2"
   msg "YAML: inspect $layer"
   if has_mmdebstrap "$file" ; then
      ENV_BDEBSTRAP+=(--config "$file")
   else
      warn "[!mmdebstrap] skipped $file"
   fi
}
msg "\nLAYER ADD"
mapfile_kv "${IGTMP}/layers.order" add_layer || die "add layer"


process_conf_opt() {
   local key="$1"
   local value="$2"
   local skip=0
   msg "-> $key : $value"
   case $key in
      IGconf_sys_apt_keydir)
         [[ -d "$value" ]] || die "$key specifies invalid dir ($value)"
         ENV_BDEBSTRAP+=(--aptopt "Dir::Etc::TrustedParts $value")
         ;;
      IGconf_sys_apt_cachedir)
         cache=$(realpath -e "$value") 2>/dev/null || die "$key specifies invalid dir ($value)"
         mkdir -p "${cache}/archives"
         ENV_BDEBSTRAP+=(--aptopt "Dir::Cache $cache")
         ENV_BDEBSTRAP+=(--aptopt "Dir::Cache::archives ${cache}/archives")
         ;;
      IGconf_sys_apt_proxy_http)
         err=$(curl --head --silent --write-out "%{http_code}" --output /dev/null "$value")
         [[ $? -ne 0 ]] && die "$key specifies unreachable proxy: ${value}"
         ENV_BDEBSTRAP+=(--aptopt "Acquire::http { Proxy \"$value\"; }")
         msg "$err $value"
         ;;
      IGconf_sys_apt_get_purge)
         if [[ ${value,,} == y?(es) ]]; then
            ENV_BDEBSTRAP+=(--aptopt "APT::Get::Purge true" )
         fi
         ;;
      IGconf_image_name)
         ENV_BDEBSTRAP+=(--name "$value")
         ;;
      IGconf_device_hostname)
         ENV_BDEBSTRAP+=(--hostname "$value")
         ;;
      IGconf_image_outputdir)
         ENV_BDEBSTRAP+=(--output "$value")
         ;;
      IGconf_image_target)
         ENV_BDEBSTRAP+=(--target "$value")
         ;;
      IGconf_device_user1)
         ENV_BDEBSTRAP+=(--env USER="$value")
         ;;
   esac
   [[ "$skip" -ne 1 ]] && ENV_BDEBSTRAP+=(--env $key="$value")
}


process_missing_conf_opt() {
    local file="$1"
    local opts=(IGconf_sys_apt_keydir)

    for opt in "${opts[@]}"; do
        value=$(get_var "$opt" "$file") && continue

        case $opt in
            IGconf_sys_apt_keydir)
               keydir=$(realpath -m "${IGconf_sys_workroot}/keys")
               mkdir -p "$keydir"
               [[ -d /usr/share/keyrings ]] && rsync -a /usr/share/keyrings/ "$keydir"
               [[ -d "$USER/.local/share/keyrings" ]] && rsync -a "$USER/.local/share/keyrings/" "$keydir"
               rsync -a "$(rootpath)/keydir/" "$keydir"
               ENV_BDEBSTRAP+=(--aptopt "Dir::Etc::TrustedParts $keydir")
               ENV_BDEBSTRAP+=(--env IGconf_sys_apt_keydir="$keydir")
               ;;
        esac
    done
}


msg "\nFINAL ENV"
mapfile_kv "$FINALENV" process_conf_opt
process_missing_conf_opt "$FINALENV"


msg READY
[[ $INTERACTIVE == y ]] && { ask "Start build?" y || exit 0; }


###############################################################################
# Stage 4: Filesystem generation
#   pre-build
#   bdebstrap
#   overlays
#   post-build
#
hook() {
   local script=$1; shift
   runhook "$script" "$FINALENV" "$@"
}


hook "$(rootpath)/image/pre-build.sh"
hook "$(rootpath)/device/pre-build.sh"


hook "${IGconf_image_assetdir}/pre-build.sh"
hook "${IGconf_device_assetdir}/pre-build.sh"


# Generate filesystem
rund $(rootpath) podman unshare bdebstrap \
   "${ENV_BDEBSTRAP[@]}" \
   --setup-hook 'bin/runner setup "$@"' \
   --essential-hook 'bin/runner essential "$@"' \
   --customize-hook 'bin/runner customize "$@"' \
   --cleanup-hook 'bin/runner cleanup "$@"'


[[ $INTERACTIVE == y ]] && { ask "Complete. Continue?" y || exit 0; }


# Apply overlays
if [ -d "$IGconf_image_target" ] ; then
   for d in "$IGconf_image_assetdir" "$IGconf_device_assetdir"; do
      if src=$(realpath -e "${d}/device/rootfs-overlay" 2>/dev/null); then
         run podman unshare rsync -a -- "${src}/" "${IGconf_image_target}/"
      fi
   done
fi


hook "${IGconf_image_assetdir}/post-build.sh" ${IGconf_image_target}
hook "${IGconf_device_assetdir}/post-build.sh" ${IGconf_image_target}


#[[ $ONLY_ROOTFS = 1 ]] && exit $?


###############################################################################
# Stage 5: SBOM and image generation
#   pre-image
#   SBOM
#   genimage
#   post-image
#
hook "${IGconf_device_assetdir}/pre-image.sh" "${IGconf_image_target}" "${IGconf_image_outputdir}"
hook "${IGconf_image_assetdir}/pre-image.sh" "${IGconf_image_target}" "${IGconf_image_outputdir}"


hook "$(rootpath)/sbom/gen.sh" "${IGconf_image_target}" "${IGconf_image_outputdir}"


GTMP=${IGTMP}/genimage
mkdir -p "$GTMP"


# Generate image(s)
for f in "${IGconf_image_outputdir}"/genimage*.cfg; do
   [[ -f "$f" ]] || continue
   runenv "$FINALENV" podman unshare env "${ENV_POST_BUILD[@]}" genimage \
      --rootpath "$IGconf_image_target" \
      --tmppath "$GTMP" \
      --inputpath "$IGconf_image_outputdir"   \
      --outputpath "$IGconf_image_outputdir" \
      --loglevel=1 \
      --config $f | pv -t -F 'Generating image...%t' || die "genimage error"
done


if [ -x ${IGconf_device_assetdir}/post-image.sh ] ; then
   hook ${IGconf_device_assetdir}/post-image.sh "$IGconf_image_deploydir"
elif [ -x ${IGconf_image_assetdir}/post-image.sh ] ; then
   hook ${IGconf_image_assetdir}/post-image.sh "$IGconf_image_deploydir"
else
   hook $(rootpath)/image/post-image.sh "$IGconf_image_deploydir"
fi

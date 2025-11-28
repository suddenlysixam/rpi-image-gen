#!/bin/bash


msg() {
   echo -e "$*"
}
export -f msg


warn (){
   >&2 msg "Warning: $*"
}
export -f warn


err (){
   >&2 msg "Error: $*"
}
export -f err


die (){
   [[ -n "$*" ]] && err "$*"
   exit 1
}
export -f die


run()
{
   env "$@"
   _ret=$?
   if [[ $_ret -ne 0 ]]
   then
      die "[$*] ($_ret)"
   fi
}
export -f run


rund()
{
   if [ "$#" -gt 1 ] && [ -d  "$1" ] ; then
      local _dir="$1"
      shift 1
      run -C "$_dir" "$@"
   fi
}
export -f rund


# Command runner with env wrapper
runenv() {
    local file=$1; shift
    [[ -r $file ]] || die "Cannot read env file '$file'"

    # collect env options
    local -a env_opts
    while (( $# )); do
        case $1 in
            -C)  env_opts+=("$1" "$2"); shift 2 ;;
            -i|-u|--ignore-environment) env_opts+=("$1"); shift ;;
            --) shift; break ;; # explicit terminate
            *)  break ;;
        esac
    done

    # remaining words are the command to run
    local -a cmd=("$@")

    # convert to kv
    local -a env_args
    while IFS='=' read -r k v; do
        env_args+=("$k=$v")
    done < <(sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d;s/"//g' "$file")

    run "${env_opts[@]}" "${env_args[@]}" "${cmd[@]}"
}
export -f runenv


# Retrieve a variable from a file containing key value pairs
get_var() {
   local key="$1" file="$2"
   local line value

   if line=$(grep "^${key}=" "$file" 2>/dev/null); then
      value="${line#*=}"
      value="${value#\"}"
      value="${value%\"}"
      [[ -n "$value" ]] && { echo "$value"; return 0; }
   fi
   return 1
}


# General purpose key=value file read with command callback
mapfile_kv() {
   local file cmd key val
   file=$1; shift || die "$0 missing file"
   cmd=$1;  shift || die "$0 missing callback"

   # Verify callback exists and is executable in this shell
   if ! type -t "$cmd" &>/dev/null; then
       die "$0 '$cmd' is not a function or executable command"
   fi

   [[ -r $file ]] || die "$0 cannot read $file"

   # FIXME use get_var
   while IFS= read -r line || [[ -n $line ]]; do
      key=${line%%=*}
      val=${line#*=}
      val=${val#\"}
      val=${val%\"}
      "$cmd" "$key" "$val" "$@" || { err "$0 exec $cmd" ; return 1 ;}
   done < "$file"
}


# One way key check in file
check_missing_keys() {
   local needles="$1" haystack="$2"

   [[ $# -eq 2 && -f "$needles" && -f "$haystack" ]] || {
       die "Need <needles> and <haystack>"
   }

   # Look in here...
   declare -A haystack_keys
   gather_haystack() { haystack_keys["$1"]=1; }
   mapfile_kv "$haystack" gather_haystack

   # ...for these.
   local missing=()
   find_needle() { [[ -z "${haystack_keys[$1]:-}" ]] && missing+=("$1"); }
   mapfile_kv "$needles" find_needle

   if [[ ${#missing[@]} -gt 0 ]]; then
       echo "Keys from '$needles' not found in '$haystack':"
       printf ' %s\n' "${missing[@]}"
       return 1
   fi

   return 0
}


# ask <prompt> [<default>]
# default: y or n   (case-insensitive). If omitted -> ‘y’.
ask () {
   local prompt=${1:-"Continue?"}
   local default=${2:-y}
   local reply

   # Build prompt string with defaults
   if [[ $default =~ ^[Yy]$ ]]; then
      prompt="$prompt [Y/n] "
   else
      prompt="$prompt [y/N] "
   fi

   while true; do
      read -r -p "$prompt" reply
      reply=${reply,,}

      # Empty reply → use default
      [[ -z $reply ]] && reply=$default

      case $reply in
         y|yes) return 0 ;; # 0 = continue
         n|no)  return 1 ;; # 1 = abort
      esac
      echo "Please answer yes or no."
   done
}


# Translates logical asset namespaces into real paths at execution time.
# This is the central namespace path resolver for the build system. Rather than
# using hard‑coded absolute paths, logical tag specs are used to translate
# them at runtime. This makes hooks, overlays, layer paths etc portable, eg
# between (host) bootstrap and (container) build.
map_path() {
   local raw=$1
   [[ $raw == *:* ]] || { printf '%s\n' "$raw"; return 0; }

   local tag=${raw%%:*}
   local rest=${raw#*:}
   local base

   # Fall back to scalar when array not present.
   # ctx doesn't exist outside of top level script
   local src_root
   if declare -p ctx &>/dev/null; then
      src_root=${ctx[SRC_DIR]:?"not set for '$raw'"}
   else
      src_root=${SRC_DIR:?"not set for '$raw'"}
   fi

   # Handler for variable or spec inside a variable
   if [[ $raw == VAR:* ]]; then
      local ref=${raw#VAR:}
      if [[ -z ${!ref+x} ]]; then
         return 1 # var not set -> ignore
      fi
      local val=${!ref}
      [[ -n $val ]] || return 1 # set but empty -> ignore

      if [[ $val == *:* ]]; then
         map_path "$val" # Yielded a spec so recurse to resolve
      else
         printf '%s\n' "$val"
      fi
      return 0
   fi

   case $tag in
      IGROOT)
         base=${IGTOP:?"not set for $raw"}
         ;;
      IGROOT_*)
         base="${IGTOP:?"not set for $raw"}/${tag#IGROOT_}"
         ;;
      SRCROOT)
         base=$src_root
         ;;
      SRCROOT_*)
         base="${src_root}/${tag#SRCROOT_}"
         ;;
      DEVICE_ASSET)
         [[ -n ${IGconf_device_assetdir:-} ]] || return 1
         base=${IGconf_device_assetdir}
         ;;
      IMAGE_ASSET)
         [[ -n ${IGconf_image_assetdir:-} ]] || return 1
         base=${IGconf_image_assetdir}
         ;;
      TMPROOT_layer)
         [[ -n ${ctx[DYN_LAYER_DIR]:-} ]] || return 1
         base=${ctx[DYN_LAYER_DIR]}
         ;;
      TARGETDIR)
         [[ -n ${IGconf_target_dir:-} ]] || return 1
         base=${IGconf_target_dir}
         ;;
      *)
         printf '%s\n' "$raw"
         return 0
         ;;
   esac

   if [[ -z $rest || $rest == "." ]]; then
      printf '%s\n' "$base"
   elif [[ $rest == /* ]]; then
      printf '%s\n' "$(realpath -m "$rest")"
   else
      printf '%s\n' "$(realpath -m "$base/$rest")"
   fi
}
export -f map_path

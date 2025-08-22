#!/bin/bash


validate_dir() {
   [[ $# -eq 1 ]] || { >&2 echo "missing dir argument" ; return 1; }
   [[ -d "$1" ]] || { >&2 echo "${1:-}: not a directory" ; return 1; }
   realpath -e "$1" 2>/dev/null || { >&2 echo "${1:-}: cannot resolve dpath" ; return 1; }
}


validate_file() {
   [[ $# -eq 1 ]] || { >&2 echo "missing file argument" ; return 1; }
   [[ -f "$1" ]] || { >&2 echo "${1:-}: not a file" ; return 1; }
   realpath -e "$1" 2>/dev/null || { >&2 echo "${1:-}: cannot resolve fpath" ; return 1; }
}


cli_help()
{
cat <<-EOF >&2

Raspberry Pi filesystem and image generation utility.

Usage:
  $(basename $(readlink -f "$0")) [cmd] [options]
  $(basename $(readlink -f "$0")) -h|--help

Supported commands:
  help                Show this help message
  build    [options]    Filesystem and image construction
  clean    [options]    Clean work tree
  layer    [options]    Layer operations (delegated)
  metadata [options]    Layer metadata operations (delegated)
  config   [options]    Config file operations (delegated)

Delegated commands are processed by the core engine helper (bin/ig).

For command-specific help, use: $(basename $(readlink -f "$0")) <cmd> -h
EOF
}


cli_help_build()
{
cat <<-EOF >&2
Usage
  $(basename $(readlink -f "$0")) build [options] [-- IGconf_key=value ...]

Options:
  [-c <config>]    Path to config file.
  [-S <src dir>]   Directory holding custom sources of config, profile, image
                   layout and layers.
  [-B <build dir>] Use this as the root directory for generation and build.
                   Sets IGconf_sys_workroot.
  [-I]             Interactive. Prompt at different stages.

  Developer Options
  [-f]             setup, build filesystem, skip image generation.
  [-i]             setup, skip building filesystem, generate image(s).

  IGconf Variable Overrides:
    Use -- to separate options from overrides.
    Any number of key=value pairs can be provided.
    Use single quotes to enable variable expansion.
EOF
}


# Handler for build command options
# Arguments: 1 = nameref to a context array ; remaining = CLI args.
cli_parse_build() {
   local -n __ctx=$1
   shift

   local OPTIND flag
   while getopts "B:c:fhiIS:" flag; do
      case $flag in
         B)  __ctx[BUILD_DIR]=$(validate_dir "$OPTARG") || { cli_help_build; exit 1; } ;;
         c)  __ctx[INCONFIG]="$OPTARG" ;;
         f)  __ctx[ONLY_FS]=1     ;;
         h)  cli_help_build ; exit 0 ;;
         i)  __ctx[ONLY_IMAGE]=1  ;;
         I)  __ctx[INTERACTIVE]=y ;;
         S)  __ctx[SRC_DIR]=$(validate_dir "$OPTARG") || { cli_help_build; exit 1; } ;;
         *)  cli_help_build ; exit 1 ;;
      esac
   done

   return $((OPTIND-1))
}


cli_help_clean()
{
cat <<-EOF >&2
Usage
  $(basename $(readlink -f "$0")) clean [options]

Options:
  [-c <config>]    Path to config file.
  [-B <build dir>] The top level build dir to run clean operations in.
EOF
}


# Handler for clean command options
# Arguments: 1 = nameref to a context array ; remaining = CLI args.
cli_parse_clean() {
   local -n __ctx=$1
   shift

   local OPTIND flag
   while getopts "B:c:hIS:" flag; do
      case $flag in
         B)  __ctx[BUILD_DIR]=$(validate_dir "$OPTARG") || { cli_help_build; exit 1; } ;;
         c)  __ctx[INCONFIG]="$OPTARG" ;;
         h)  cli_help_clean ; exit 0 ;;
         I)  __ctx[INTERACTIVE]=y ;;
         S)  __ctx[SRC_DIR]=$(validate_dir "$OPTARG") || { cli_help_build; exit 1; } ;;
         *)  cli_help_clean ; exit 1 ;;
      esac
   done

   return $((OPTIND-1))
}


cli_help_layer()
{
cat <<-EOF >&2
Usage
  $(basename $(readlink -f "$0")) layer [options] ...

Options:
  [-S <src dir>]   Directory holding custom sources of config, profile, image
                   layout and layers.
  <...>            All other arguments are passed through.

  This is a delegated command, meaning that it passes all other args straight
  through to the engine for processing. Use -h to see available options.


EOF
}


# Handler for layer command options
# Arguments: 1 = nameref to a context array ; remaining = CLI args.
cli_parse_layer() {
   local -n _ctx=$1; shift
   local processed=0

   # We consume some args and pass through others
   while [[ $# -gt 0 ]]; do
      case $1 in
         -S)
            if [[ $# -lt 2 ]]; then
               printf 'option -S needs an argument\n' >&2
               cli_help_layer ; exit 1
            fi
            _ctx[SRC_DIR]=$(validate_dir "$2") || { cli_help_layer ; exit 1 ; }
            shift 2
            processed=2 # consumed opt + path
            ;;
         -h)
            cli_help_layer
            # Don't consume -h, pass through
            break
            ;;
         *)
            # Don't care. Pass through
            break
            ;;
      esac
   done

   return $processed
}


cli_help_metadata()
{
cat <<-EOF >&2
Usage
  $(basename $(readlink -f "$0")) metadata [options] ...

  This is a delegated command, meaning that it passes all args straight
  through to the engine for processing. Use -h to see available options.

EOF
}


# Handler for metadata command options
# Arguments: 1 = nameref to a context array ; remaining = CLI args.
cli_parse_metadata() {
   local -n _ctx=$1 # unused
   shift

   # Only need to support -h
   if [[ $# -gt 0 && "$1" == "-h" ]]; then
      cli_help_metadata
   fi
   return 0 # Pass through everything without consuming
}


cli_help_config()
{
cat <<-EOF >&2
Usage
  $(basename $(readlink -f "$0")) config [options] ...

  This is a delegated command, meaning that it passes all args straight
  through to the engine for processing. Use -h to see available options.

EOF
}


# Handler for config command options
# Arguments: 1 = nameref to a context array ; remaining = CLI args.
cli_parse_config() {
   local -n _ctx=$1 # unused
   shift

   # Only need to support -h
   if [[ $# -gt 0 && "$1" == "-h" ]]; then
      cli_help_config
   fi
   return 0 # Pass through everything without consuming
}

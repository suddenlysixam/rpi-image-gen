#!/bin/bash


cli_help()
{
cat <<-EOF >&2

Raspberry Pi filesystem and image generation utility.

Usage:
  $(basename $(readlink -f "$0")) [cmd] [options]
  $(basename $(readlink -f "$0")) -h|--help

Supported commands:
  help               Show this help message
  build [options]    Filesystem and image construction
  clean [options]    Clean work tree
  layer [options]    Layer operations (delegated)
  meta  [options]    Metadata operations (delegated)

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
  [-f]             Run setup, build filesystem, skip image generation.
  [-i]             Run setup, skip filesystem, generate image(s).

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
         B)  __ctx[BUILD_DIR]=$(realpath --canonicalize-missing "$OPTARG") ;;
         c)  __ctx[INCONFIG]=$OPTARG                                     ;;
         f)  __ctx[ONLY_FS]=1                                        ;;
         i)  __ctx[ONLY_IMAGE]=1                                         ;;
         I)  __ctx[INTERACTIVE]=y                                        ;;
         S)  __ctx[SRC_DIR]=$(realpath --canonicalize-missing "$OPTARG") ;;
         h)  cli_help_build ; exit 0 ;;
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
  [-B <build dir>] Use this as the root directory for generation and build.
                   Sets IGconf_sys_workroot.
EOF
}


# Handler for clean command options
# Arguments: 1 = nameref to a context array ; remaining = CLI args.
cli_parse_clean() {
   local -n __ctx=$1
   shift

   local OPTIND flag
   while getopts "B:c:h" flag; do
      case $flag in
         B)  __ctx[BUILD_DIR]=$(realpath --canonicalize-missing "$OPTARG") ;;
         c)  __ctx[INCONFIG]=$OPTARG                                     ;;
         h)  cli_help_clean ; exit 0 ;;
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

   OPTERR=0
   local OPTIND flag
   while getopts ':S:h' flag; do
      case $flag in
         S) _ctx[SRC_DIR]=$(realpath --canonicalize-existing "$OPTARG") ;;
         h) cli_help_layer
            OPTIND=$((OPTIND- 1))
            break ;;
         \?)break ;;  # pass through
         :) printf 'option -%s needs an argument\n' "$OPTARG" >&2
            cli_help_layer ;;
      esac
   done
   return $((OPTIND-1))
}

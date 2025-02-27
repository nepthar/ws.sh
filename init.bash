# init.bash - ws.sh setup for bash

# Check if running in bash and being sourced
if [[ -z "$BASH_VERSION" ]]; then
  echo "ws.sh: init.bash is for bash only" >&2
  return 1
fi

(return 0 2>/dev/null) && sourced=true || sourced=false
if [[ "$sourced" == "false" ]]; then
  echo "ws.sh: init.bash must be sourced rather than run" >&2
  exit 1
fi


# # Ensure that this is being sourced by bash, rather than being run
# # directly as a script or otherwise in a different shell.
# if (return 0 2>/dev/null) [[ "$0" != "-bash" ]]; then
#   echo "ws.sh: init.bash must be sourced by bash rather than run"
#   return
# fi

# Use the path of this file to determine where ws.sh is installed to.
if [[ $BASH_SOURCE == *"/ws.sh/init.bash" ]]; then
  ws_root="${BASH_SOURCE%%/init.bash}"
else
  echo "ws.sh: Unable to determine ws.sh location. Please provide a full path when sourcing init.bash. Got: \"$BASH_SOURCE\"" >&2
  return 1
fi

# Configuration
export workspace
ws_spaces="${ws_root}/known"
ws_home=
ws_funcs=()
ws_file=
ws_prefix=

# Helper functions
_ws.is_active() { [[ -n "$workspace" ]]; }

_ws.resolve_file() {
  local path
  
  # No argument - check current directory
  if [[ -z $1 ]]; then
    path="./workspace.sh"
  # Literal workspace file
  elif [[ "$1" == *"workspace.sh" ]]; then
    path="$1"
  # Known workspace
  elif [[ -L "${ws_spaces}/${1}.ws" ]]; then
    path="${ws_spaces}/${1}.ws"
  # Directory containing workspace.sh
  elif [[ -f "${1}/workspace.sh" ]]; then
    path="${1}/workspace.sh"
  else
    return 1
  fi
  
  # Return absolute path if file exists and is readable
  [[ -r "$path" ]] && readlink -f "$path" || return 1
}

_ws.template() {
  sed -e "s/{NAME}/$1/g" "${ws_root}/workspace.template"
}

_ws.active() {
  local cmd="$1"
  local dot_command="${ws_prefix}.${cmd}"

  # Run without arguments, just cd to workspace root
  if [[ -z $cmd ]]; then
    cd "$ws_home"
    return
  fi

  shift 1

  if type -t "$dot_command" &>/dev/null; then
    $dot_command "$@"
  elif [[ "$cmd" == "help" ]]; then
    ws.help
  else
    echo "Command not found: $cmd" >&2
    return 1
  fi
}

_ws.inactive() {
  case "$1" in
    "new") shift; ws.new "$@" ;;
    "add") ws.add "$2" ;;
    *) ws.enter "$@" ;;
  esac
}

_ws.tab_comp_inactive() {
  local cur=${COMP_WORDS[COMP_CWORD]}
  local words=()
  
  # Use nullglob to handle case when no files match
  shopt -s nullglob
  for file in "${ws_spaces}"/*.ws; do
    words+=("${file##*/}")
    words[-1]="${words[-1]%.ws}"
  done
  shopt -u nullglob
  
  COMPREPLY=($(compgen -W "${words[*]}" -- "$cur"))
}

# Public functions
## ws.info
## Dumps information about the workspace state
ws.info() {
  cat <<EOF
ws name:   $workspace
ws_root:   $ws_root
ws_home:   $ws_home
ws_funcs:  (${ws_funcs[*]})
ws_file:   $ws_file
ws_prefix: $ws_prefix
EOF
}

## Displays the help strings for all available commands
ws.help() {
  echo "$workspace workspace Commands:"
  grep -E "^(##|${ws_prefix}\.)" "$ws_file" | while read -r line; do
    case "$line" in
      '##'* ) help="${line:3}" ;;
      "${ws_prefix}"* ) printf " - %-20s %s\n" "${line%%\(*}" "$help" ;;
    esac
  done
}

## ws.ls
## List known workspaces
ws.ls() {
  echo "Spaces in ${ws_spaces}:"
  ls -1 "${ws_spaces}"
}

## ws.new (name)
## Create a new workspace in the current folder with a given name. If
## name is not provided, the name of the folder will be used.
ws.new() {
  local new_name="${1:-${PWD##*/}}"
  local tail="(enter to continue, ctrl+c to stop)"
  local throwaway

  if [[ -f workspace.sh ]]; then
    echo "workspace.sh already exists" >&2
    return 1
  fi

  if ! read -r -p "Create \"$new_name\" @ ${PWD}? $tail" throwaway; then
    echo "canceled."
    return 1
  fi

  _ws.template "$new_name" > workspace.sh
  echo "$new_name created in workspace.sh"

  read -r -p "Enter $new_name? $tail" throwaway || return 0
  ws.enter

  read -r -p "Add $new_name? $tail" throwaway || return 0
  ws.add
}

## ws.enter (name/filename)
## Enter into a workspace. If (name/filename) is provided, it will be looked up
## in linked workspaces. If not, the workspace in the current dir will be used.
ws.enter() {
  local possible_file

  if _ws.is_active; then
    echo "Already in workspace: $workspace" >&2
    return 1
  fi

  # Resolve workspace file path
  if ! possible_file="$(_ws.resolve_file "$1")"; then
    echo "Unable to resolve workspace from \"$1\"" >&2
    return 1
  fi

  ws_file="$possible_file"
  ws_home="${ws_file%/*}"

  # Enter the workspace
  if ! { cd "$ws_home" && source "$ws_file" && [[ -n "$workspace" ]]; }; then
    echo "Failed to enter workspace. Note that workspace files must set \$workspace." >&2
    ws.info >&2
    return 1
  fi

  ws_prefix=${ws_prefix:-$workspace}

  # Generate command list for tab completion
  mapfile -t ws_funcs < <(
    declare -F | 
    cut -d' ' -f3 | 
    grep "^${ws_prefix}\." | 
    sed -e "s/^${ws_prefix}\.//" -e "s/^root\.//"
  )

  # Set up command alias and tab completion
  alias ,=_ws.active
  complete -W "${ws_funcs[*]}" ,

  # Define refresh function within the workspace context
  ws.refresh() {
    unset workspace
    if ws.enter "$ws_file"; then
      echo "Refreshed workspace from ${ws_file}"
    else
      echo "Failed. Workspace is likely in a broken state." >&2
      return 1
    fi
  }
}

## ws.add
## Add a link to the active workspace in $ws_spaces
ws.add() {
  if ! _ws.is_active; then
    echo "You must be in an active workspace to add it to your known spaces" >&2
    return 1
  fi

  local linkname="${ws_spaces}/${workspace}.ws"
  mkdir -p "$ws_spaces"
  
  echo "Link $workspace: $ws_file -> ${ws_spaces}"
  ln -sf "$ws_file" "$linkname"
}

# Setup
alias ,=_ws.inactive
complete -F _ws.tab_comp_inactive ,
mkdir -p "$ws_spaces"

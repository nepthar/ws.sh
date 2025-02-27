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
  echo "ws.sh: Unable to figure out where ws.sh is located. Please" \
    "provide a full path when sourcing init.bash." \
    "Got: \"$BASH_SOURCE\". Workspaces cannot be set up." >&2
  return 1
fi

# Pass the workspace name to subprocesses
export workspace

# Configuration
ws_spaces="${ws_root}/known"
ws_home=
ws_funcs=()
ws_file=
ws_prefix=

## ws.info
## Dumps information about the workspace state
ws.info()
{
  echo "ws name:   $workspace"
  echo "ws_root:   $ws_root"
  echo "ws_home:   $ws_home"
  echo "ws_funcs:  (${ws_funcs[@]})"
  echo "ws_file:   $ws_file"
  echo "ws_prefix: $ws_prefix"
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
ws.ls()
{
  echo "Spaces in ${ws_spaces}:"
  ls "${ws_spaces}"
}

## ws.new (name)
## Create a new workspace in the current folder with a given name. If
## name is not provided, the name of the folder will be used.
ws.new()
{
  local new_name="$1"
  local new_home="$PWD"
  local throwaway
  local tail="(enter to continue, ctrl+c to stop)"

  if [[ -z $new_name ]]; then
    new_name="${new_home##*/}"
  fi

  if [[ -f workspace.sh ]]; then
    echo "workspace.sh already exists"
    return 1
  fi

  if ! read -r -p "Create Create \"$new_name\" @ ${new_home}? $tail" throwaway; then
    echo "canceled."
    return 1
  fi

  _ws.template $new_name > workspace.sh

  echo "$new_name created in $new_file."

  read -r -p "Enter $new_name? $tail" throwaway || return 0
  ws.enter

  read -r -p "Add $new_name? $tail" throwaway || return 0
  ws.add
}

## ws.enter (name/filename)
## Enter into a workspace. If (name/filename) is provided, it will be looked up
## in linked workspaces. If not, the workspace in the current dir will
## be used.
ws.enter()
{
  local possible_file

  if _ws.is_active; then
    echo "Already in workspace: $workspace"
    return 1
  fi

  # This will either resolve to the full path of a readable file or fail.
  if ! possible_file="$(_ws.resolve_file "$1")"; then
    echo "Unable to resolve workspace from \"$1\""
    return 1
  fi

  ws_file="$possible_file"
  ws_home="${ws_file%/*}"

  # There's very little we can do to see if we entered a "valid" workspace
  # or just sourced a file. In reality, this is enough as, after all, a
  # workspace is just a collection of scripts.
  if ! {
    cd "$ws_home" &&
    source "$ws_file" &&
    test $workspace; # tests if $workspace is not empty
  } ; then
    echo \
      "Failed to enter workspace. Shell is probbably in a bad state" \
      "and should be closed. Note that workspace files must set \$workspace." \
      "Additional info:" >&2
    ws.info >&2
    return 1
  fi

  ws_prefix=${ws_prefix:-$workspace}

  # Sourcing the file & running init seems to have gone OK.
  # Generate the list of commands for tab complete
  ws_funcs=($(
    for funcname in $(declare -F | cut -c12- | grep "^${ws_prefix}\."); do
      funcname=${funcname#${ws_prefix}.}
      echo ${funcname#"root."}
    done
  ))


  # Project entry mapping & tab completion
  alias ,=_ws.active
  complete -W "${ws_funcs[*]}" ,

  # debug:
  # echo "ws_file=$ws_file, workspace=$workspace, ws_funcs=(${ws_funcs[@]})" >&2

  ws.refresh()
  {
    unset workspace
    if ws.enter "$ws_file"; then
      echo "Refreshed workspace from ${ws_file}"
    else
      echo "Failed. Workspace is likely in a broken state, close the terminal"
      return 1
    fi
  }
}

## ws.add
## Add a link to the active workspace in $ws_spaces
ws.add()
{
  if ! _ws.is_active; then
    echo "You must be in an active workspace to add it to your known spaces"
    return 1
  fi

  local linkname="${ws_spaces}/${workspace}.ws"

  echo "Link $workspace: $ws_file -> ${ws_spaces}"
  ln -s "$ws_file" "$linkname"
}

_ws.active()
{
  # Forward the command
  local cmd="$1"

  local dot_command="${ws_prefix}.${cmd}"

  # Run without arguments, just cd to the root of the workspace
  if [[ -z $cmd ]]; then
    cd "$ws_home"
    return
  fi

  shift 1

  if isfunc $dot_command; then
    $dot_command "$@"
  elif [[ "$cmd" == "help" ]]; then
    ws.help
  else
    echo "$cmd not found"
    return 1
  fi
}

_ws.inactive()
{
  case "$1" in
    "new")
      shift 1
      ws.new "$@"
      ;;
    "add")
      ws.add "$2"
      ;;
    *)
      ws.enter "$@"
      ;;
  esac
}

_ws.is_active()
{
  # Check if $workplace is set
  test $workspace
}

_ws.tab_comp_inactive()
{
  # When not in a workspace, generate a list of known workspaces
  local cur
  local words

  cur=${COMP_WORDS[COMP_CWORD]}

  words=$(
  for file in ${ws_spaces}/*.ws; do
    f1="${file%.*}"
    echo "${f1##*/}"
  done)

  COMPREPLY=($(compgen -W "$words" -- $cur))
}

# Resolve a token to an absolute file path of a file that exists
_ws.resolve_file()
{
  if [[ -z $1 ]]; then
    # No argument given - check only if the workspace file
    # exists right here.
    readlink -f ./workspace.sh
    return $?
  fi

  # See if it's a literal workspace file that exists
  if [[ "$1" == *"workspace.sh" ]]; then
    readlink -f "$1" && return 0
  fi

  # See if it's a known workspace
  readlink -f "${ws_spaces}/${1}.ws" && return 0

  # See if it's the folder containing a workspace.sh file
  readlink -f "${1}/workspace.sh" && return 0

  # Otherwise, we cannot resolve
  return 1
}

_ws.template() {
  sed -e "s/{NAME}/$1/g" "${ws_root}/workspace.template"
}

alias ,=_ws.inactive
complete -F _ws.tab_comp_inactive ,
mkdir -p "$ws_root"

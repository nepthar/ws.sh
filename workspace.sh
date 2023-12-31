#!/usr/bin/env bash
workspace="ws"

# Shell Workspace File
# This is designed to be used with github.com/nepthar/ws.sh for "magic",
# it can be sourced from bash, or it can be executed directly.

# Variables & Functions
ws.say-hello() {
  echo "Hello from $workspace in $PWD"
}

# Run a command if this is being executed instead of sourced.
if [[ "$0" == *workspace.sh ]]; then
  funcname="${workspace}.${1}"
  shift 1
  cd $(dirname $0)
  $funcname "$@"
fi

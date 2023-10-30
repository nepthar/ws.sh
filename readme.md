ws.sh - Shell Workspaces
------------------------
Workspaces keep your projects organized and easily accessable from the
shell as well as provides a place to put common operations. The comma
(,) is used as a new command to access workspace functionality. This
functionality all lives in a `workspace.sh` file at the root of the
project.

When one "enters" a workspace, the `workspace.sh` file is sourced and
the functions within it can be dispatched (with tab completion) with
the command command.

If the user does not have `ws.sh` then the workspace.sh file simply is
a useful, bash-sourceable list of functions related to your project.
This was an intentional design choice to ensure usefulness without
forcing folks to install another dependency.


Installation
------------
Right now, this only supports bash on macos. Pull requests welcome!
1) Clone this repository somewhere (ex: `${HOME}/local/ws.sh`.)
2) Source `init.bash` in your `~/.profile`
(ex: `source ${HOME}/local/ws.sh/init.bash`).sd


Usage
-----

Create a new workspace for your project:
1) `$ cd ~/my/project/folder`
2) `$ , new`


Start working in a workspace:
1) `$ , [workspace name] or [workspace file]`
  -  Tab completion works for selecting a workspace. Woohoo!
  -  The command (,) by itself will return you to the workspace's home


Link up the current workspace to `$ws_root/known` for quick access.
1) `$ ws.add # (from within the workspace)`


Finish working in a workspace:
1) Close the shell. There's no "exiting"


If you have made changes to the workspace.sh file and would like to
"re enter" the workspace, `,,` will attempt to refresh things. Note that
it isn't smart enough to un-define variables and functions that you've
removed.


The workspace.sh file
---------------------
- This file is sourced every time upon entering a workspace, so any
commands that are in there will be executed each time.

- Functions using the dot notation of `${workspace}.${function name}`
(for example: `railsapp.run-tests`) will become discoverable by tab
completion with the comma command.

- If your workspace name is long, you can change function prefix by
setting `$ws_pre`.

- Functions just defined normally are handled normally

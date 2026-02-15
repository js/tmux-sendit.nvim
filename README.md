# Tmux Send It

Send selected buffer contents or filepath to another tmux pane

`:SenditSelection` - Uses the current selection for sendit
`:SenditPath` - Uses the current relative, to the project root file path for sendit
`:SenditFullPath` - Uses the full path

After executing the commit a picker will be presented where a target tmux pane can be selected for the selected content to be inserted into, as if you typed in to that pane

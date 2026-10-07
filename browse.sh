#!/bin/bash
# Opens a file chooser for .gguf models and adds each verified pick via setmodel.sh addpath.
dir=$(dirname "$0")
if python3 -c "import gi" 2>/dev/null; then
  picks=$(python3 "$dir/pick.py")
elif command -v zenity >/dev/null; then
  picks=$(zenity --file-selection --multiple --separator=$'\n' --file-filter='GGUF models | *.gguf' --title='Select a .gguf model')
elif command -v kdialog >/dev/null; then
  picks=$(kdialog --getopenfilename "$HOME/models" '*.gguf|GGUF models' --multiple --separate-output)
else
  echo "err: no file chooser found (install python-gobject or zenity) — paste the path in Settings instead"; exit 0
fi
while IFS= read -r f; do [ -n "$f" ] && "$dir/setmodel.sh" addpath "$f"; done <<< "$picks"

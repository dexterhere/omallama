#!/bin/bash
# usage: setmodel.sh model <path> | ctx <n> | set <KEY> <value> [norestart]
#        setmodel.sh addpath <file|dir> | rmpath <file|dir> | login on|off
# Settings live in ~/.config/omallama/env (read by omallama.service).
cfg=$HOME/.config/omallama
f=$cfg/env list=$cfg/models.list
mkdir -p "$cfg"; touch "$f" "$list"
# Values end up in line-based files (env, models.list): refuse anything that could add a line.
for a in "$@"; do [[ $a == *[[:cntrl:]]* ]] && { echo "err: control characters are not allowed"; exit 0; }; done
set_kv() { [[ $1 =~ ^LLM_[A-Z]+$ ]] || { echo "err: bad key"; return; }; grep -v "^$1=" "$f" > "$f.tmp"; echo "$1=$2" >> "$f.tmp"; mv "$f.tmp" "$f"; }
restart() { systemctl --user is-active --quiet omallama && systemctl --user restart omallama; }
case $1 in
  model) set_kv LLM_MODEL "$2"; set_kv LLM_ALIAS "$(basename "$2" .gguf)"; restart ;;
  ctx) set_kv LLM_CTX "$2"; restart ;;
  set) set_kv "$2" "$3"; [ "$4" = norestart ] || restart ;;
  addpath)
    p=${2/#\~/$HOME}; p=$(realpath -m -- "$p")
    if [ -d "$p" ] || { [ -f "$p" ] && [[ ${p,,} == *.gguf ]] && [ "$(head -c4 "$p")" = GGUF ]; }; then
      grep -qxF -- "$p" "$list" || echo "$p" >> "$list"; echo "ok: added ${p##*/}"
    elif [ -f "$p" ]; then echo "err: ${p##*/} is not a valid GGUF model"
    else echo "err: path not found"; fi ;;
  rmpath) grep -vxF -- "$2" "$list" > "$list.tmp"; mv "$list.tmp" "$list" ;;
  login) systemctl --user "$([ "$2" = on ] && echo enable || echo disable)" omallama 2>/dev/null ;;
esac
exit 0

#!/bin/bash
# Local GGUFs as "bytes|realpath" and cached models as "bytes|hf:repo:quant".
# Skips projectors and non-first shards (llama.cpp loads the rest from shard 1).
. "$(dirname "$0")/lib.sh"
list=$cfg/models.list
# Keep snapshot filenames for quant matching; only stat follows the blob symlink.
cache_bytes() {
  local model=$1 repo quant root revision f stem bytes total=0
  repo=${model%%:*} quant=${model#*:}
  [ "$quant" != "$model" ] || { echo 0; return; }
  root=${HF_HUB_CACHE:-${HF_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/huggingface}/hub}/models--${repo//\//--}
  revision=$(head -n1 "$root/refs/main" 2>/dev/null)
  [[ $revision =~ ^[[:xdigit:]]+$ && -d $root/snapshots/$revision ]] || { echo 0; return; }
  while IFS= read -r -d '' f; do
    stem=${f##*/}; stem=${stem,,}; stem=${stem%.gguf}
    [[ $stem == *mmproj* ]] && continue
    # Sum all shards, not just the first file, for split GGUFs.
    [[ $stem =~ -[0-9]{5}-of-[0-9]{5}$ ]] && stem=${stem%-?????-of-?????}
    case $stem in
      "${quant,,}"|*[-_.]"${quant,,}")
        bytes=$(stat -Lc %s -- "$f" 2>/dev/null) || continue
        total=$((total + bytes)) ;;
    esac
  done < <(find "$root/snapshots/$revision" \( -type l -o -type f \) -iname '*.gguf' -print0 2>/dev/null)
  echo "$total"
}

bin=$(find_bin)
if [ -n "$bin" ]; then
  args=()
  [ "${bin##*/}" = llama ] && args=(cli)
  timeout 15 "$bin" "${args[@]}" --cache-list 2>/dev/null |
    sed -nE 's/^[[:space:]]*[0-9]+\.[[:space:]]+([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(:[A-Za-z0-9_.-]+)?)[[:space:]]*$/\1/p' | sort -u |
    while IFS= read -r model; do printf '%s|hf:%s\n' "$(cache_bytes "$model")" "$model"; done
fi
candidates() {
  local d
  # Scan local files, not hash-named cache blobs; cache names come from llama above.
  for d in "$HOME/models" "$HOME/Models" \
    "$HOME/.lmstudio/models" "$HOME/.local/share/nomic.ai" "$HOME/.local/share/jan" "$HOME/.local/share/gpt4all" \
    "$HOME/Downloads" "$HOME/Documents" "$HOME/Desktop" "$HOME/ai" \
    /opt /srv /mnt /run/media; do
    [ -d "$d" ] && find -L "$d" -xdev -maxdepth 8 -type f -iname '*.gguf' -size +20M -print0 2>/dev/null
  done
  # Shallow sweep of the rest of $HOME, skipping hidden and build directories.
  find "$HOME" -xdev -maxdepth 3 \( -name '.*' -o -name node_modules -o -name target -o -name build -o -name venv \) -prune \
    -o -type f -iname '*.gguf' -size +20M -print0 2>/dev/null
  while IFS= read -r p; do
    # Absolute paths only: a relative entry such as "-delete" would be parsed by find as an option.
    [[ $p == /* ]] || continue
    if [ -d "$p" ]; then find -L "$p" -maxdepth 8 -type f -iname '*.gguf' -print0 2>/dev/null
    elif [ -f "$p" ]; then printf '%s\0' "$p"; fi
  done 2>/dev/null < "$list"
}
candidates | xargs -0 -r realpath -z -- 2>/dev/null | sort -zu |
  while IFS= read -r -d '' f; do
    # Output is one "bytes|path" record per line, so a path with a newline could forge records.
    [[ $f == *[[:cntrl:]]* ]] && continue
    b=${f##*/}
    case ${b,,} in *mmproj*) continue ;; esac
    if [[ $b =~ -([0-9]{5})-of-[0-9]{5}\.gguf$ && ${BASH_REMATCH[1]} != 00001 ]]; then continue; fi
    echo "$(stat -c %s "$f")|$f"
  done

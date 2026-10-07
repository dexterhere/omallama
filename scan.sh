#!/bin/bash
# Every GGUF model on the machine as "bytes|realpath", plus anything the user added
# in the settings (files or folders in models.list). Skips vision projectors and
# non-first shards of split models (llama.cpp loads the rest from shard 1).
list=$HOME/.config/omallama/models.list
candidates() {
  local d
  # Where model apps keep GGUF files; symlinks are followed (Hugging Face snapshots are links).
  for d in "$HOME/models" "$HOME/Models" "$HOME/.cache/huggingface/hub" "$HOME/.cache/llama.cpp" \
    "$HOME/.lmstudio/models" "$HOME/.local/share/nomic.ai" "$HOME/.local/share/jan" "$HOME/.local/share/gpt4all" \
    "$HOME/.local/share/llama.cpp" "$HOME/Downloads" "$HOME/Documents" "$HOME/Desktop" "$HOME/ai" \
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
  done < "$list" 2>/dev/null
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

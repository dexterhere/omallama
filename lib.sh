# Shared helpers, sourced by sample.sh, doctor.sh and setup.sh.
cfg=$HOME/.config/omallama

# Prefer the llama dispatcher, with standalone llama-server as a fallback.
find_bin() {
  local c
  for c in "$(command -v llama)" "$HOME/.local/bin/llama" "$HOME/llama.cpp/build/bin/llama" \
    "$HOME/Work/llama.cpp/build/bin/llama" "$HOME/src/llama.cpp/build/bin/llama" /usr/local/bin/llama /opt/llama.cpp/bin/llama \
    "$(grep -m1 '^LLM_BIN=' "$cfg/env" 2>/dev/null | cut -d= -f2-)" "$(command -v llama-server)" \
    "$HOME/.local/bin/llama-server" "$HOME/llama.cpp/build/bin/llama-server" \
    "$HOME/Work/llama.cpp/build/bin/llama-server" "$HOME/src/llama.cpp/build/bin/llama-server" \
    /usr/local/bin/llama-server /opt/llama.cpp/bin/llama-server; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return; }
  done
  find "$HOME" -xdev -maxdepth 5 \( -name node_modules -o -name .git -o -name .cache -o -name .npm -o -name .cargo -o -name .rustup -o -name target \) -prune \
    -o \( -name llama -o -name llama-server \) -type f -perm -u+x -print -quit 2>/dev/null
}

# Picks the best GPU from sysfs: sets GPU_KIND (nvidia|amd|intel|none), GPU_INT (1 = integrated), GPU_CARD.
# Preference: NVIDIA > discrete AMD > Intel Arc > AMD APU > Intel iGPU.
detect_gpu() {
  GPU_KIND=none GPU_INT=0 GPU_CARD= GPU_SLOT=
  local best=-1 d slot vram score kind int
  for d in "${OMALLAMA_DRM:-/sys/class/drm}"/card[0-9]*/device; do
    [ -r "$d/vendor" ] && [[ $(cat "$d/class" 2>/dev/null) == 0x03* ]] || continue
    slot=$(basename "$(readlink -f "$d")")
    case $(cat "$d/vendor") in
      0x10de) kind=nvidia int=0 score=4 ;;
      0x1002) kind=amd; vram=$(cat "$d/mem_info_vram_total" 2>/dev/null || echo 0)
              # APUs carve a small slice out of system RAM; real cards have several GiB of their own.
              if [ "$vram" -lt 3221225472 ]; then int=1 score=1; else int=0 score=3; fi ;;
      0x8086) kind=intel; if [[ $slot == 0000:00:02.* ]]; then int=1 score=0; else int=0 score=2; fi ;;
      *) continue ;;
    esac
    if [ "$score" -gt "$best" ]; then best=$score GPU_KIND=$kind GPU_INT=$int GPU_CARD=$d GPU_SLOT=$slot; fi
  done
}

# Human name of the chosen GPU, e.g. "NVIDIA GeForce RTX 4050 Max-Q / Mobile".
gpu_name() {
  [ -n "$GPU_SLOT" ] && command -v lspci >/dev/null || { echo "${GPU_KIND^} graphics"; return; }
  lspci -s "${GPU_SLOT#0000:}" 2>/dev/null | sed -E 's/^[^ ]* [^:]*: //; s/ \(rev.*//' |
    sed -E 's/^Advanced[^[]*\[AMD\/ATI\][^[]*/AMD /; s/^([A-Za-z]+)[^[]*\[([^]]+)\][^[]*$/\1 \2/'
}

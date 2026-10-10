#!/bin/bash
# Environment check for the onboarding view, as key=value lines.
. "$(dirname "$0")/lib.sh"
bin=$(find_bin)
echo "bin=$bin"
if [ -n "$bin" ]; then
  args=()
  [ "${bin##*/}" = llama ] && args=(serve)
  echo "bin_version=$("$bin" "${args[@]}" --version 2>&1 | grep -i -m1 version | sed 's/^version: *//')"
  echo "devices=$(timeout 15 "$bin" "${args[@]}" --list-devices 2>&1 | grep -oE '^ *[A-Za-z]+[0-9]+:' | tr -d ' 0-9:' | tr 'A-Z' 'a-z' | sort -u | tr '\n' ',' | sed 's/,$//')"
fi
detect_gpu
echo "gpu_kind=$GPU_KIND"; echo "gpu_integrated=$GPU_INT"; echo "gpu_name=$(gpu_name)"
[ "$GPU_KIND" = nvidia ] && { command -v nvidia-smi >/dev/null && echo "gpu_driver=ok" || echo "gpu_driver=missing"; }
echo "ram_total_mb=$(awk '/^MemTotal/{print int($2/1024)}' /proc/meminfo)"
echo "unit=$([ -f "$HOME/.config/systemd/user/omallama.service" ] && echo installed || echo missing)"
missing=
for t in curl systemctl; do command -v $t >/dev/null || missing+="!$t,"; done
for t in wl-copy wl-paste notify-send xdg-open journalctl lspci; do command -v $t >/dev/null || missing+="$t,"; done
python3 -c "import gi" 2>/dev/null || missing+="python-gi,"
echo "missing_tools=${missing%,}"

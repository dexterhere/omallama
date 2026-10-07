#!/bin/bash
# GPU detection against fake sysfs trees: ./tests/gpu.test.sh
. "$(dirname "$0")/../lib.sh"
root=$(mktemp -d); trap 'rm -rf "$root"' EXIT
card() { # name vendor slot [vram_bytes]
  local d=$root/$1/device; mkdir -p "$d"; echo "$2" > "$d/vendor"; echo 0x030000 > "$d/class"
  [ -n "$4" ] && echo "$4" > "$d/mem_info_vram_total"
  mkdir -p "$root/pci"; mkdir -p "$root/pci/$3"; rm -rf "$d"; ln -s "$root/pci/$3" "$d"
  echo "$2" > "$root/pci/$3/vendor"; echo 0x030000 > "$root/pci/$3/class"; [ -n "$4" ] && echo "$4" > "$root/pci/$3/mem_info_vram_total"
}
check() { # label expected_kind expected_int
  OMALLAMA_DRM=$root detect_gpu
  [ "$GPU_KIND/$GPU_INT" = "$2/$3" ] && echo "ok   $1 -> $GPU_KIND int=$GPU_INT" || { echo "FAIL $1: got $GPU_KIND/$GPU_INT want $2/$3"; fail=1; }
}
reset() { rm -rf "$root"/card* "$root"/pci; }
reset; check "no gpu" none 0
reset; card card0 0x8086 0000:00:02.0; check "intel iGPU only" intel 1
reset; card card0 0x8086 0000:03:00.0; check "intel Arc" intel 0
reset; card card0 0x1002 0000:06:00.0 536870912; check "amd APU (512 MiB carve-out)" amd 1
reset; card card0 0x1002 0000:03:00.0 8589934592; check "amd discrete" amd 0
reset; card card0 0x8086 0000:00:02.0; card card1 0x10de 0000:01:00.0; check "intel iGPU + nvidia (optimus)" nvidia 0
reset; card card0 0x8086 0000:00:02.0; card card1 0x1002 0000:03:00.0 8589934592; check "intel iGPU + amd discrete" amd 0
reset; card card0 0x1002 0000:06:00.0 536870912; card card1 0x8086 0000:00:02.0; check "amd APU beats intel iGPU" amd 1
exit ${fail:-0}

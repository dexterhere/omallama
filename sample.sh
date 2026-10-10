#!/bin/bash
# One sample of everything the panel graphs, as key=value lines.
. "$(dirname "$0")/lib.sh"
envf=$cfg/env
awk '/^MemTotal/{t=$2}/^MemAvailable/{a=$2}/^SwapTotal/{st=$2}/^SwapFree/{sf=$2}
  END{printf "mem_total=%d\nmem_avail=%d\nswap_used=%d\n",t,a,st-sf}' /proc/meminfo

detect_gpu
echo "gpu_kind=$GPU_KIND"; echo "gpu_integrated=$GPU_INT"
mib() { echo $(( ${1:-0} / 1048576 )); }
hwtemp() { local t; t=$(cat "$1"/hwmon/hwmon*/temp1_input 2>/dev/null | head -1); echo $(( ${t:-0} / 1000 )); }
case $GPU_KIND in
  nvidia)
    nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null |
      awk -F', ' '{printf "vram_used=%s\nvram_total=%s\ngpu_util=%s\ngpu_temp=%s\n",$1,$2,$3,$4}' ;;
  amd)
    echo "gpu_util=$(cat "$GPU_CARD/gpu_busy_percent" 2>/dev/null || echo -1)"
    echo "gpu_temp=$(hwtemp "$GPU_CARD")"
    if [ "$GPU_INT" = 0 ]; then
      echo "vram_used=$(mib "$(cat "$GPU_CARD/mem_info_vram_used" 2>/dev/null)")"
      echo "vram_total=$(mib "$(cat "$GPU_CARD/mem_info_vram_total" 2>/dev/null)")"
    fi ;;
  intel)
    # No unprivileged utilisation counter for Intel GPUs; the panel shows "n/a".
    echo "gpu_util=-1"; echo "gpu_temp=$(hwtemp "$GPU_CARD")" ;;
esac

port=$(grep '^LLM_PORT=' "$envf" 2>/dev/null | cut -d= -f2)
echo "state=$(systemctl --user is-active omallama 2>/dev/null)"
pid=$(systemctl --user show -p MainPID --value omallama 2>/dev/null)
if [ "${pid:-0}" != 0 ]; then
  awk '/^VmRSS/{printf "server_rss=%d\n",$2}' /proc/$pid/status 2>/dev/null
  curl -s -m 1 "localhost:${port:-8080}/health" | grep -q '"ok"' && echo "health=ok"
  curl -s -m 1 "localhost:${port:-8080}/metrics" | awk '/^llamacpp:predicted_tokens_seconds /{printf "tps=%.1f\n",$2} /^llamacpp:requests_processing /{printf "busy=%d\n",$2}'
fi
model=$(grep '^LLM_MODEL=' "$envf" 2>/dev/null | cut -d= -f2-)
[ "$(grep '^LLM_MODEL_FLAG=' "$envf" 2>/dev/null | cut -d= -f2-)" = -hf ] && model=hf:$model
echo "active_model=$model"
echo "ctx=$(grep '^LLM_CTX=' "$envf" 2>/dev/null | cut -d= -f2)"
[ "${pid:-0}" != 0 ] && echo "uptime=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')"
for k in PORT NGL KV EXTRA AUTOSTOP; do echo "cfg_$k=$(grep "^LLM_$k=" "$envf" 2>/dev/null | cut -d= -f2-)"; done
echo "enabled=$(systemctl --user is-enabled omallama 2>/dev/null)"
sed 's/^/added=/' "$cfg/models.list" 2>/dev/null

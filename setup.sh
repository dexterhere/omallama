#!/bin/bash
# usage: setup.sh            install or repair the omallama systemd user service
#        setup.sh remove     stop and delete the service (settings and models are kept)
. "$(dirname "$0")/lib.sh"
if [ "$1" = remove ]; then
  systemctl --user disable --now omallama 2>/dev/null
  rm -f "$HOME/.config/systemd/user/omallama.service"
  systemctl --user daemon-reload
  echo "ok: service removed (settings stay in ~/.config/omallama)"
  exit 0
fi
bin=$(find_bin)
[ -n "$bin" ] || { echo "err: llama-server not found"; exit 0; }
detect_gpu
mkdir -p "$cfg" "$HOME/models" "$HOME/.config/systemd/user"
touch "$cfg/env" "$cfg/models.list"
set_default() { grep -q "^$1=" "$cfg/env" || echo "$1=$2" >> "$cfg/env"; }
sed -i '/^LLM_BIN=/d' "$cfg/env"; echo "LLM_BIN=$bin" >> "$cfg/env"
first=$(find "$HOME/models" -maxdepth 2 -iname '*.gguf' 2>/dev/null | head -1)
set_default LLM_MODEL "$first"
set_default LLM_ALIAS "$(basename "${first:-model}" .gguf)"
set_default LLM_CTX 8192
set_default LLM_NGL "$([ "$GPU_KIND" = none ] && echo 0 || echo 99)"
set_default LLM_KV "-ctk q8_0 -ctv q8_0"
set_default LLM_PORT 8080
set_default LLM_EXTRA ""
set_default LLM_AUTOSTOP 0
mem=$(awk '/^MemTotal/{print int($2*0.75/1024)}' /proc/meminfo)
unit=$HOME/.config/systemd/user/omallama.service
cat > "$unit.new" <<UNIT
[Unit]
Description=Omallama: llama.cpp server

[Service]
EnvironmentFile=%h/.config/omallama/env
ExecStart=$bin -m \${LLM_MODEL} -ngl \${LLM_NGL} -c \${LLM_CTX} -fa on \$LLM_KV --port \${LLM_PORT} --alias \${LLM_ALIAS} --metrics \$LLM_EXTRA
Restart=no
# Keep the desktop out of swap if the model ever balloons
MemoryMax=${mem}M

[Install]
WantedBy=default.target
UNIT
# Keep a copy if the user edited the service by hand, rather than overwriting it silently.
[ -f "$unit" ] && ! cmp -s "$unit" "$unit.new" && cp "$unit" "$unit.bak"
mv "$unit.new" "$unit"
systemctl --user daemon-reload
echo "ok: service installed for $bin"

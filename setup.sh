#!/bin/bash
# Installs (or repairs) the omallama systemd user service around the llama-server found on this machine.
. "$(dirname "$0")/lib.sh"
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
cat > "$HOME/.config/systemd/user/omallama.service" <<UNIT
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
systemctl --user daemon-reload
echo "ok: service installed for $bin"

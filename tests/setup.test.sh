#!/bin/bash
# setup.sh remove: stops and deletes the service but keeps settings. Uses a stub systemctl.
here=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail=0
export PATH=/usr/bin:/bin
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
mkdir -p "$T/home/.config/systemd/user" "$T/home/.config/omallama" "$T/bin"
echo unit > "$T/home/.config/systemd/user/omallama.service"; echo "LLM_PORT=8080" > "$T/home/.config/omallama/env"
printf '#!/bin/sh\necho "$@" >> "%s/calls"\n' "$T" > "$T/bin/systemctl"; chmod +x "$T/bin/systemctl"
out=$(HOME=$T/home PATH=$T/bin:$PATH bash "$here/setup.sh" remove)
[[ $out == ok:* ]] && ok "remove reports success" || bad "remove output: $out"
[ ! -e "$T/home/.config/systemd/user/omallama.service" ] && ok "service file deleted" || bad "service file still there"
[ -f "$T/home/.config/omallama/env" ] && ok "settings kept" || bad "settings deleted"
grep -q -- "--user disable --now omallama" "$T/calls" && ok "service stopped and disabled" || bad "systemctl disable not called"

# install: an edited service file is backed up before being replaced, an identical one is not
printf '#!/bin/sh\n' > "$T/bin/llama-server"; chmod +x "$T/bin/llama-server"
echo "LLM_BIN=$T/bin/llama-server" > "$T/home/.config/omallama/env"
U=$T/home/.config/systemd/user/omallama.service
echo "hand edited" > "$U"
HOME=$T/home PATH=$T/bin:$PATH bash "$here/setup.sh" >/dev/null
[ "$(cat "$U.bak" 2>/dev/null)" = "hand edited" ] && ok "edited service backed up" || bad "edited service not backed up"
grep -q "ExecStart=$T/bin/llama-server" "$U" && ok "service written for the found binary" || bad "service not written"
rm -f "$U.bak"; HOME=$T/home PATH=$T/bin:$PATH bash "$here/setup.sh" >/dev/null
[ ! -e "$U.bak" ] && ok "unchanged service is not backed up" || bad "needless backup"
# Dispatcher discovery, service subcommand, and cached/local selection.
printf '#!/bin/sh\necho "$@" >> "%s/llama-calls"\n' "$T" > "$T/bin/llama"; chmod +x "$T/bin/llama"
HOME=$T/home PATH=$T/bin:$PATH bash "$here/setup.sh" >/dev/null
grep -q "ExecStart=$T/bin/llama serve \${LLM_MODEL_FLAG} \${LLM_MODEL}" "$U" && ok "dispatcher service uses serve and model flag" || bad "dispatcher command wrong"
grep -qx 'LLM_MODEL_FLAG=-m' "$T/home/.config/omallama/env" && ok "existing local selection defaults to -m" || bad "missing model flag"
HOME=$T/home PATH=$T/bin:$PATH bash "$here/setmodel.sh" model hf:owner/model-7B:Q4_K_M
grep -qx 'LLM_MODEL_FLAG=-hf' "$T/home/.config/omallama/env" && grep -qx 'LLM_MODEL=owner/model-7B:Q4_K_M' "$T/home/.config/omallama/env" && grep -qx 'LLM_ALIAS=model-7B:Q4_K_M' "$T/home/.config/omallama/env" && ok "cache selection uses -hf and matching alias" || bad "cache selection wrong"
HOME=$T/home PATH=$T/bin:$PATH bash "$here/sample.sh" 2>/dev/null | grep -qx 'active_model=hf:owner/model-7B:Q4_K_M' && ok "sample preserves cache selection identity" || bad "cache identity lost"
HOME=$T/home PATH=$T/bin:$PATH bash "$here/doctor.sh" >/dev/null 2>&1
grep -qx 'serve --version' "$T/llama-calls" && grep -qx 'serve --list-devices' "$T/llama-calls" && ok "doctor uses serve" || bad "doctor missing subcommand"
HOME=$T/home PATH=$T/bin:$PATH bash "$here/setmodel.sh" model "$T/home/models/local.gguf"
grep -qx 'LLM_MODEL_FLAG=-m' "$T/home/.config/omallama/env" && ok "switch back to local uses -m" || bad "local flag wrong"
exit $fail

#!/bin/bash
# setup.sh remove: stops and deletes the service but keeps settings. Uses a stub systemctl.
here=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fail=0
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
mkdir -p "$T/home/.config/systemd/user" "$T/home/.config/omallama" "$T/bin"
echo unit > "$T/home/.config/systemd/user/omallama.service"; echo "LLM_PORT=8080" > "$T/home/.config/omallama/env"
printf '#!/bin/sh\necho "$@" >> "%s/calls"\n' "$T" > "$T/bin/systemctl"; chmod +x "$T/bin/systemctl"
out=$(HOME=$T/home PATH=$T/bin:$PATH bash "$here/setup.sh" remove)
[[ $out == ok:* ]] && ok "remove reports success" || bad "remove output: $out"
[ ! -e "$T/home/.config/systemd/user/omallama.service" ] && ok "service file deleted" || bad "service file still there"
[ -f "$T/home/.config/omallama/env" ] && ok "settings kept" || bad "settings deleted"
grep -q -- "--user disable --now omallama" "$T/calls" && ok "service stopped and disabled" || bad "systemctl disable not called"
exit $fail

#!/bin/bash
# Regression tests for scan.sh and setmodel.sh against hostile paths: ./tests/scan.test.sh
here=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
mkdir -p "$T/home/.config/omallama" "$T/home/models" "$T/work/-delete"
cd "$T/work"; touch canary.txt; truncate -s 25M victim.gguf
export HOME=$T/home

# 1. relative list entries must never reach find as options
echo "-delete" > "$HOME/.config/omallama/models.list"
bash "$here/scan.sh" >/dev/null 2>&1
[ -f canary.txt ] && [ -f victim.gguf ] && ok "relative list entry '-delete' is ignored" || bad "relative list entry deleted files"

# 2. a directory name with a newline must not forge an extra record
d=$(printf 'a\n1|'); mkdir -p "$HOME/models/$d/etc"; truncate -s 25M "$HOME/models/$d/etc/passwd.gguf"
out=$(bash "$here/scan.sh")
[[ $out == *"1|/etc/passwd.gguf"* ]] && bad "forged record emitted" || ok "paths with newlines are skipped"

# 3. a normal model still shows up, with the right record shape
truncate -s 30M "$HOME/models/good-7b-q4_k_m.gguf"
bash "$here/scan.sh" | grep -qx "31457280|$HOME/models/good-7b-q4_k_m.gguf" && ok "normal model listed" || bad "normal model missing"

# 4. setmodel refuses control characters and bad keys
: > "$HOME/.config/omallama/env"
bash "$here/setmodel.sh" set LLM_EXTRA $'x\nLLM_MODEL=/evil' norestart | grep -q '^err' && ok "newline in value rejected" || bad "newline accepted"
bash "$here/setmodel.sh" set 'bad key' value norestart | grep -q '^err' && ok "bad key rejected" || bad "bad key accepted"
grep -q evil "$HOME/.config/omallama/env" && bad "env was polluted" || ok "env untouched"
exit $fail

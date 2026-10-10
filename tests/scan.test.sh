#!/bin/bash
# Regression tests for scan.sh and setmodel.sh against hostile paths: ./tests/scan.test.sh
here=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
mkdir -p "$T/home/.config/omallama" "$T/home/models" "$T/work/-delete"
cd "$T/work"; touch canary.txt; truncate -s 25M victim.gguf
export HOME=$T/home
export HF_HUB_CACHE=$HOME/.cache/huggingface/hub

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
# Cached model names come from the CLI, never the resolved hash filenames.
mkdir -p "$T/bin" "$HOME/.cache/llama.cpp" "$HOME/.cache/huggingface/hub"
printf '#!/bin/sh\n[ "$*" = "cli --cache-list" ] || exit 1\nprintf "number of models in cache: 2\\n   1. owner/model-7B:Q4_K_M\\n   2. owner/model-7B:MXFP4\\n   3. bad|record\\n"\n' > "$T/bin/llama"
chmod +x "$T/bin/llama"
truncate -s 30M "$HOME/.cache/huggingface/hub/hashblob"
ln -s "$HOME/.cache/huggingface/hub/hashblob" "$HOME/.cache/llama.cpp/model.gguf"
out=$(PATH=$T/bin:$PATH bash "$here/scan.sh")
grep -qx '0|hf:owner/model-7B:Q4_K_M' <<< "$out" && grep -qx '0|hf:owner/model-7B:MXFP4' <<< "$out" && ok "cache names listed via llama cli" || bad "cache names missing"
[[ $out != *hashblob* && $out != *'bad|record'* ]] && ok "hash blobs and malformed cache records excluded" || bad "bad cache record"
bash "$here/setmodel.sh" model 'hf:owner/model:Q4|bad' | grep -q '^err' && ok "malformed cached selection rejected" || bad "malformed cache selection accepted"
# Use refs/main only, follow symlinks for sizes, and add all quant-matched shards.
export HF_HUB_CACHE=$T/custom-cache
repo=$HF_HUB_CACHE/models--owner--model-7B
mkdir -p "$repo/refs" "$repo/blobs" "$repo/snapshots/abc123/nested" "$repo/snapshots/def456"
printf abc123 > "$repo/refs/main"
truncate -s 30M "$repo/blobs/q4"; truncate -s 40M "$repo/blobs/mx1"; truncate -s 60M "$repo/blobs/mx2"
ln -s ../../blobs/q4 "$repo/snapshots/abc123/model-Q4_K_M.gguf"
ln -s ../../../blobs/mx1 "$repo/snapshots/abc123/nested/model-mxfp4-00001-of-00002.gguf"
ln -s ../../../blobs/mx2 "$repo/snapshots/abc123/nested/model-MXFP4-00002-of-00002.gguf"
ln -s ../../blobs/mx1 "$repo/snapshots/abc123/mmproj-MXFP4.gguf"
ln -s ../../blobs/missing "$repo/snapshots/abc123/broken-MXFP4.gguf"
ln -s ../../blobs/mx1 "$repo/snapshots/def456/old-MXFP4.gguf"
truncate -s 99M "$repo/snapshots/abc123/model-IQ4_XS.gguf"
out=$(PATH=$T/bin:$PATH bash "$here/scan.sh")
grep -qx '31457280|hf:owner/model-7B:Q4_K_M' <<< "$out" && ok "Q4 size comes from snapshot symlink target" || bad "Q4 size wrong"
grep -qx '104857600|hf:owner/model-7B:MXFP4' <<< "$out" && ok "MXFP4 sums shards and skips old revisions, projectors and broken links" || bad "MXFP4 size wrong"
printf '../../outside' > "$repo/refs/main"
out=$(PATH=$T/bin:$PATH bash "$here/scan.sh")
grep -qx '0|hf:owner/model-7B:MXFP4' <<< "$out" && ok "invalid revision is kept as unknown size" || bad "invalid revision traversed"
exit $fail

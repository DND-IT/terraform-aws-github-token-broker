#!/usr/bin/env bash
# Imports a GitHub App private key into an EXTERNAL-origin KMS key, then destroys
# every local copy including the source PEM.
#
# Usage: import-key-material.sh <kms-key-id> <path-to-app-pem>
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <kms-key-id> <path-to-app-pem>" >&2
  exit 64
fi

key_id=$1
pem=$2

for tool in aws openssl xxd python3; do
  command -v "$tool" >/dev/null || { echo "missing required tool: $tool" >&2; exit 69; }
done
[[ -r $pem ]] || { echo "cannot read $pem" >&2; exit 66; }

# -id-aes256-wrap-pad needs OpenSSL 3; macOS ships LibreSSL as /usr/bin/openssl.
openssl version | grep -q '^OpenSSL 3' || { echo "OpenSSL 3.x required, found: $(openssl version)" >&2; exit 69; }

umask 077
workdir=$(mktemp -d)

destroy() {
  local f=$1
  [[ -e $f ]] || return 0
  if command -v shred >/dev/null; then
    shred -u "$f"
  elif command -v gshred >/dev/null; then
    gshred -u "$f"
  else
    # Best effort where shred is unavailable; on SSDs and copy-on-write
    # filesystems no overwrite is a guarantee, so run this on an encrypted disk.
    dd if=/dev/urandom of="$f" bs=1 count="$(wc -c <"$f")" conv=notrunc status=none
    rm -f "$f"
  fi
}

cleanup() {
  for f in "$workdir"/*; do destroy "$f"; done
  rmdir "$workdir"
}
trap cleanup EXIT

aws kms get-parameters-for-import \
  --key-id "$key_id" \
  --wrapping-algorithm RSA_AES_KEY_WRAP_SHA_256 \
  --wrapping-key-spec RSA_4096 \
  --output json >"$workdir/params.json"

python3 - "$workdir" <<'PY'
import base64, json, sys
d = sys.argv[1]
p = json.load(open(f"{d}/params.json"))
open(f"{d}/wrapping-key.der", "wb").write(base64.b64decode(p["PublicKey"]))
open(f"{d}/import-token.bin", "wb").write(base64.b64decode(p["ImportToken"]))
PY

openssl pkcs8 -topk8 -nocrypt -inform PEM -outform DER -in "$pem" -out "$workdir/key.der"

openssl rand -out "$workdir/aes.bin" 32

openssl enc -id-aes256-wrap-pad \
  -K "$(xxd -p <"$workdir/aes.bin" | tr -d '\n')" \
  -iv A65959A6 \
  -in "$workdir/key.der" \
  -out "$workdir/key-wrapped.bin"

openssl pkeyutl -encrypt \
  -in "$workdir/aes.bin" \
  -out "$workdir/aes-wrapped.bin" \
  -inkey "$workdir/wrapping-key.der" -keyform DER -pubin \
  -pkeyopt rsa_padding_mode:oaep \
  -pkeyopt rsa_oaep_md:sha256 \
  -pkeyopt rsa_mgf1_md:sha256

cat "$workdir/aes-wrapped.bin" "$workdir/key-wrapped.bin" >"$workdir/encrypted-key-material.bin"

aws kms import-key-material \
  --key-id "$key_id" \
  --encrypted-key-material "fileb://$workdir/encrypted-key-material.bin" \
  --import-token "fileb://$workdir/import-token.bin" \
  --expiration-model KEY_MATERIAL_DOES_NOT_EXPIRE

destroy "$pem"

echo "Imported into $key_id; $pem destroyed."
aws kms describe-key --key-id "$key_id" --query 'KeyMetadata.[KeyState,Origin,KeySpec]' --output text

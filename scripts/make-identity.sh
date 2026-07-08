#!/bin/zsh
# Creates a local self-signed code-signing identity ("Sleight Local Signing")
# and imports it into the login keychain. Signing Sleight with a stable
# identity means macOS permission grants (Accessibility, Input Monitoring)
# SURVIVE app updates — with plain ad-hoc signing they break on every build.
# Run once per machine.
set -euo pipefail

NAME="Sleight Local Signing"

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "Identity '$NAME' already exists — nothing to do."
  exit 0
fi

DIR=$(mktemp -d)
trap "rm -rf $DIR" EXIT
cd "$DIR"

cat > cert.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Sleight Local Signing
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
  -days 3650 -nodes -config cert.cnf 2>/dev/null
openssl pkcs12 -export -out identity.p12 -inkey key.pem -in cert.pem \
  -passout pass:sleight -name "$NAME" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
security import identity.p12 -k ~/Library/Keychains/login.keychain-db \
  -P sleight -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign cert.pem 2>/dev/null || true

echo "Created and imported '$NAME'. Builds will now use it automatically."

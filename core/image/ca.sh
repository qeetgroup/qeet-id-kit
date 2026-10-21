#!/bin/sh
# Generates this computer's local certificate authority for the edge's https
# environments into the given directory:
#   root.crt  the CA certificate; Start asks once to trust it on this computer
#   root.key  its private key, owner-only; only the edge reads it
# The edge (Caddy) issues short-lived certificates for each environment's
# addresses from it. Name-constrained to the kit zones, so even its own key
# cannot vouch for any other site: not production (id.qeet.in), not any
# address outside <env>.id.qeet.in. Random per computer, never shared.
# Never replaces an existing CA: browsers on this computer already trust it.
set -eu

out=${1:-/out}
if [ -s "$out/root.crt" ] && [ -s "$out/root.key" ]; then
  echo "ca: this computer's certificate authority already exists"
  exit 0
fi
if [ -e "$out/root.crt" ] || [ -e "$out/root.key" ]; then
  echo "ca: $out holds an incomplete certificate authority; refusing to replace it" >&2
  exit 3
fi

umask 077
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/ca.cnf" << 'EOF'
[req]
prompt = no
distinguished_name = dn
x509_extensions = ca
[dn]
O = Qeet ID Kit
CN = Qeet ID Kit local CA (this computer only)
[ca]
basicConstraints = critical, CA:TRUE, pathlen:1
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
nameConstraints = critical, permitted;DNS:test.id.qeet.in, permitted;DNS:staging.id.qeet.in, permitted;DNS:dev.id.qeet.in
EOF

# pathlen:1 leaves room for the intermediate the edge creates under it.
openssl req -x509 -config "$work/ca.cnf" -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -days 1825 -keyout "$work/root.key" -out "$work/root.crt" 2> /dev/null

cp "$work/root.key" "$out/root.key.tmp"
chmod 600 "$out/root.key.tmp"
cp "$work/root.crt" "$out/root.crt.tmp"
chmod 644 "$out/root.crt.tmp"
# Certificate last: its presence is what marks the pair complete.
mv "$out/root.key.tmp" "$out/root.key"
mv "$out/root.crt.tmp" "$out/root.crt"
echo "ca: created this computer's certificate authority"

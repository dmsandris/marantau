#!/bin/sh
# Buat / lengkapi .env server Marantau dengan rahasia acak.
# - .env belum ada  -> dibuat dari env.template.
# - .env sudah ada  -> TIDAK ada nilai lama yang diubah; hanya kunci baru yang belum ada ditambahkan.
# Pakai: sh gen-env.sh [email-acme]
set -eu
cd "$(dirname "$0")"
command -v openssl >/dev/null || { echo "openssl tidak ada"; exit 1; }
umask 077

b64url() { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }
jwt() {
  h=$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | b64url)
  p=$(printf '%s' "$1" | b64url)
  s=$(printf '%s' "$h.$p" | openssl dgst -binary -sha256 -hmac "$JWT_SECRET" | b64url)
  printf '%s' "$h.$p.$s"
}
base32() { openssl rand 20 | python3 -c 'import base64,sys;print(base64.b32encode(sys.stdin.buffer.read()).decode())'; }

if [ ! -f .env ]; then
  acme_email="${1:-ops@marantau.web.id}"
  JWT_SECRET=$(openssl rand -hex 32)
  iat=$(date +%s)
  exp=$((iat + 10 * 365 * 24 * 3600))
  ANON_KEY=$(jwt "{\"role\":\"anon\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}")
  SERVICE_ROLE_KEY=$(jwt "{\"role\":\"service_role\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}")
  sed \
    -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 24)|" \
    -e "s|^JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" \
    -e "s|^ANON_KEY=.*|ANON_KEY=$ANON_KEY|" \
    -e "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY|" \
    -e "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$(openssl rand -hex 48)|" \
    -e "s|^REALTIME_DB_ENC_KEY=.*|REALTIME_DB_ENC_KEY=$(openssl rand -hex 8)|" \
    -e "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$(openssl rand -hex 16)|" \
    -e "s|^MT_OPS_RO_PASSWORD=.*|MT_OPS_RO_PASSWORD=$(openssl rand -hex 24)|" \
    -e "s|__ACME_EMAIL__|$acme_email|" \
    env.template > .env
  echo ".env dibuat."
fi

# Kunci yang ditambahkan belakangan (Panel Ops, dst). Hanya ditulis bila belum ada.
added=""
ensure() {
  grep -q "^$1=" .env && return 0
  printf '%s=%s\n' "$1" "$2" >> .env
  added="$added $1"
}
ensure OPS_PASSWORD "$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)"
ensure OPS_TOTP_SECRET "$(base32)"
ensure OPS_SESSION_SECRET "$(openssl rand -hex 32)"
ensure OPS_MCP_TOKEN "$(openssl rand -hex 32)"
ensure OPS_TELEGRAM_TOKEN ""
ensure OPS_TELEGRAM_CHAT_ID ""

chmod 600 .env
[ -n "$added" ] && echo "Ditambahkan ke .env:$added"
echo "OK. Simpan salinan .env di password manager."

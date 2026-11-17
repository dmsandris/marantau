#!/bin/sh
# Buat .env server Marantau dari env.template dengan rahasia acak.
# TIDAK PERNAH menimpa .env yang sudah ada (rahasia lama = token & sandi DB tetap berlaku).
# Pakai: sh gen-env.sh [email-acme]
set -eu
cd "$(dirname "$0")"

if [ -f .env ]; then
  echo ".env sudah ada - tidak diubah."
  exit 0
fi
command -v openssl >/dev/null || { echo "openssl tidak ada"; exit 1; }

acme_email="${1:-ops@marantau.web.id}"

b64url() { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }
jwt() {
  h=$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | b64url)
  p=$(printf '%s' "$1" | b64url)
  s=$(printf '%s' "$h.$p" | openssl dgst -binary -sha256 -hmac "$JWT_SECRET" | b64url)
  printf '%s' "$h.$p.$s"
}

JWT_SECRET=$(openssl rand -hex 32)
iat=$(date +%s)
exp=$((iat + 10 * 365 * 24 * 3600))
ANON_KEY=$(jwt "{\"role\":\"anon\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}")
SERVICE_ROLE_KEY=$(jwt "{\"role\":\"service_role\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}")

umask 077
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
chmod 600 .env
echo ".env dibuat (chmod 600). Simpan salinannya di password manager."

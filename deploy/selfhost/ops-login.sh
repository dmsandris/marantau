#!/bin/sh
# Tampilkan sandi Panel Ops + QR 2FA. JALANKAN MANUAL DI VM (jangan dari GitHub Actions - log repo publik).
#   sh /opt/marantau/selfhost/ops-login.sh
set -eu
cd "$(dirname "$0")"
pw=$(sed -n 's/^OPS_PASSWORD=//p' .env)
secret=$(sed -n 's/^OPS_TOTP_SECRET=//p' .env)
domain=$(sed -n 's/^OPS_DOMAIN=//p' .env)
uri="otpauth://totp/Marantau%20Ops:pemilik?secret=$secret&issuer=Marantau%20Ops&digits=6&period=30"
echo
echo "Panel Ops : https://$domain"
echo "Sandi     : $pw"
echo
echo "Pindai QR ini dengan Google Authenticator / Authy / 1Password:"
if command -v qrencode >/dev/null; then qrencode -t ansiutf8 "$uri"; else echo "(qrencode belum terpasang: sudo apt-get install -y qrencode)"; fi
echo "Kalau QR tidak bisa dipindai, masukkan kode manual: $secret"
echo
mcp=$(sed -n 's/^OPS_MCP_TOKEN=//p' .env)
if [ -n "$mcp" ]; then
  echo "Connector Claude (claude.ai > Settings > Connectors > Add custom connector):"
  echo "  Nama : marantau-ops"
  echo "  URL  : https://$domain/mcp/$mcp"
  echo "  (URL ini rahasia - siapa pun yang punya bisa membaca server.)"
  echo
fi
echo "Setelah tersimpan, bersihkan layar: clear"

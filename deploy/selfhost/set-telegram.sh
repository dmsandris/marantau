#!/bin/sh
# Pasang peringatan Telegram untuk Panel Ops & backup. JALANKAN MANUAL DI VM:
#   sh /opt/marantau/selfhost/set-telegram.sh
# Sebelumnya: buat bot di @BotFather, lalu kirim pesan apa saja (mis. "halo") ke bot itu.
set -eu
cd "$(dirname "$0")"
printf 'Tempel token bot dari @BotFather (tidak tampil di layar): '
stty -echo 2>/dev/null || true; read -r TOKEN; stty echo 2>/dev/null || true; echo
case "$TOKEN" in *:*) ;; *) echo "Format token salah (harus seperti 123456:ABC...)."; exit 1;; esac

me=$(curl -s -m 10 "https://api.telegram.org/bot$TOKEN/getMe")
echo "$me" | jq -e .ok >/dev/null || { echo "Token ditolak Telegram: $(echo "$me" | jq -r .description)"; exit 1; }
echo "Bot: @$(echo "$me" | jq -r .result.username)"

upd=$(curl -s -m 10 "https://api.telegram.org/bot$TOKEN/getUpdates")
CHAT=$(echo "$upd" | jq -r '[.result[] | (.message // .channel_post // .my_chat_member) | .chat.id] | last // empty')
if [ -z "$CHAT" ]; then
  echo "Belum ada pesan ke bot. Buka bot di Telegram, kirim 'halo', lalu jalankan skrip ini lagi."; exit 1
fi
echo "Chat ID: $CHAT ($(echo "$upd" | jq -r '[.result[] | (.message // .channel_post // .my_chat_member) | .chat | (.title // .first_name // "-")] | last'))"

umask 077
tmp=$(mktemp .env.XXXX)
grep -v -e '^OPS_TELEGRAM_TOKEN=' -e '^OPS_TELEGRAM_CHAT_ID=' .env > "$tmp"
printf 'OPS_TELEGRAM_TOKEN=%s\nOPS_TELEGRAM_CHAT_ID=%s\n' "$TOKEN" "$CHAT" >> "$tmp"
chmod 600 "$tmp"; mv "$tmp" .env

curl -s -m 10 -o /dev/null "https://api.telegram.org/bot$TOKEN/sendMessage" \
  --data-urlencode "chat_id=$CHAT" --data-urlencode "text=✅ Telegram Marantau Ops terpasang di $(hostname)."
echo "Menyalakan ulang Panel Ops dengan setelan baru..."
sudo docker compose up -d ops >/dev/null 2>&1 || docker compose up -d ops
echo "Selesai. Cek pesan di Telegram, lalu coba tombol 'Kirim pesan tes' di Panel Ops > Backup."

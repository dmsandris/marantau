# Supabase self-host ramping - Marantau

Bagian **Fase 1.3** dari `PLAN-Pindah-Server-Biznet.md`. Supabase cloud tetap melayani pemain sampai Fase 3.

| Layanan | Image (dikunci) | Peran |
|---|---|---|
| `db` | `supabase/postgres:17.6.1.136` | Postgres, hanya di jaringan Docker + `127.0.0.1:5432` |
| `auth` | `supabase/gotrue:v2.197.0` | Login, autoconfirm `@marantau.game`, tanpa SMTP |
| `rest` | `postgrest/postgrest:v14.18` | `api_*`, pool 8, `db_pre_request` dari role |
| `realtime` | `supabase/realtime:v2.148.3` | Kanal privat, `realtime.send` |
| `api-gw` | `envoyproxy/envoy:v1.39.6` | Gateway resmi Supabase (cek apikey) |
| `caddy` | `caddy:2.10` | HTTPS `api.` & `ops.marantau.web.id` (profil `https`) |
| `ops` | dibangun dari `ops/` (node:22-alpine) | Panel Ops `ops.marantau.web.id` (1.5) |

Studio, Storage, imgproxy, Meta, Edge Functions, Supavisor, Analytics **tidak dipasang**.

## Berkas
- `docker-compose.yml`: susunan layanan.
- `env.template`: kerangka `.env`. **`.env` asli hanya di VM** (`/opt/marantau/selfhost/.env`, chmod 600).
- `gen-env.sh`: membuat `.env` dengan rahasia acak, sekali saja, tidak pernah menimpa.
- `post-deploy.sh`: setelan role (timeout 8 dtk/3 dtk, role hanya-baca `mt_ops_ro`) + uji asap.
- `Caddyfile`: hanya meneruskan `/auth/v1`, `/rest/v1`, `/realtime/v1`.
- `volumes/api/envoy/*`, `volumes/db/{realtime,webhooks,roles,jwt}.sql`: salinan resmi dari `supabase/supabase/docker`.

## Cara pakai
1. Actions → **VPS setup** (sekali; aman diulang).
2. Actions → **VPS deploy** (`https` = on bila DNS sudah mengarah ke VM).
3. Simpan salinan `.env` VM di password manager:
   `scp -i ~/.ssh/marantau-vps marantau@139.190.107.108:/opt/marantau/selfhost/.env marantau-vps-env.txt`

## Kunci API
Mode **legacy HS256** (anon/service JWT dari `JWT_SECRET`). `config.js` versi uji memakai `ANON_KEY`
yang dicetak `post-deploy.sh`. Token login cloud lama akan ditolak (401) lalu klien memakai refresh
token yang ikut pindah (rencana 1.4).

## Panel Ops (`ops/`)
- Login sandi + 2FA TOTP, sesi 12 jam, 5 percobaan gagal / 15 menit per IP, kode TOTP tidak bisa dipakai ulang.
- **Server**: CPU, IOwait, RAM, swap, load, disk + grafik 6 jam / 24 jam / 7 hari (sampel tiap menit dari `/proc` host), jumlah 5xx dari log Caddy.
- **Layanan**: status & RAM tiap container, 200 baris log, tombol Restart (hanya daftar container tetap; Postgres diberi peringatan).
- **Database**: pemain online, koneksi, kunci menunggu, transaksi > 10 dtk, endpoint terlambat (`pg_stat_statements`), tabel terbesar. Memakai role `mt_ops_ro` (hanya-baca, tanpa schema `auth`).
- **Backup**: membaca `/opt/marantau/backup` (+ `status.json`) - terisi setelah 1.7.
- **Telegram** (opsional): isi `OPS_TELEGRAM_TOKEN` & `OPS_TELEGRAM_CHAT_ID` di `.env`, lalu VPS deploy. Peringatan: RAM > 85%, swap > 200 MB, disk > 80%, IOwait > 30%, layanan mati, backup > 30 jam, 5xx >= 20/jam.
- Sandi & QR 2FA: jalankan **manual di VM** `sh /opt/marantau/selfhost/ops-login.sh` (jangan lewat Actions - log repo publik).
- Uji lokal: `cd ops && npm ci && OPS_DEV=1 OPS_PROC=/proc OPS_DATA=/tmp/ops OPS_PASSWORD=... OPS_TOTP_SECRET=... node server.js`.

## Menu Debug (Panel Ops)
Tombol **Buat laporan** → teks berisi host, sertifikat HTTPS, layanan (restart/OOM), database, 5xx, backup, peringatan aktif, dan log bermasalah 24 jam. Rahasia disamarkan otomatis. **Salin** / **Unduh .txt** (`marantau-debug-YYYY-MM-DD-HHMM.txt`) lalu kirim ke Claude. Cadangan bila connector bermasalah.

## Connector Claude `marantau-ops` (1.6)
- Endpoint MCP di Panel Ops: `https://ops.marantau.web.id/mcp/<OPS_MCP_TOKEN>` (URL lengkap: `sh ops-login.sh`). Token salah → 404.
- Alat hanya-baca: `server_status`, `db_stats`, `db_query` (satu pernyataan lewat prepared statement + cursor, transaksi read only, 5 dtk, maks 200 baris, role `mt_ops_ro` tanpa schema `auth`), `logs_tail`, `backup_list`, `debug_report`. Tidak ada restart/ubah data. Batas 60 permintaan/menit. Semua keluaran disamarkan.

## Backup VM (1.7) - `backup/`
- `backup-vps.sh backup`: pg_dump (schema game, public, auth) + kebijakan Realtime + `count(*)` asli → tar → `age` (kunci publik Fase 0) → lokal `/opt/marantau/backup` 7 hari + Google Drive `marantau-backup/vps/` 30 hari. Status di `/opt/marantau/backup/status.json`.
- `backup-vps.sh restore-test`: backup + restore ke container `postgres:17` sementara (`tools/backup/restore-test.sh`).
- systemd: `marantau-backup.timer` (03:47 WIB), `marantau-restore-test.timer` (Minggu 04:20), `*.path` untuk tombol Panel Ops (berkas permintaan di `/opt/marantau/backup/req/`).
- Rahasia di VM: `~/.config/marantau/age-recipient.txt`, `~/.config/marantau/rclone.conf` (dipasang VPS deploy dari secret `BACKUP_AGE_RECIPIENT` & `RCLONE_CONF`).
- Gagal → Telegram (bila diatur) + Panel Ops merah.

## Telegram
`sh /opt/marantau/selfhost/set-telegram.sh` di VM (minta token bot, cari chat ID otomatis, tulis `.env`, nyalakan ulang Panel Ops).

Bot hanya menjawab chat pemilik (`OPS_TELEGRAM_CHAT_ID`), lewat long polling dari Panel Ops:
`/status`, `/db`, `/backup`, `/harian`, `/error [jam]`, `/log <db|rest|auth|realtime|envoy|caddy|ops> [baris]`,
`/debug` (laporan .txt), `/backup_sekarang`, `/tes_restore`, `/bantuan`. Laporan harian otomatis 07:00 WIB
(puncak server 24 jam, layanan & restart, pemain online + puncak, endpoint terlambat, 5xx, sertifikat, backup).
Tidak ada perintah restart/ubah data - restart hanya lewat Panel Ops (2FA).

## Belum di sini
Uji Realtime di Panel Ops & sinkron data (Fase 2).

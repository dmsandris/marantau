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

## Belum di sini
Uji Realtime di Panel Ops (Fase 2), connector `marantau-ops` (1.6), backup VM (1.7, menunggu Fase 0), sinkron data (Fase 2).

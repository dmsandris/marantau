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

## Belum di sini
Panel Ops (1.5), connector `marantau-ops` (1.6), backup VM (1.7, menunggu Fase 0), sinkron data (Fase 2).

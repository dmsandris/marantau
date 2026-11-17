#!/usr/bin/env bash
# Backup database Marantau (Supabase) -> satu arsip tar di $WORK.
# Isi arsip: db.dump (pg_dump custom: schema game, public, auth),
#            realtime-messages.sql (tabel + 3 kebijakan Realtime), counts.tsv, manifest.txt
# Butuh: DB (connection string), WORK (folder kerja), TANGGAL (YYYY-MM-DD, WIB).
# Tidak mencetak data apa pun ke log (repo publik) - hanya ukuran & jumlah.
set -euo pipefail
: "${DB:?DB kosong}" "${WORK:?}" "${TANGGAL:?}"
umask 077
mkdir -p "$WORK/isi"
cd "$WORK/isi"

# Perkiraan jumlah baris per tabel dari statistik Postgres (tanpa count(*): server Nano
# bisa butuh puluhan detik per tabel besar). Dipakai tes restore untuk mendeteksi data hilang.
psql "$DB" -X -At -F $'\t' -v ON_ERROR_STOP=1 > counts.tsv <<'SQL'
select n.nspname || '.' || c.relname, greatest(coalesce(s.n_live_tup, c.reltuples::bigint), 0)
from pg_class c join pg_namespace n on n.oid = c.relnamespace
left join pg_stat_user_tables s on s.relid = c.oid
where c.relkind in ('r', 'p') and not c.relispartition
  and (n.nspname in ('game', 'public') or (n.nspname = 'auth' and c.relname in ('users', 'identities', 'refresh_tokens', 'sessions')))
order by 1
SQL

ok=0
for coba in 1 2 3; do
  if pg_dump "$DB" -Fc -Z 6 --lock-wait-timeout=60s -n game -n public -n auth -f db.dump; then ok=1; break; fi
  echo "::warning::pg_dump percobaan $coba gagal, ulangi 60 dtk lagi..."; sleep 60
done
[ "$ok" = 1 ] || { echo "::error::pg_dump gagal 3x"; exit 1; }
pg_dump "$DB" -s -t realtime.messages --lock-wait-timeout=60s -f realtime-messages.sql

pol=$(grep -c '^CREATE POLICY' realtime-messages.sql || true)
[ "$pol" -ge 3 ] || { echo "::error::Kebijakan Realtime hanya $pol (harusnya >= 3)"; exit 1; }

{
  echo "tanggal_wib=$TANGGAL"
  echo "dibuat_utc=$(date -u +%FT%TZ)"
  echo "commit=${GITHUB_SHA:-lokal}"
  echo "pg_dump=$(pg_dump --version)"
  echo "server=$(psql "$DB" -X -At -c 'show server_version')"
  echo "tabel=$(wc -l < counts.tsv)"
  echo "baris_perkiraan=$(awk -F'\t' '{s+=$2} END {print s+0}' counts.tsv)"
  echo "kebijakan_realtime=$pol"
  sha256sum db.dump realtime-messages.sql counts.tsv
} > manifest.txt

tar -cf "$WORK/marantau-db-$TANGGAL.tar" db.dump realtime-messages.sql counts.tsv manifest.txt
echo "::notice::Dump OK: $(du -h db.dump | cut -f1) | $(grep -E '^(tabel|baris_perkiraan)=' manifest.txt | tr '\n' ' ')| kebijakan Realtime $pol"

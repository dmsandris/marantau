#!/usr/bin/env bash
# Tes restore: pulihkan db.dump ke Postgres kosong, lalu bandingkan jumlah baris dengan counts.tsv.
# Butuh: TARGET (connection string Postgres kosong), ISI (folder berisi db.dump & counts.tsv).
# Gagal bila: pg_restore error (selain yang wajar di Postgres polos), tabel hilang,
# atau tabel yang berisi di sumber jadi jauh lebih kecil setelah restore.
set -euo pipefail
: "${TARGET:?}" "${ISI:?}"

# Postgres polos belum punya role & schema bawaan Supabase.
psql "$TARGET" -X -q -v ON_ERROR_STOP=1 <<'SQL'
do $$ declare r text; begin
  foreach r in array array['anon','authenticated','service_role','authenticator','supabase_admin',
    'supabase_auth_admin','supabase_storage_admin','supabase_realtime_admin','dashboard_user','pgbouncer'] loop
    if not exists (select 1 from pg_roles where rolname = r) then execute format('create role %I nologin', r); end if;
  end loop;
end $$;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
SQL

set +e
pg_restore -d "$TARGET" --no-owner --no-privileges -j 2 "$ISI/db.dump" 2> "$ISI/restore-err.txt"
set -e
# Error wajar di Postgres polos: schema public sudah ada.
grep -E '^pg_restore: error:' "$ISI/restore-err.txt" | grep -vE 'schema "public" already exists' > "$ISI/restore-err-sisa.txt" || true
nerr=$(wc -l < "$ISI/restore-err-sisa.txt")

hilang=0; kecil=0; src=0; dst=0
while IFS=$'\t' read -r t n; do
  src=$((src + n))
  if ! m=$(psql "$TARGET" -X -At -c "select count(*) from $t" 2>/dev/null); then
    echo "::error::Tabel hilang setelah restore: $t"; hilang=$((hilang + 1)); continue
  fi
  dst=$((dst + m))
  if [ "$n" -gt 20 ] && [ "$m" -lt $((n * 9 / 10)) ]; then
    echo "::error::$t: $m baris (sumber $n)"; kecil=$((kecil + 1))
  fi
done < "$ISI/counts.tsv"

echo "::notice::Tes restore: $(wc -l < "$ISI/counts.tsv") tabel, baris sumber $src / hasil $dst, error lain $nerr, tabel hilang $hilang, tabel menyusut $kecil"
if [ "$nerr" -gt 0 ]; then
  # Hanya 5 baris pertama; pesan pg_restore berisi nama objek, bukan isi data.
  head -5 "$ISI/restore-err-sisa.txt" | cut -c1-300 | while IFS= read -r l; do echo "::error::$l"; done
fi
[ "$nerr" -eq 0 ] && [ "$hilang" -eq 0 ] && [ "$kecil" -eq 0 ]

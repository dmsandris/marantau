// Query tab Iluminaty (Pesan Pribadi antar kapten, game.mp_pm). Hanya SELECT, role baca-saja.
// Pesan disimpan game 7 hari (PmSimpanHari); semua yang masih ada di tabel ditampilkan.
'use strict';

const WIB = c => `to_char(to_timestamp(${c} / 1000.0) at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI:SS')`;
const NAMA = a => `coalesce(nullif(${a}.character_name, ''), ${a}.username)`;

const Q = {
  ringkas: `
select
  count(*) filter (where m.ts > (extract(epoch from now()) * 1000 - 86400000))::int as pm_24j,
  count(*)::int as pm_semua,
  count(distinct m.from_id)::int as pengirim,
  count(distinct m.pair)::int as percakapan,
  count(*) filter (where m.read_at is null)::int as belum_dibaca,
  ${WIB('min(m.ts)')} as tertua
from game.mp_pm m`,

  // satu baris per percakapan (pasangan kapten). a = uuid kecil, b = uuid besar
  percakapan: `
with x as (select m.pair, split_part(m.pair, '|', 1)::uuid as a, split_part(m.pair, '|', 2)::uuid as b,
  count(*)::int as jumlah,
  count(*) filter (where m.from_id::text = split_part(m.pair, '|', 1))::int as dari_a,
  count(*) filter (where m.from_id::text = split_part(m.pair, '|', 2))::int as dari_b,
  count(*) filter (where m.read_at is null)::int as belum_dibaca,
  max(m.ts) as akhir, min(m.ts) as awal
  from game.mp_pm m group by m.pair)
select x.pair, ${NAMA('pa')} as kapten_a, pa.username as user_a, ${NAMA('pb')} as kapten_b, pb.username as user_b,
  x.jumlah, x.dari_a, x.dari_b, x.belum_dibaca, ${WIB('x.awal')} as mulai, ${WIB('x.akhir')} as terakhir, x.akhir::float8 as akhir_ms
from x join game.players pa on pa.player_id = x.a join game.players pb on pb.player_id = x.b
order by x.akhir desc limit 500`,

  pengirim: `
select ${NAMA('p')} as kapten, p.username, count(*)::int as jumlah, count(distinct m.to_id)::int as lawan,
  count(*) filter (where m.ts > (extract(epoch from now()) * 1000 - 86400000))::int as jumlah_24j, ${WIB('max(m.ts)')} as terakhir
from game.mp_pm m join game.players p on p.player_id = m.from_id
group by p.player_id, p.character_name, p.username order by jumlah desc limit 200`,

  // $1 = pair
  utas: `
select m.id::float8 as id, ${WIB('m.ts')} as waktu, ${NAMA('pf')} as dari, pf.username as user_dari, ${NAMA('pt')} as ke,
  m.tx as isi, (m.read_at is not null) as dibaca, ${WIB('m.read_at')} as dibaca_pada
from game.mp_pm m join game.players pf on pf.player_id = m.from_id join game.players pt on pt.player_id = m.to_id
where m.pair = $1 order by m.id asc limit 2000`,

  // $1 = pola ilike (sudah di-escape), cari di isi pesan atau nama/username pengirim/penerima
  cari: `
select m.id::float8 as id, m.pair, ${WIB('m.ts')} as waktu, ${NAMA('pf')} as dari, ${NAMA('pt')} as ke, m.tx as isi, (m.read_at is not null) as dibaca
from game.mp_pm m join game.players pf on pf.player_id = m.from_id join game.players pt on pt.player_id = m.to_id
where m.tx ilike $1 or pf.character_name ilike $1 or pt.character_name ilike $1 or pf.username ilike $1 or pt.username ilike $1
order by m.id desc limit 300`,
};

const PAIR_RE = /^[0-9a-f-]{36}\|[0-9a-f-]{36}$/;
const likePat = s => '%' + String(s || '').slice(0, 80).replace(/[\\%_]/g, c => '\\' + c) + '%';

module.exports = { Q, PAIR_RE, likePat };

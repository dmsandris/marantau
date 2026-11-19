// Query tab Audit untuk Panel Ops. Hanya SELECT, dijalankan lewat role baca-saja.
// $1 di query berentang = jumlah jam ke belakang (null = semua catatan).
'use strict';

const SINCE = `($1::int is null or l.ts > now() - ($1::int * interval '1 hour'))`;
const WIB = c => `to_char(${c} at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI:SS')`;
const NAMA = `coalesce(nullif(p.character_name, ''), p.username)`;

const Q = {
  // ---------- Gudang (posisi sekarang) ----------
  gudang: `
with hold as (
  select w.player_id, w.city_id as lokasi, w.commodity_id, w.qty, w.cost, false as palka from game.warehouse w where w.qty > 0
  union all
  select i.player_id, null, i.item_id, i.qty, i.cost, true from game.inventory i join game.commodities c on c.id = i.item_id where i.qty > 0),
tot as (select commodity_id, sum(qty)::float8 as semua from hold group by 1)
select ${NAMA} as kapten, h.palka, coalesce(ci.name, h.lokasi, 'Palka') as pulau, ci.hidden as tersembunyi,
  c.name as barang, c.tier, h.qty::float8 as jumlah, (h.qty * c.base)::float8 as nilai_dasar, h.cost::float8 as modal,
  round((100 * h.qty / nullif(t.semua, 0))::numeric, 1)::float8 as pangsa_pct
from hold h join game.players p on p.player_id = h.player_id
join game.commodities c on c.id = h.commodity_id
left join game.cities ci on ci.city_id = h.lokasi
join tot t on t.commodity_id = h.commodity_id
where p.archetype <> ''
order by nilai_dasar desc`,

  // ---------- Arus gudang dari catatan (masuk = titip, keluar = ambil) ----------
  arusGudang: `
with x as (select l.player_id, l.message as m from game.player_log l
  where ${SINCE} and (l.message like 'Stored %' or l.message like 'Retrieved %')),
y as (select player_id, m like 'Stored %' as masuk,
  (regexp_match(m, '^(?:Stored|Retrieved) ([0-9]+) (.+?) (?:at|from) the warehouse'))[1]::float8 as q,
  (regexp_match(m, '^(?:Stored|Retrieved) ([0-9]+) (.+?) (?:at|from) the warehouse'))[2] as barang,
  coalesce(nullif(replace((regexp_match(m, 'fee: ([0-9][0-9,.]*) gold'))[1], ',', ''), '')::float8, 0) as biaya from x)
select ${NAMA} as kapten,
  coalesce(sum(y.q) filter (where y.masuk), 0)::float8 as masuk, coalesce(sum(y.q) filter (where not y.masuk), 0)::float8 as keluar,
  (coalesce(sum(y.q) filter (where y.masuk), 0) - coalesce(sum(y.q) filter (where not y.masuk), 0))::float8 as bersih,
  coalesce(sum(y.q * c.base) filter (where y.masuk), 0)::float8 as nilai_masuk,
  coalesce(sum(y.q * c.base) filter (where not y.masuk), 0)::float8 as nilai_keluar,
  count(*)::int as kejadian, sum(y.biaya)::float8 as biaya
from y join game.players p on p.player_id = y.player_id left join game.commodities c on c.name = y.barang
group by 1 order by nilai_masuk desc`,

  // ---------- Transfer gold antar kapten (api_mpGift) ----------
  transfer: `
with t as (select l.id, l.ts, l.player_id, regexp_match(l.message, '^Mengirim ([0-9]+) gold ke (.+)\\.$') as r
  from game.player_log l where ${SINCE} and l.message like 'Mengirim % gold ke %')
select t.id::float8 as id, ${WIB('t.ts')} as waktu, ${NAMA} as pengirim,
  coalesce(nullif(q.character_name, ''), t.r[2]) as penerima, (q.player_id is not null) as penerima_dikenal,
  t.r[1]::float8 as jumlah
from t join game.players p on p.player_id = t.player_id
left join game.players q on q.character_name = t.r[2]
where t.r is not null
order by t.ts desc, t.id desc limit 1000`,

  // ---------- Bursa Kapten: jual-beli antar kapten ----------
  bursa: `
with t as (select l.id, l.ts, l.player_id, regexp_match(l.message, '^Membeli ([0-9]+) (.+) dari (.+) di Bursa seharga ([0-9]+) gold\\.$') as r
  from game.player_log l where ${SINCE} and l.message like 'Membeli % di Bursa seharga %')
select t.id::float8 as id, ${WIB('t.ts')} as waktu, ${NAMA} as pembeli, t.r[3] as penjual, t.r[2] as barang, c.tier,
  t.r[1]::float8 as jumlah, t.r[4]::float8 as total,
  round((t.r[4]::numeric / nullif(t.r[1]::numeric, 0)), 1)::float8 as harga_satuan, c.base::float8 as harga_dasar,
  round((100 * (t.r[4]::numeric / nullif(t.r[1]::numeric, 0) / nullif(c.base, 0) - 1))::numeric, 0)::float8 as selisih_pct
from t join game.players p on p.player_id = t.player_id left join game.commodities c on c.name = t.r[2]
where t.r is not null
order by t.ts desc, t.id desc limit 1000`,

  bursaOrder: `
select o.seller_name as penjual, coalesce(ci.name, o.city_id) as pulau, c.name as barang, c.tier, o.qty::float8 as jumlah,
  o.price::float8 as harga_satuan, c.base::float8 as harga_dasar,
  round((100 * (o.price::numeric / nullif(c.base, 0) - 1))::numeric, 0)::float8 as selisih_pct,
  (o.qty::numeric * o.price)::float8 as nilai, ${WIB('o.created_at')} as dipasang
from game.mp_orders o left join game.commodities c on c.id = o.commodity_id left join game.cities ci on ci.city_id = o.city_id
where o.status = 'open' and o.qty > 0 order by nilai desc`,

  // ---------- Daftar kapten untuk pilihan Jejak ----------
  daftar: `select ${NAMA} as kapten, p.username from game.players p where p.archetype <> '' order by 1`,
};

// ---------- Jejak satu kapten ($1 = jam, $2 = nama kapten) ----------
const PID = `(select player_id from game.players p where p.archetype <> '' and ${NAMA} = $2 limit 1)`;
const J = {
  ringkas: `
with me as (select * from game.players p where p.player_id = ${PID})
select ${NAMA.replace(/p\./g, 'me.')} as kapten, me.username, me.archetype as arketipe, me.gold::float8 as gold, me.bank_balance::float8 as bank,
  me.debt_balance::float8 as utang, me.keping::float8 as keping,
  coalesce((select sum(w.qty * c.base) from game.warehouse w join game.commodities c on c.id = w.commodity_id where w.player_id = me.player_id and w.qty > 0), 0)::float8 as nilai_gudang,
  coalesce((select sum(i.qty * c.base) from game.inventory i join game.commodities c on c.id = i.item_id where i.player_id = me.player_id and i.qty > 0), 0)::float8 as nilai_palka,
  ${WIB('me.created_at')} as bergabung, round((extract(epoch from now() - me.created_at) / 86400)::numeric, 1)::float8 as umur_hari,
  ${WIB('me.last_active')} as terakhir_aktif,
  ($1::int is null) as semua
from me`,

  pola: `
with t as (select l.ts from game.player_log l where l.player_id = ${PID} and ${SINCE} and l.message ~ '^(Bought|Sold) '),
g as (select extract(epoch from ts - lag(ts) over (order by ts)) as d from t)
select (select count(*) from t)::int as transaksi,
  round((percentile_cont(0.5) within group (order by d))::numeric, 1)::float8 as jeda_median,
  (count(*) filter (where d < 2))::int as jeda_bawah_2,
  round((100.0 * count(*) filter (where d < 2) / nullif(count(d), 0))::numeric, 1)::float8 as jeda_bawah_2_pct
from g`,

  transfer: `
with me as (select player_id, character_name from game.players where player_id = ${PID}),
keluar as (select l.ts, 'keluar' as arah, (regexp_match(l.message, '^Mengirim ([0-9]+) gold ke (.+)\\.$')) as r
  from game.player_log l, me where l.player_id = me.player_id and ${SINCE} and l.message like 'Mengirim % gold ke %'),
masuk as (select l.ts, 'masuk' as arah, (regexp_match(l.message, '^(.+) mengirimimu ([0-9]+) gold\\.$')) as r
  from game.player_log l, me where l.player_id = me.player_id and ${SINCE} and l.message like '% mengirimimu % gold.')
select ${WIB('ts')} as waktu, arah, r[2] as lawan, r[1]::float8 as jumlah from keluar where r is not null
union all
select ${WIB('ts')}, arah, r[1], r[2]::float8 from masuk where r is not null
order by 1 desc limit 300`,

  hakLot: `
select to_char(h.day_wib, 'YYYY-MM-DD') as hari, coalesce(ci.name, h.city_id) as pulau, h.used::int as lot
from game.honor_lot h left join game.cities ci on ci.city_id = h.city_id
where h.player_id = ${PID} and h.used > 0 and h.day_wib >= (now() at time zone 'Asia/Jakarta')::date - 13
order by h.day_wib desc, h.used desc`,

  log: `
select ${WIB('l.ts')} as waktu, l.message as catatan from game.player_log l
where l.player_id = ${PID} and ${SINCE}
order by l.id desc limit 400`,
};

module.exports = { Q, J };

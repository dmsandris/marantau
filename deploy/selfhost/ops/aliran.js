// Aliran dana: dari mana gold kapten datang dan ke mana gold itu pergi, dari catatan kapten (game.player_log)
// ditambah ronde Kasino Mutiara (game.kasino_round, Tide v84: kasino tidak menulis player_log per ronde).
// Hanya SELECT, dijalankan lewat role baca-saja. $1 = jumlah jam ke belakang (null = semua catatan).
// Setor/tarik bank hanya memindahkan gold antara tangan dan bank, jadi dipisah sebagai "pindah" dan tidak
// dihitung ke masuk/keluar. Bunga bank tidak dicatat di log, jadi tidak muncul di sini.
'use strict';

const SINCE = `($1::int is null or l.ts > now() - ($1::int * interval '1 hour'))`;
const NAMA = `coalesce(nullif(p.character_name, ''), p.username)`;

// Angka gold pertama di pesan ("1,200 gold", "(+350 gold", "-90 gold").
const GOLD = `nullif(replace((regexp_match(l.message, '([0-9][0-9,]*) gold'))[1], ',', ''), '')::float8`;

// Urutan penting: pola paling khusus di atas. Kolom: kat (nama kategori), kel (kelompok), arah (+1 masuk, -1 keluar, 0 pindah/tak pasti).
const KAT = `
case
  when m like 'Bought "%' then 'Beli item dan peta|Item dan harta|-1'
  when m like 'Galian di %' then 'Galian harta|Item dan harta|1'
  when m like 'Sold %x "%' then 'Jual item dan artefak|Item dan harta|1'
  when m like 'Sold %' then 'Jual barang dagang|Dagang|1'
  when m like 'Bought %' then 'Beli barang dagang|Dagang|-1'
  when m like 'Deposited %' then 'Setor ke bank|Bank|0'
  when m like 'Withdrew %' then 'Tarik dari bank|Bank|0'
  when m like 'Borrowed %' then 'Pinjam rentenir|Bank|1'
  when m like 'Repaid %' then 'Lunasi rentenir|Bank|-1'
  when m like 'Memancing %' then 'Memancing|Pancing|1'
  when m like 'Made landfall%(+%' then 'Pancing di pelayaran|Pancing|1'
  when m like 'Made landfall%' then 'Perbaikan darurat badai|Kapal|-1'
  when m like 'Stored %fee: %' then 'Biaya titip gudang|Gudang|-1'
  when m like 'Hak Lot: %' then 'Beli lewat Hak Lot|Dagang|-1'
  when m like 'Menerima pesanan %' or m like 'Menerima titipan %' then 'Terima misi, belum ada uang|Misi|0'
  when m like 'Memasang order Bursa%' then 'Pasang order Bursa, belum ada uang|Antar kapten|0'
  when m like 'Membeli % pesanan di % seharga %' then 'Beli muatan Pesanan|Misi|-1'
  when m like 'Misi selesai%' then 'Imbalan misi gubernur|Misi|1'
  when m like 'Pesanan Harian selesai%' then 'Pesanan Harian|Harian dan lomba|1'
  when m like 'Pacu Dagang %' then 'Hadiah Pacu Dagang|Harian dan lomba|1'
  when m like 'Repaired the ship%' then 'Reparasi kapal|Kapal|-1'
  when m like 'Upgraded ship%' then 'Upgrade kapal|Kapal|-1'
  when m like '% mengirimimu % gold%' then 'Transfer masuk|Antar kapten|1'
  when m like 'Mengirim % gold ke %' then 'Transfer keluar|Antar kapten|-1'
  when m like '%dari order Bursa-mu (+%' then 'Jual lewat Bursa|Antar kapten|1'
  when m like '% di Bursa seharga %' then 'Beli lewat Bursa|Antar kapten|-1'
  when m like 'Menang duel%' or m like 'Taruhan duel dimenangkan%' then 'Menang duel|Antar kapten|1'
  when m like 'Kalah duel%' or m like 'Taruhan duel lepas%' then 'Kalah duel|Antar kapten|-1'
  when m like 'Menanam % di kapal kongsi%' then 'Modal Balai Kongsi|Kongsi|-1'
  when m like 'Kapal kongsi % kembali %' or m like 'Memanggil pulang kapal kongsi%' or m like 'Ki Dorus mengirim hasil%' then 'Hasil Balai Kongsi|Kongsi|1'
  when m like 'Menyumbang %' then 'Sumbangan IKN|Sumbangan|-1'
  when m like 'Dikepung Tony%' then 'Dirampas Tony and Gank|Bajak laut|-1'
  when m like 'Tony and Gank kabur%' then 'Jarahan Tony|Bajak laut|1'
  when m like 'Purchased "%' then 'Beli buku|Belanja lain|-1'
  when m like 'Membeli Joran%' or m like 'Membeli Umpan%' then 'Beli alat pancing|Belanja lain|-1'
  when m like 'Meminjamkan % kepada coco%' then 'Pinjaman ke coco epan|Quest|-1'
  when m like '%coco epan melunasi%' then 'Pelunasan coco epan|Quest|1'
  when m like 'Membayar jaminan%' or m like 'Menyetor %' then 'Setoran quest|Quest|-1'
  when m like 'Jejak Perantau%' then 'Hadiah Jejak Perantau|Quest|1'
  when m ~ '\\(-[0-9][0-9,]* gold' or m ~* '(seharga|membayar|dibayar|diambil|kehilangan|denda)' then 'Pengeluaran lain|Lain-lain|-1'
  when m ~ '\\+[0-9][0-9,]* gold' or m ~* '(hadiah|imbalan|menerima|menemukan|mendapat|dikembalikan|mengembalikan|menghadiahkan|untukmu|rampasan|kiriman|mengangkut)' then 'Hadiah quest dan lainnya|Quest|1'
  else 'Arah tak pasti|Lain-lain|0'
end`;

const BASE = `
x as (select l.player_id, l.message as m, ${GOLD} as g, l.ts from game.player_log l
  where ${SINCE} and l.message like '% gold%'),
kc as (select player_id, ts, g, ${KAT} as c from x where g is not null),
kl as (select player_id, ts, g, split_part(c, '|', 1) as kat, split_part(c, '|', 2) as kel, split_part(c, '|', 3)::int as arah from kc),
kz as (select r.player_id, r.settled_at as ts, abs(r.net_delta)::float8 as g,
  case when r.net_delta > 0 then 'Menang kasino' else 'Kalah kasino' end as kat, 'Kasino' as kel, sign(r.net_delta)::int as arah
  from game.kasino_round r where r.status <> 'active' and r.net_delta <> 0
   and ($1::int is null or r.settled_at > now() - ($1::int * interval '1 hour'))),
k as (select * from kl union all select * from kz)`;

const Q = {
  // Total per kategori di seluruh server.
  kategori: `
with ${BASE}
select kat, kel, arah, count(*)::int as kejadian, count(distinct player_id)::int as pemain, sum(g)::float8 as gold
from k group by kat, kel, arah order by arah desc, gold desc`,

  // Per kapten: masuk, keluar, bersih, dan sumber/tujuan terbesar.
  kapten: `
with ${BASE},
pk as (select player_id, kat, arah, sum(g) as g from k group by 1, 2, 3),
top_in as (select distinct on (player_id) player_id, kat, g from pk where arah = 1 order by player_id, g desc),
top_out as (select distinct on (player_id) player_id, kat, g from pk where arah = -1 order by player_id, g desc),
agg as (select player_id,
  coalesce(sum(g) filter (where arah = 1), 0) as masuk, coalesce(sum(g) filter (where arah = -1), 0) as keluar,
  coalesce(sum(g) filter (where arah = 1 and kat in ('Galian harta', 'Jual item dan artefak')), 0) as dari_harta,
  coalesce(sum(g) filter (where arah = 1 and kat = 'Jual barang dagang'), 0) as dari_dagang,
  coalesce(sum(g) filter (where arah = 1 and kat in ('Transfer masuk', 'Jual lewat Bursa', 'Menang duel')), 0) as dari_kapten,
  coalesce(sum(case when kel = 'Kasino' then g * arah else 0 end), 0) as kasino_bersih,
  count(*) as kejadian from k group by player_id)
select ${NAMA} as kapten, p.username, a.masuk::float8, a.keluar::float8, (a.masuk - a.keluar)::float8 as bersih,
  a.dari_dagang::float8, a.dari_harta::float8, a.dari_kapten::float8,
  round((100 * a.dari_harta / nullif(a.masuk, 0))::numeric, 1)::float8 as harta_pct,
  ti.kat as sumber_utama, ti.g::float8 as sumber_utama_gold, tt.kat as tujuan_utama, tt.g::float8 as tujuan_utama_gold,
  a.kasino_bersih::float8, a.kejadian::int, (p.gold + p.bank_balance - p.debt_balance)::float8 as kekayaan_kini
from agg a join game.players p on p.player_id = a.player_id
left join top_in ti on ti.player_id = a.player_id left join top_out tt on tt.player_id = a.player_id
where p.archetype <> ''
order by a.masuk desc`,

  // Kapten × kategori, untuk rincian satu kapten di klien.
  matriks: `
with ${BASE}
select ${NAMA} as kapten, k.kat, k.arah, count(*)::int as kejadian, sum(k.g)::float8 as gold
from k join game.players p on p.player_id = k.player_id where p.archetype <> ''
group by 1, 2, 3 order by 1, gold desc`,

  // Per hari WIB: masuk & keluar menurut kelompok (maks 30 hari).
  harian: `
with ${BASE}
select to_char(ts at time zone 'Asia/Jakarta', 'YYYY-MM-DD') as hari, kel, arah, sum(g)::float8 as gold
from k where arah <> 0 and ts > now() - interval '30 days'
group by 1, 2, 3 order by 1`,
};

module.exports = { Q, KAT, GOLD };

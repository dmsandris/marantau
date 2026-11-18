// Query dashboard Ekonomi & Kapten untuk Panel Ops. Hanya SELECT. Dijalankan lewat role baca-saja.
// Semua angka dikirim sebagai float8 supaya sampai ke klien sebagai angka (bukan teks).
'use strict';

const IKN_TARGET_DEFAULT = 100000000; // jumlah need semua tahap Restorasi IKN (5+10+20+25+40 jt)

const GOLD_OF = `nullif(replace((regexp_match(message, '([0-9][0-9,]*) gold'))[1], ',', ''), '')::float8`;

const Q = {
  ringkasan: `
with cfg as (select game.cfg_num('GameDayLengthRealMinutes', 180) as m, game.bank_tiers() as tiers),
p as (select gold::float8 as g, bank_balance::float8 as b, debt_balance::float8 as d, last_active, (gold + bank_balance)::float8 as w
      from game.players where archetype <> ''),
rk as (select w, row_number() over (order by w desc) as n from p),
tr as (select coalesce(sum(case when message like 'Sold %' then (regexp_match(message, 'for ([0-9]+) gold'))[1]::float8 else 0 end), 0)
             - coalesce(sum(case when message like 'Bought %' then (regexp_match(message, 'for ([0-9]+) gold'))[1]::float8 else 0 end), 0) as laba
       from game.player_log where ts > now() - interval '24 hours' and message ~ '^(Sold|Bought) '),
gi as (select sum(abs(a.w - b.w)) as s from p a cross join p b),
bg as (select sum(game.bank_interest_day(p.b, cfg.tiers)) as v from p cross join cfg)
select (select count(*) from p)::int as pemain,
  (select count(*) from p where last_active > now() - interval '24 hours')::int as aktif_24j,
  (select count(*) from p where last_active > now() - interval '7 days')::int as aktif_7h,
  (select count(*) from game.mp_presence where ts > now() - interval '2 minutes')::int as online_sekarang,
  (select sum(g) from p)::float8 as total_gold, (select sum(b) from p)::float8 as total_bank, (select sum(d) from p)::float8 as total_utang,
  (select sum(w) from p)::float8 as total_kekayaan,
  (select percentile_cont(0.5) within group (order by w) from p)::float8 as median_kekayaan,
  round((100 * (select w from rk where n = 1) / nullif((select sum(w) from p), 0))::numeric, 1)::float8 as pangsa_terkaya_pct,
  round((100 * (select sum(w) from rk where n <= 3) / nullif((select sum(w) from p), 0))::numeric, 1)::float8 as pangsa_top3_pct,
  round((gi.s / nullif(2 * (select count(*) from p) * (select sum(w) from p), 0))::numeric, 3)::float8 as gini,
  round(bg.v)::float8 as bunga_per_hari_game,
  round(bg.v * 1440 / cfg.m)::float8 as bunga_per_hari,
  tr.laba::float8 as laba_dagang_24j,
  round((bg.v * 1440 / cfg.m / nullif(tr.laba, 0))::numeric, 1)::float8 as rasio_bunga_dagang,
  to_char(now() at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI') as diperbarui_wib
from cfg, tr, gi, bg`,

  dagang: `
with x as (select (ts at time zone 'Asia/Jakarta')::date as d,
  coalesce(sum(case when message like 'Sold %' then (regexp_match(message, 'for ([0-9]+) gold'))[1]::float8 else 0 end), 0) as jual,
  coalesce(sum(case when message like 'Bought %' then (regexp_match(message, 'for ([0-9]+) gold'))[1]::float8 else 0 end), 0) as beli,
  count(distinct player_id)::int as pedagang
  from game.player_log where ts > now() - interval '15 days' and message ~ '^(Sold|Bought) ' group by 1)
select to_char(g::date, 'YYYY-MM-DD') as hari, coalesce(x.jual, 0)::float8 as jual, coalesce(x.beli, 0)::float8 as beli,
  (coalesce(x.jual, 0) - coalesce(x.beli, 0))::float8 as laba, coalesce(x.pedagang, 0)::int as pedagang
from generate_series((now() at time zone 'Asia/Jakarta')::date - 13, (now() at time zone 'Asia/Jakarta')::date, interval '1 day') g
left join x on x.d = g::date order by 1`,

  arus: `
with l as (select player_id, message as m, ${GOLD_OF} as g from game.player_log where ts > now() - interval '24 hours'),
k as (select player_id, g, case
  when m like 'Sold %' then 'Jual barang' when m like 'Bought %' then 'Beli barang'
  when m like 'Deposited%' then 'Setor ke bank' when m like 'Withdrew%' then 'Tarik dari bank'
  when m ilike 'Memancing%' then 'Pancing'
  when m ilike '%Pesanan Harian%' or m ilike '%pacu%' then 'Harian dan Pacu'
  when m ilike '%misi%' or m ilike '%mission%' then 'Misi gubernur'
  when m ilike '%loot%' or m ilike '%rampas%' or m ilike '%victory%' then 'Tempur'
  when m ilike 'Purchased%' or m ilike 'Upgraded%' or m ilike '%Menyumbang%' then 'Belanja buku, upgrade, donasi'
  else 'Quest dan lainnya' end as arus from l where g is not null)
select arus, count(*)::int as kejadian, count(distinct player_id)::int as pemain, sum(g)::float8 as gold from k group by arus order by gold desc`,

  stok: `
with b as (select c.id, count(*) as n, count(distinct l.player_id) as pl from game.player_log l
  join game.commodities c on l.message like 'Bought % of ' || c.name || ' for %' where l.ts > now() - interval '24 hours' group by c.id),
s as (select m.city_id, c.id, c.name, c.grp, c.tier, c.ref, c.sort, m.current_price,
  game.mkt_project(m.stock, m.at, m.cyc, m.role, c.tier, c.ref, c.id, game.mkt_cycle_tags(m.city_id, game.mkt_cycle_index()), game.mkt_cycle_index()) as stok
  from game.market m join game.commodities c on c.id = m.commodity_id where c.active)
select s.name as barang, s.grp as kelompok, s.tier,
  round(avg(s.stok / nullif(s.ref, 0))::numeric, 3)::float8 as rasio_stok,
  round(max(s.stok / nullif(s.ref, 0))::numeric, 3)::float8 as rasio_terbaik,
  (count(*) filter (where s.stok < s.ref * 0.3))::int as kota_menipis, count(*)::int as kota,
  min(s.current_price)::int as harga_min, max(s.current_price)::int as harga_max,
  coalesce(b.n, 0)::int as beli_24j, coalesce(b.pl, 0)::int as pembeli_24j
from s left join b on b.id = s.id
group by s.id, s.name, s.grp, s.tier, s.sort, b.n, b.pl
order by case s.tier when 'premium' then 0 when 'mid' then 1 else 2 end, rasio_stok`,

  ikn: `
select (select coalesce(total, 0) from game.gr_projects where id = 'ikn')::float8 as total,
  (select stage from game.gr_projects where id = 'ikn')::int as tahap,
  (select stages from game.gr_projects where id = 'ikn') as tahap_daftar,
  (select done_at is not null from game.gr_projects where id = 'ikn') as selesai,
  (select count(*) from game.gr_donations where project_id = 'ikn')::int as donatur,
  (select coalesce(sum(gold), 0) from game.gr_donations where project_id = 'ikn')::float8 as dari_gold,
  (select coalesce(sum(keping), 0) from game.gr_donations where project_id = 'ikn')::float8 as dari_keping,
  (select coalesce(sum(kongsi), 0) from game.gr_donations where project_id = 'ikn')::float8 as dari_kongsi,
  (select coalesce(sum(duneks), 0) from game.gr_donations where project_id = 'ikn')::float8 as dari_duneks,
  (select coalesce(sum(jtq), 0) from game.gr_donations where project_id = 'ikn')::float8 as dari_jtq,
  (select coalesce(max(total), 0) from game.gr_donations where project_id = 'ikn')::float8 as donatur_terbesar`,

  kongsiTier: `
select tier, status, count(*)::int as n, coalesce(sum(modal), 0)::float8 as modal, coalesce(sum(payout), 0)::float8 as bayar
from game.kongsi group by tier, status order by tier, status`,

  kongsiMinggu: `
select to_char(week, 'YYYY-MM-DD') as minggu, modal::float8, bayar::float8, laba::float8, donasi::float8, pengongsi::int
from game.kongsi_week order by week desc limit 8`,

  keping: `
select sumber, count(*)::int as n, coalesce(sum(delta) filter (where delta > 0), 0)::float8 as terbit,
  coalesce(-sum(delta) filter (where delta < 0), 0)::float8 as terpakai
from game.keping_log where ts > now() - interval '7 days' group by sumber order by terbit desc`,

  kepingTotal: `
select coalesce(sum(delta) filter (where delta > 0), 0)::float8 as terbit, coalesce(-sum(delta) filter (where delta < 0), 0)::float8 as terpakai,
  (select coalesce(sum(saldo), 0) from (select distinct on (player_id) saldo from game.keping_log order by player_id, ts desc, id desc) z)::float8 as beredar
from game.keping_log`,

  tony: `
select (select count(*) from game.tony_victims)::int as korban,
  (select coalesce(sum(gold_taken), 0) from game.tony_victims)::float8 as emas,
  (select coalesce(sum(cargo_value), 0) from game.tony_victims)::float8 as kargo,
  (select count(*) from game.tony_hunts)::int as perburuan,
  (select coalesce(sum(harta), 0) from game.tony_hunts)::float8 as harta,
  (select coalesce(sum(paid), 0) from game.tony_hunts)::float8 as dibayar`,

  tonyBuru: `
select to_char(hunt_day, 'YYYY-MM-DD') as hari, harta::float8, pool::float8, paid::float8 as dibayar,
  coalesce(jsonb_array_length(case when jsonb_typeof(shares) = 'array' then shares else '[]'::jsonb end), 0)::int as peserta,
  kabur_at is not null as kabur
from game.tony_hunts order by hunt_day desc limit 6`,

  pacu: `
select e.id, to_char(e.sat, 'YYYY-MM-DD') as sabtu, e.theme as tema, e.status,
  (select count(*) from game.pd_scores s where s.event_id = e.id and not coalesce(s.banned, false))::int as peserta,
  coalesce((select sum(s.profit) from game.pd_scores s where s.event_id = e.id and not coalesce(s.banned, false)), 0)::float8 as laba_peserta
from game.pd_events e order by e.sat desc limit 5`,

  pemain: `
with cfg as (select game.cfg_num('GameDayLengthRealMinutes', 180) as m, game.bank_tiers() as tiers),
tr as (select player_id,
  coalesce(sum(case when message like 'Sold %' then (regexp_match(message, 'for ([0-9]+) gold'))[1]::float8 else 0 end), 0) as jual24,
  coalesce(sum(case when message like 'Bought %' then (regexp_match(message, 'for ([0-9]+) gold'))[1]::float8 else 0 end), 0) as beli24,
  count(*) filter (where message like 'Set sail%') as layar24
  from game.player_log where ts > now() - interval '24 hours' group by player_id),
mu as (select x.player_id, sum(x.qty * c.base) as v from (select player_id, item_id as cid, qty from game.inventory
  union all select player_id, commodity_id, qty from game.warehouse) x join game.commodities c on c.id = x.cid group by x.player_id),
tot as (select sum(gold + bank_balance) as t from game.players where archetype <> '')
select p.character_name as pemain, p.archetype as arketipe, coalesce(s.tier, '') as kapal,
  case when l.arrive_at > now() then 'laut ke ' || coalesce(l.destination_city_id, '') else coalesce(l.city_id, '') end as lokasi,
  p.gold::float8 as gold, p.bank_balance::float8 as bank, p.debt_balance::float8 as utang,
  coalesce(mu.v, 0)::float8 as nilai_muatan, (p.gold + p.bank_balance)::float8 as kekayaan,
  round((100.0 * (p.gold + p.bank_balance) / nullif(tot.t, 0))::numeric, 2)::float8 as pangsa_pct,
  round(game.bank_interest_day(p.bank_balance::float8, cfg.tiers) * 1440 / cfg.m)::float8 as bunga_per_hari,
  coalesce(tr.jual24, 0)::float8 as jual_24j, coalesce(tr.beli24, 0)::float8 as beli_24j,
  (coalesce(tr.jual24, 0) - coalesce(tr.beli24, 0))::float8 as selisih_dagang_24j,
  coalesce(tr.layar24, 0)::int as layar_24j,
  (select count(*) from game.player_books b where b.player_id = p.player_id)::int as buku,
  round((extract(epoch from now() - p.last_active) / 3600)::numeric, 1)::float8 as jam_sejak_aktif,
  to_char(p.created_at at time zone 'Asia/Jakarta', 'YYYY-MM-DD') as bergabung
from game.players p cross join tot cross join cfg
left join game.ships s on s.player_id = p.player_id
left join game.player_location l on l.player_id = p.player_id
left join tr on tr.player_id = p.player_id
left join mu on mu.player_id = p.player_id
where p.archetype <> ''
order by kekayaan desc`,
};

// Katalog quest dipakai bersama oleh dua query quest.
const QUEST_CAT = `
cat(qid, no, saga, nama, akhir) as (values
 ('gala',1,'Saga 1','Harta Uda Gala',6),('toogood',2,'Saga 1','Pembebasan TooGood',10),('warwerwor',3,'Saga 1','Warwerwor',12),('barsati',4,'Saga 1','Tiga Tanda Silang',16),
 ('kompas',5,'Saga 2','Kompas yang Berputar',8),('cocoepan',6,'Saga 2','Bunga yang Tak Pernah Layu',11),('tigasilang',7,'Saga 2','Malam Tiga Tanda Silang',12),('limatangan',8,'Saga 2','Lima Tangan',10),('duatangan',9,'Saga 2','Serbuan Bersama',5),
 ('ps10',10,'Saga 3','Penumpang Bergaun Putih',11),('ps11',11,'Saga 3','Kapal yang Tak Pernah Terdampar',10),('ps12',12,'Saga 3','Kota yang Lampunya Sampai ke Laut',7),('ps13',13,'Saga 3','Laksamana yang Tak Pernah Tenggelam',7),('ps14',14,'Saga 3','Pasir Terakhir',6),
 ('mahkota',15,'Saga 4','Monopoli dan Mahkota',game.mk_last())),
sidecat(qid, no, nama, pendek, akhir) as (values
 ('peregrin',90,'Mesin yang Hanyut (Lorang Peregrin)','Lorang Peregrin',game.pg_last()),
 ('duneks',91,'Knock-knock Gudang Door','Gudang Door',game.dn_last()),
 ('jtq',92,'Bunga yang Tak Pernah Dipetik','Rekening J.T.',game.jt_last()),
 ('surat',93,'Surat yang Selalu Tertinggal Satu Pelabuhan','Surat Pulang',game.sp_last()))`;

Q.questPemain = `
with ${QUEST_CAT},
q as (select q.*, c.no, c.saga, c.nama, c.akhir from game.player_quests q join cat c on c.qid = q.quest_id),
aktif as (select distinct on (player_id) player_id, no, saga, nama, akhir, step, updated_at from q where done_at is null order by player_id, no),
sel as (select player_id, count(*)::int as n, max(no) as maxno, string_agg('Q' || no, ', ' order by no) as daftar, max(done_at) as terakhir from q where done_at is not null group by player_id),
side as (select q.player_id, string_agg(s.pendek || ' ' || case when q.done_at is not null then 'tamat' else q.step || '/' || s.akhir end, ', ' order by s.no) as s
  from game.player_quests q join sidecat s on s.qid = q.quest_id group by q.player_id),
per as (select player_id, step, (data->>'eligible')::boolean as el from game.player_quests where quest_id = 'perantau')
select p.character_name as pemain,
 case when a.player_id is not null then a.saga when s.maxno is null then 'Belum mulai' when s.maxno = 15 then 'Saga 4' when s.maxno = 14 then 'Saga 3' else (select saga from cat where no = s.maxno + 1) end as saga,
 case when a.player_id is not null then a.nama
      when s.maxno is null then 'Mengumpulkan Tanda Jasa'
      when s.maxno = 15 then 'Tamat Saga 4'
      when s.maxno = 14 then 'Tamat Saga 3'
      else 'Belum terpicu: ' || (select nama from cat where no = s.maxno + 1) end as quest_kini,
 case when a.player_id is not null then a.no end as quest_no,
 a.step::int as langkah, a.akhir::int as langkah_akhir,
 coalesce(s.n, 0) as tamat, coalesce(s.daftar, '') as quest_tamat, coalesce(sd.s, '') as sampingan,
 case when per.el then per.step end::int as jejak_perantau,
 to_char(greatest(a.updated_at, s.terakhir) at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI') as gerak_terakhir,
 round((extract(epoch from now() - p.last_active) / 3600)::numeric, 1)::float8 as jam_sejak_aktif
from game.players p
left join aktif a on a.player_id = p.player_id left join sel s on s.player_id = p.player_id
left join side sd on sd.player_id = p.player_id left join per on per.player_id = p.player_id
where p.archetype <> ''
order by coalesce(a.no, s.maxno + 0.5, 0) desc, a.step desc nulls last, p.character_name`;

Q.questRingkas = `
with ${QUEST_CAT},
semua as (select qid, no, saga, nama from cat union all select qid, no, 'Sampingan', nama from sidecat),
q as (select q.quest_id, q.done_at from game.player_quests q join game.players p on p.player_id = q.player_id where p.archetype <> '')
select case when s.no < 90 then 'Q' || s.no || ' ' || s.nama else s.nama end as quest, s.saga, s.no::int as no,
 count(q.done_at)::int as tamat, (count(q.quest_id) - count(q.done_at))::int as berjalan
from semua s left join q on q.quest_id = s.qid
group by s.no, s.nama, s.saga order by s.no`;

module.exports = { Q, IKN_TARGET_DEFAULT };

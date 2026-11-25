// Query tab Kasino (Kasino Mutiara, Tide v84). Hanya SELECT, role baca-saja.
// Sumber: game.kasino_round (satu baris per ronde, saldo sebelum/sesudah = money trace) dan game.kasino_edge_audit.
// $1 = jumlah jam ke belakang (null = semua).
'use strict';

const WIB = c => `to_char(${c} at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI:SS')`;
const NAMA = `coalesce(nullif(p.character_name, ''), p.username)`;
const SINCE = `($1::int is null or r.created_at > now() - ($1::int * interval '1 hour'))`;
const TODAY = `((now() at time zone 'Asia/Jakarta')::date)`;
const MEJA = `case r.game_type when 'dadu' then 'Duel Dadu' when 'roulette' then 'Roulette' when 'blackjack' then 'Blackjack' else 'Slot' end`;

const Q = {
  ringkas: `
select count(*) filter (where r.status <> 'active')::int as ronde,
  count(distinct r.player_id)::int as kapten,
  coalesce(sum(r.bet_amount) filter (where r.status <> 'active'), 0)::float8 as putaran,
  coalesce(sum(r.payout_amount) filter (where r.status <> 'active'), 0)::float8 as bayaran,
  (-coalesce(sum(r.net_delta) filter (where r.status <> 'active'), 0))::float8 as bandar_bersih,
  coalesce(sum(r.net_delta) filter (where r.net_delta > 0), 0)::float8 as faucet,
  (-coalesce(sum(r.net_delta) filter (where r.net_delta < 0), 0))::float8 as sink,
  count(*) filter (where r.capped)::int as kena_batas,
  (select count(*)::int from game.kasino_round where status = 'active') as aktif_kini,
  (select value from game.config where key = 'KasinoOpen') as gerbang,
  coalesce((select value::numeric from game.config where key = 'KasinoMenangHarian'), 2500000)::float8 as batas_harian
from game.kasino_round r where ${SINCE}`,

  meja: `
select ${MEJA} as meja, r.game_type,
  (select value from game.config where key = 'KasinoEdge' || initcap(r.game_type))::float8 * 100 as edge_kini_pct,
  count(*)::int as ronde, sum(r.bet_amount)::float8 as putaran, sum(r.payout_amount)::float8 as bayaran,
  (sum(r.bet_amount) - sum(r.payout_amount))::float8 as bandar_bersih,
  round((100 * sum(r.payout_amount) / nullif(sum(r.bet_amount), 0))::numeric, 2)::float8 as rtp_pct,
  round((100 * sum(r.bet_amount * (1 - r.edge_applied)) / nullif(sum(r.bet_amount), 0))::numeric, 2)::float8 as rtp_target_pct,
  count(*) filter (where r.capped)::int as kena_batas, max(r.payout_amount / r.bet_amount)::float8 as pengali_maks
from game.kasino_round r where r.status <> 'active' and ${SINCE}
group by r.game_type order by putaran desc`,

  harian: `
select to_char(r.ks_day, 'YYYY-MM-DD') as hari, count(*)::int as ronde, count(distinct r.player_id)::int as kapten,
  sum(r.bet_amount)::float8 as putaran,
  (-coalesce(sum(r.net_delta) filter (where r.net_delta < 0), 0))::float8 as sink,
  coalesce(sum(r.net_delta) filter (where r.net_delta > 0), 0)::float8 as faucet,
  (-sum(r.net_delta))::float8 as bandar_bersih
from game.kasino_round r where r.status <> 'active' and r.ks_day > ${TODAY} - 30
group by r.ks_day order by r.ks_day desc`,

  kapten: `
select ${NAMA} as kapten, p.username, count(*)::int as ronde, sum(r.bet_amount)::float8 as putaran,
  coalesce(sum(r.net_delta) filter (where r.net_delta > 0), 0)::float8 as menang,
  (-coalesce(sum(r.net_delta) filter (where r.net_delta < 0), 0))::float8 as kalah,
  sum(r.net_delta)::float8 as bersih,
  coalesce(sum(r.net_delta) filter (where r.ks_day = ${TODAY}), 0)::float8 as bersih_hari_ini,
  count(*) filter (where r.capped)::int as kena_batas,
  ${WIB('max(r.created_at)')} as terakhir, p.gold::float8 as gold_kini
from game.kasino_round r join game.players p on p.player_id = r.player_id
where r.status <> 'active' and ${SINCE}
group by p.player_id, p.character_name, p.username, p.gold order by bersih desc`,

  // $2 = saring kapten (ilike), $3 = meja ('' semua), $4 = status ('' semua)
  feed: `
select r.id::float8 as id, ${WIB('r.created_at')} as waktu, r.game_day as hari_game, to_char(r.ks_day, 'YYYY-MM-DD') as hari_wib,
  ${NAMA} as kapten, p.username, ${MEJA} as meja, r.gold_before::float8 as gold_sebelum, r.bet_amount::float8 as taruhan,
  r.payout_amount::float8 as bayaran, r.net_delta::float8 as selisih, r.gold_after::float8 as gold_sesudah,
  round(r.edge_applied * 100, 2)::float8 as edge_pct, r.status, r.capped as kena_batas,
  left((r.state_json - 'out' - 'shoe' - 'acts' - 'i' - 'k')::text, 220) as detail
from game.kasino_round r join game.players p on p.player_id = r.player_id
where ${SINCE}
  and ($2::text = '' or ${NAMA} ilike $2 or p.username ilike $2)
  and ($3::text = '' or r.game_type = $3)
  and ($4::text = '' or r.status = $4)
order by r.id desc limit 300`,

  audit: `
select ${WIB('a.created_at')} as waktu, coalesce(p.username, '?') as gm,
  case a.game_type when 'dadu' then 'Duel Dadu' when 'roulette' then 'Roulette' when 'blackjack' then 'Blackjack' else 'Slot' end as meja,
  round(a.old_edge * 100, 2)::float8 as edge_lama_pct, round(a.new_edge * 100, 2)::float8 as edge_baru_pct, a.note as catatan
from game.kasino_edge_audit a left join game.players p on p.player_id = a.gm_id
order by a.id desc limit 100`,

  // ---- Pengecekan tambahan (v86): gerbang & konfigurasi, alarm z-score, kuota, papan gambler, ronde besar, aktif, kapten janggal ----
  gerbang: `
select c.key, c.value from game.config c where c.key like 'Kasino%' or c.key = 'FiturPenguji' order by c.key`,

  // z-score per meja, seluruh riwayat (rumus sama dengan ks_gm_stats yang dipakai panel GM)
  alarm: `
with s as (
  select r.game_type g, count(*)::int n, sum(r.bet_amount::numeric) bet, sum(r.payout_amount::numeric) pay,
    sum(r.bet_amount::numeric * (1 - r.edge_applied::numeric)) expv, sum(power(r.bet_amount::numeric, 2)) b2,
    avg(power(r.payout_amount::numeric / r.bet_amount - (1 - r.edge_applied::numeric), 2)) v
  from game.kasino_round r where r.status <> 'active' group by r.game_type),
z as (select *, case when v > 0 and b2 > 0 then (pay - expv) / sqrt(b2 * v) else 0 end zz from s),
m as (select coalesce((select value::numeric from game.config where key = 'KasinoAlarmMinRonde'), 1000) as min_ronde)
select case z.g when 'dadu' then 'Duel Dadu' when 'roulette' then 'Roulette' when 'blackjack' then 'Blackjack' else 'Slot' end as meja,
  z.n as ronde, m.min_ronde::int as min_ronde, round(100 * z.pay / nullif(z.bet, 0), 2)::float8 as rtp_pct, round(100 * z.expv / nullif(z.bet, 0), 2)::float8 as rtp_target_pct,
  round(z.zz, 2)::float8 as z,
  (z.n >= m.min_ronde and (z.zz > 4 or (z.g <> 'blackjack' and z.zz < -4))) as alarm
from z, m order by z.n desc`,

  // kuota menang harian per kapten (hari nyata WIB, hanya GM yang boleh lihat)
  kuota: `
select ${NAMA} as kapten, p.username, d.net::float8 as bersih, d.rounds as ronde, d.turnover::float8 as putaran,
  c.cap::float8 as batas, greatest(0, c.cap - d.net)::float8 as sisa, round((100 * d.net / nullif(c.cap, 0))::numeric, 0)::float8 as terpakai_pct
from game.kasino_daily d join game.players p on p.player_id = d.player_id,
  (select coalesce((select value::numeric from game.config where key = 'KasinoMenangHarian'), 2500000)::bigint as cap) c
where d.ks_day = ${TODAY} and d.rounds > 0 order by d.net desc limit 40`,

  // papan gambler yang tampil di lobi pemain (peringkat total taruhan) + menang bersihnya, yang tidak tampil ke pemain
  topHari: `
select ${NAMA} as kapten, p.username, d.turnover::float8 as putaran, d.rounds as ronde, d.net::float8 as bersih
from game.kasino_daily d join game.players p on p.player_id = d.player_id
where d.ks_day = ${TODAY} and d.turnover > 0 order by d.turnover desc, d.rounds desc limit 10`,
  topPekan: `
select ${NAMA} as kapten, p.username, sum(d.turnover)::float8 as putaran, sum(d.rounds)::int as ronde, sum(d.net)::float8 as bersih,
  to_char(date_trunc('week', ${TODAY}::timestamp)::date, 'YYYY-MM-DD') as sejak
from game.kasino_daily d join game.players p on p.player_id = d.player_id
where d.ks_day between date_trunc('week', ${TODAY}::timestamp)::date and ${TODAY}
group by p.player_id, p.character_name, p.username having sum(d.turnover) > 0 order by 3 desc, 4 desc limit 10`,

  besar: `
select ${WIB('r.created_at')} as waktu, ${NAMA} as kapten, p.username, ${MEJA} as meja, r.bet_amount::float8 as taruhan,
  r.payout_amount::float8 as bayaran, r.net_delta::float8 as selisih, round((r.payout_amount::numeric / r.bet_amount), 1)::float8 as pengali, r.capped as kena_batas
from game.kasino_round r join game.players p on p.player_id = r.player_id
where r.status <> 'active' and ${SINCE} order by r.net_delta desc limit 15`,

  aktif: `
select ${NAMA} as kapten, p.username, r.bet_amount::float8 as taruhan, r.gold_before::float8 as gold_sebelum,
  round(extract(epoch from now() - r.created_at))::int as umur_detik,
  coalesce((select value::int from game.config where key = 'KasinoBjDetik'), 120) as batas_detik
from game.kasino_round r join game.players p on p.player_id = r.player_id
where r.status = 'active' order by r.created_at`,

  // kapten dengan hasil paling menyimpang dari harapan (z), minimal 100 ronde. Blackjack bias karena strategi pemain beda dari basic strategy.
  curiga: `
select ${NAMA} as kapten, p.username, count(*)::int as ronde, sum(r.bet_amount)::float8 as putaran,
  round((100 * sum(r.payout_amount::numeric) / nullif(sum(r.bet_amount::numeric), 0)), 1)::float8 as rtp_pct,
  round((100 * sum(r.bet_amount::numeric * (1 - r.edge_applied::numeric)) / nullif(sum(r.bet_amount::numeric), 0)), 1)::float8 as rtp_target_pct,
  round((case when avg(power(r.payout_amount::numeric / r.bet_amount - (1 - r.edge_applied::numeric), 2)) > 0
    then (sum(r.payout_amount::numeric) - sum(r.bet_amount::numeric * (1 - r.edge_applied::numeric)))
      / sqrt(sum(power(r.bet_amount::numeric, 2)) * avg(power(r.payout_amount::numeric / r.bet_amount - (1 - r.edge_applied::numeric), 2))) else 0 end), 2)::float8 as z,
  sum(r.net_delta)::float8 as bersih
from game.kasino_round r join game.players p on p.player_id = r.player_id
where r.status <> 'active' group by p.player_id, p.character_name, p.username having count(*) >= 100 order by z desc limit 15`,
};

Q.auditBatas = `
select ${WIB('a.created_at')} as waktu, coalesce(p.username, '?') as gm, a.old_limit::float8 as lama, a.new_limit::float8 as baru, a.note as catatan
from game.kasino_limit_audit a left join game.players p on p.player_id = a.gm_id order by a.id desc limit 50`;

const GAMES = ['', 'dadu', 'roulette', 'blackjack', 'slot'];
const STATUS = ['', 'settled', 'active', 'expired'];
const likePat = s => '%' + String(s || '').replace(/[\\%_]/g, c => '\\' + c).slice(0, 60) + '%';

module.exports = { Q, GAMES, STATUS, likePat };

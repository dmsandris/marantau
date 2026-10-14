-- =====================================================================
-- Marantau (Supabase) - 0024 SAGA 2 · QUEST 6 "BUNGA YANG TAK PERNAH LAYU"
-- Prasyarat: Quest 5 (kompas) selesai + 2 hari game. Saldo bank >= 1.000.000 untuk meminjamkan.
-- Pinjaman ke coco epan (Javasche Bank) ditahan 10 hari game, dikembalikan 2x lipat
-- (bunga 10%/hari sederhana). Pulau baru Gading Island (tersembunyi; terbuka setelah bunga melati),
-- Buku Pancing Legenda, ikan legenda Gading (hanya saat fajar), tiga kopi premium baru.
--
-- Langkah (game.player_quests, quest_id = 'cocoepan'):
--   0  belum mulai (timeOk = 2 hari game sejak Quest 5 selesai)
--   1  Babak 1  Javasche Bank - 'talk'. Lalu 'loan' <jumlah> | 'decline' (boleh kembali kapan saja)
--   2  Babak 2  pinjaman ditahan; Peti Bantuan (10 ruang palka) -> 'deliver' di Kamp Pemulung IKN
--   3           'syahbandar' ok|gagal (Mata Syahbandar, Joungjava) -> 'flower' (bunga melati)
--   4  Babak 3  Gading Island terbuka -> 'stumpy' (felyx)
--   5           'grave' (makam Nyonya Maudy) -> Buku Pancing Legenda
--   6           ikan legenda Gading saat fajar (kait fish_quest_catch, otomatis)
--   7  Babak 4  'mural' (Sandi Pelikan)
--   8  Babak 5  menunggu hari kesepuluh -> 'return': pelunasan 2x lipat ke gold
--   9           'gasing' won|lost (coco epan) -> reveal, Surat untuk Marlya
--  10  Epilog   'surat' di Marie Regal
--  11  selesai
-- Juga: kota yang sudah menerima bantuan (Joungjava, IKN) pulih dari krisis Quest 5 lebih cepat.
-- Aman diulang (migrasi 0018 menyisipkan ulang baris pasar setiap deploy - peran kopi & Gading
-- ditegakkan lagi di bawah).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Konfigurasi (bisa diubah lewat game.config tanpa ubah kode)
--   CocoEpanLoanMax  batas atas pinjaman (bawaan 5.000.000)
-- ---------------------------------------------------------------------
create or replace function game.cb_loan_min() returns bigint language sql immutable as $$ select 1000000::bigint $$;
create or replace function game.cb_loan_max() returns bigint language sql stable as $$ select greatest(game.cb_loan_min(), game.cfg_num('CocoEpanLoanMax', 5000000))::bigint $$;
create or replace function game.cb_hold_days() returns int language sql immutable as $$ select 10 $$;
create or replace function game.cb_ready_days() returns numeric language sql immutable as $$ select 2::numeric $$;
create or replace function game.cb_rate() returns numeric language sql immutable as $$ select 0.10::numeric $$;
create or replace function game.cb_crate_size() returns numeric language sql immutable as $$ select 10::numeric $$;

create or replace function game.cb_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'cocoepan'), 0) $$;

create or replace function game.cb_day_ms() returns bigint
language sql stable as $$ select (greatest(1, game.cfg_num('GameDayLengthRealMinutes', 60)) * 60000)::bigint $$;

-- Kapan Quest 5 selesai (ms) - null bila belum
create or replace function game.cb_kp_done_ms(p_pid uuid) returns bigint
language sql stable as $$
  select (extract(epoch from coalesce(done_at, updated_at, now())) * 1000)::bigint
    from game.player_quests where player_id = p_pid and quest_id = 'kompas' and step >= 8
$$;

-- Pengembalian = pokok + bunga sederhana selama masa tahan (10% x 10 hari = 2x)
create or replace function game.cb_repay_amount(p_loan bigint) returns bigint
language sql immutable as $$
  select round(p_loan * (1 + game.cb_rate() * game.cb_hold_days()))::bigint
$$;

-- Fajar: ujung malam sampai pagi awal (pecahan hari 0.93 .. 0.12; jam HUD "Fajar" = 0 .. 0.07)
create or replace function game.cb_is_dawn() returns boolean
language plpgsql stable as $$
declare start_ms bigint; len_ms numeric; f numeric;
begin
  start_ms := game.cfg_num('WorldStartTimestamp', 0)::bigint;
  len_ms := greatest(60000, game.cfg_num('GameDayLengthRealMinutes', 60) * 60000);
  f := mod(game.now_ms() - start_ms, len_ms::bigint) / len_ms;
  return f >= 0.93 or f < 0.12;
exception when others then return false;
end $$;

-- ---------------------------------------------------------------------
-- Item quest (tidak bisa dijual/dibuang/dititip - type 'quest')
-- ---------------------------------------------------------------------
insert into game.item_catalog(item_id, name, type, effects, value, price, source, sort) values
  ('qi_peti_bantuan', 'Peti Bantuan', 'quest',
   '{"cargoSize": 10, "desc": "Beras dan garam dari gudang Javasche Bank. Untuk Kamp Pemulung di bawah sayap Garuda."}',
   0, null, 'quest', 93),
  ('qi_bunga_melati', 'Seikat Melati Kering', 'quest',
   '{"cargoSize": 0, "desc": "Dibungkus kertas minyak dan diikat benang merah. coco epan tidak sanggup mengantarnya sendiri."}',
   0, null, 'quest', 94),
  ('qi_buku_pancing_maudy', 'Buku Pancing Legenda', 'quest',
   '{"cargoSize": 0, "desc": "Catatan Nyonya Maudy: dua puluh satu ikan legenda di seluruh laut. Halaman pertama: \"Untuk E. Kalau aku tak sempat, selesaikan untukku.\""}',
   0, null, 'quest', 95),
  ('qi_surat_coco', 'Surat Bersegel Lilin', 'quest',
   '{"cargoSize": 0, "desc": "Surat coco epan untuk Ratu Marlya. Surat pertama antara dua darah itu dalam beberapa generasi."}',
   0, null, 'quest', 96)
on conflict (item_id) do update set name = excluded.name, type = excluded.type, effects = excluded.effects,
  value = excluded.value, price = excluded.price, source = excluded.source, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Pulau Gading Island (tersembunyi) - laut timur jauh, lewat Marie Regal
-- ---------------------------------------------------------------------
insert into game.cities(city_id, name, type, repair_cost_rate, image_url, map_x, map_y, sort, hidden)
values ('gading_island', 'Gading Island', 'Gading', 1.2, '', 135, 40, 11, true)
on conflict (city_id) do update set name = excluded.name, type = excluded.type, repair_cost_rate = excluded.repair_cost_rate,
  map_x = excluded.map_x, map_y = excluded.map_y, sort = excluded.sort, hidden = true;

select game.cfg_set('CitiesVersion', '5-gading');

create or replace function game.city_flavor(p_type text) returns text
language sql immutable as $$
  select case p_type
    when 'TradeHub' then 'Pelabuhan sibuk tempat semua rute berpotongan - harga stabil, pilihan barang lengkap.'
    when 'Agricultural' then 'Lumbung wilayah ini - hasil bumi murah, barang mewah harus didatangkan dari luar.'
    when 'Remote' then 'Jauh dari jalur ramai - harga lebih mahal, tapi lebih sedikit persaingan pedagang.'
    when 'Capital' then 'Kota besar yang penuh sukacita - pasar paling lengkap, harga adil dan stabil untuk semua.'
    when 'Outlaw' then 'Sarang penyamun - kapal dagang menuju sini nyaris pasti dicegat bajak laut di tengah jalan. Senjata di sini selalu lebih murah dari kota manapun.'
    when 'FallenCapital' then 'Ibu kota lama yang sudah tumbang - reruntuhan megah dengan banyak yang perlu dibenahi. Papan misi paling ramai di sini, meski bayarannya seadanya.'
    when 'Paradise' then 'Surga para pelaut yang tak ada di peta mana pun - pesta, tarian, dan mata air panas. Kapal yang merapat di sini pulih dengan sendirinya.'
    when 'Regal' then 'Ibu kota Pemerintah Moramora. Menara kaca, lampu yang tak pernah padam, dan mesin yang bekerja tanpa suara. Tak ada satu manusia pun di dermaganya.'
    when 'BlindSpot' then 'Titik di tengah laut tak bertuan yang hanya muncul saat lampu-lampu dinyalakan. Tak ada dermaga - hanya perahu tanpa bendera yang menunggu.'
    when 'Maelstrom' then 'Pusaran air raksasa di bawah langit ungu dan petir biru. Armada Terakhir berjaga di tepinya - kapalmu dirawat di sini, tapi tak ada pasar di tengah badai.'
    when 'Gading' then 'Kepulauan di laut timur yang jauh. Lampion merah di sepanjang dermaga, asap dupa dari klenteng tua, dan pintu toko yang dibuka sebelum matahari. Porselen dan sutranya terkenal, kopinya lebih lagi.'
    else '' end
$$;

-- Pulau terbuka (server) & daftar unlock (klien menyembunyikan kota Hidden yang tak ada di sini)
create or replace function game.city_open(p_pid uuid, p_city text) returns boolean
language sql stable as $$
  select coalesce((select not hidden from game.cities where city_id = p_city), false)
      or (p_city = 'paradiso' and game.gala_step(p_pid) >= 6)
      or (p_city = 'marie_regal' and game.ww_step(p_pid) >= 1)
      or (p_city = 'titik_buta' and game.bx_step(p_pid) = 4 and game.fish_is_night())
      or (p_city = 'pusaran' and game.bx_step(p_pid) between 7 and 15)
      or (p_city = 'gading_island' and game.cb_step(p_pid) >= 4)
$$;

create or replace function game.player_unlocks(p_pid uuid) returns jsonb
language sql stable as $$
  select (case when game.gala_step(p_pid) >= 6 then '["paradiso"]'::jsonb else '[]'::jsonb end)
      || (case when game.ww_step(p_pid) >= 1 then '["marie_regal"]'::jsonb else '[]'::jsonb end)
      || (case when game.bx_step(p_pid) = 4 and game.fish_is_night() then '["titik_buta"]'::jsonb else '[]'::jsonb end)
      || (case when game.bx_step(p_pid) between 7 and 15 then '["pusaran"]'::jsonb else '[]'::jsonb end)
      || (case when game.cb_step(p_pid) >= 4 then '["gading_island"]'::jsonb else '[]'::jsonb end)
$$;

-- ---------------------------------------------------------------------
-- Waktu tempuh: Gading Island TIDAK ikut menentukan rentang jarak dunia (supaya pelayaran
-- antar-pulau lama tidak berubah untuk siapa pun). Jarak di luar rentang (hanya rute ke Gading
-- dari barat) boleh melampaui batas terlama sampai 1,5x: laut terbuka, pelayaran lebih panjang.
-- Isi fungsi lain identik dengan 0003 (voy_travel_seconds); hanya batas frac yang berubah.
-- ---------------------------------------------------------------------
create or replace function game.voy_far_city(p_city text) returns boolean
language sql immutable as $$ select p_city in ('gading_island') $$;

create or replace function game.voy_dist_range(out dmin double precision, out dmax double precision)
language sql stable as $$
  select min(game.voy_map_distance(a.city_id, b.city_id)), max(game.voy_map_distance(a.city_id, b.city_id))
  from game.cities a join game.cities b on a.city_id < b.city_id
  where not game.spot_city(a.city_id) and not game.spot_city(b.city_id)  -- titik laut quest tidak mengubah waktu tempuh
    and not game.voy_far_city(a.city_id) and not game.voy_far_city(b.city_id)  -- laut timur jauh juga tidak
$$;

create or replace function game.voy_travel_seconds(p_distance double precision, p_ship jsonb) returns int
language plpgsql stable as $$
declare lo double precision; hi double precision; r record; frac double precision; base_t double precision;
  base_speed double precision; spd double precision; mult double precision; eff double precision;
  fast double precision; floor_mult constant double precision := 0.24; f double precision; tm double precision;
begin
  if coalesce(p_ship ->> 'Legend', '') = 'pearl' then
    return greatest(5, game.cfg_num('TravelLegendSeconds', 15))::int;
  end if;
  lo := greatest(10, game.cfg_num('TravelMinSeconds', 120));
  hi := greatest(lo, game.cfg_num('TravelMaxSeconds', 240));
  fast := least(lo, greatest(5, game.cfg_num('TravelFastestSeconds', 25)));
  select * into r from game.voy_dist_range();
  -- 0024: batas 1,5 (bukan 1) - hanya rute laut timur jauh yang melampaui dmax
  frac := case when r.dmax > r.dmin then least(1.5, greatest(0, (p_distance - r.dmin) / (r.dmax - r.dmin))) else 0 end;
  base_t := lo + (hi - lo) * frac;
  base_speed := greatest(1, game.cfg_num('BaselineShipSpeed', 50));
  spd := coalesce(nullif(game.voy_num(p_ship -> 'Speed'), 0), base_speed);
  mult := coalesce(nullif(game.voy_num(p_ship -> 'SpeedMultiplier'), 0), 1);
  mult := least(1, greatest(floor_mult, mult));
  eff := least(1, greatest(floor_mult, floor_mult + (mult - floor_mult) * base_speed / spd));
  f := fast / lo + (1 - fast / lo) * (eff - floor_mult) / (1 - floor_mult);
  tm := coalesce(nullif(game.voy_num(p_ship -> 'TravelMul'), 0), 1);
  if tm < 1 then f := greatest(fast / lo, f * tm); end if;
  return greatest(1, round(base_t * f))::int;
end $$;

-- ---------------------------------------------------------------------
-- Kopi Gading Island: tiga kopi PREMIUM (stok kecil, hanya bisa dibeli di pulau produsen,
-- dibeli mahal di kota konsumen). Premium juga tidak dipakai papan misi (lihat 0004).
-- ---------------------------------------------------------------------
insert into game.commodities(id, name, flavor, sort, grp, tier, base, size, spread, elast, ref, active) values
  ('kopi_bourbon_chiroso', 'Bourbon Chiroso', 'Kopi paling langka dari lereng Gading Island. Dipetik satu per satu; stoknya selalu sedikit.', 41, 'minuman', 'premium', 2600, 0.25, 0.225, 0.6, 6,  true),
  ('kopi_flores_bajawa',   'Flores Bajawa',   'Harum rempah dan cokelat gelap. Para juru seduh menyebutnya kopi yang sabar.',              42, 'minuman', 'premium', 1600, 0.25, 0.225, 0.6, 10, true),
  ('kopi_sumatera_gayo',   'Sumatera Gayo',   'Kopi paling umum dari ketiganya. Pahit yang jujur, manis di ingatan.',                     43, 'minuman', 'premium', 1100, 0.25, 0.225, 0.6, 14, true)
on conflict (id) do update set name = excluded.name, flavor = excluded.flavor, sort = excluded.sort, grp = excluded.grp,
  tier = excluded.tier, base = excluded.base, size = excluded.size, spread = excluded.spread, elast = excluded.elast,
  ref = excluded.ref, active = true;

-- Peran pasar Gading Island & kopi. Ditulis ulang SETIAP deploy (0018 menyisipkan ulang semua
-- baris pasar dengan peran bawaan sebelum migrasi ini berjalan).
create or replace function game.cb_market_role(p_city text, p_comm text) returns text
language sql immutable as $$
  select case
    when p_comm like 'kopi\_%' escape '\' and p_comm <> 'kopi' then
      case when p_city = 'gading_island' then 'produce'
           when p_city in ('sunda_empire', 'skitraw', 'paradiso', 'marie_regal') then 'consume'
           else 'neutral' end
    when p_city = 'gading_island' then
      case when p_comm in ('porselen', 'silk', 'kopi') then 'produce'
           when p_comm in ('beras', 'sugar', 'lada', 'kayu_jati') then 'consume'
           else 'neutral' end
    else null end
$$;

insert into game.market(city_id, commodity_id, base_price, current_price, role)
select ci.city_id, co.id, co.base, co.base, coalesce(game.cb_market_role(ci.city_id, co.id), 'neutral')
  from game.cities ci cross join game.commodities co
 where co.active and not game.spot_city(ci.city_id)
   and (ci.city_id = 'gading_island' or (co.id like 'kopi\_%' escape '\' and co.id <> 'kopi'))
on conflict (city_id, commodity_id) do update set base_price = excluded.base_price, role = excluded.role;

-- ---------------------------------------------------------------------
-- Ikan legenda Gading Island: tidak masuk Buku Ikan (14 ikan, syarat Quest 2 tetap utuh).
-- Hanya naik ke kail saat fajar, di Gading Island, setelah buku Maudy diterima (langkah 6).
-- ---------------------------------------------------------------------
alter table game.mp_fish_types add column if not exists book text not null default 'ikan';  -- ikan | legenda

insert into game.mp_fish_types(id, name, v, w, zone, sp, rarity, kg_min, kg_max, stam, pow, agi, depth, tod, cities, kind, hint, sort, book)
values ('naga_fajar', 'Ikan Naga Fajar', 1100, 1, 0.08, 2.5, 7, 4.0, 18.0, 9.0, 1.0, 0.85, 2, 'any',
        array['gading_island'], 'fish', 'Sisiknya keemasan seperti langit sebelum matahari. Tercatat di Buku Pancing Maudy dengan tanda bintang.', 99, 'legenda')
on conflict (id) do update set name = excluded.name, v = excluded.v, w = excluded.w, zone = excluded.zone,
  sp = excluded.sp, rarity = excluded.rarity, kg_min = excluded.kg_min, kg_max = excluded.kg_max, stam = excluded.stam,
  pow = excluded.pow, agi = excluded.agi, depth = excluded.depth, tod = excluded.tod, cities = excluded.cities,
  kind = excluded.kind, hint = excluded.hint, sort = excluded.sort, book = excluded.book;
-- hapus sisa baris uji dari versi awal (bila ada)
delete from game.mp_fish_book where fish_id = 'legenda_gading';
delete from game.mp_fish_types where id = 'legenda_gading';

-- Buku Ikan hanya menghitung ikan biasa (book = 'ikan')
create or replace function game.tg_book(p_pid uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'found', (select count(*)::int from game.mp_fish_book b join game.mp_fish_types t on t.id = b.fish_id where b.player_id = p_pid and t.book = 'ikan'),
    'total', (select count(*)::int from game.mp_fish_types where book = 'ikan'))
$$;

create or replace function public.api_mgFishInfo(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(); r game.mp_fish;
begin
  r := game.fish_row(v_me.player_id);
  return jsonb_build_object('left', game.fish_left(v_me.player_id), 'max', game.fish_qmax(),
    'nextMs', game.fish_next_ms(v_me.player_id), 'regenMs', game.fish_qsec(), 'rod', r.rod, 'rods', game.fish_rods(),
    'baits', game.fish_baits(), 'night', game.fish_is_night(), 'cityId', game.current_city(v_me.player_id),
    'dawn', game.cb_is_dawn(),
    'found', (select count(*) from game.mp_fish_book b join game.mp_fish_types t on t.id = b.fish_id where b.player_id = v_me.player_id and t.book = 'ikan'),
    'total', (select count(*) from game.mp_fish_types where book = 'ikan'),
    'cooldownMs', greatest(0, coalesce(r.cooldown_until, 0) - game.now_ms()));
end $$;
select game.expose('api_mgfishinfo');

create or replace function public.api_mgFishBook(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me();
begin
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', t.id, 'rarity', t.rarity, 'kind', t.kind, 'depth', t.depth, 'night', t.tod = 'night',
      'cities', coalesce(to_jsonb(t.cities), 'null'::jsonb), 'hint', t.hint,
      'found', b.player_id is not null,
      'name', case when b.player_id is not null then t.name else null end,
      'n', coalesce(b.n, 0), 'bestKg', b.best_kg, 'bestGold', b.best_gold,
      'kgMax', case when b.player_id is not null then t.kg_max else null end,
      'record', (select jsonb_build_object('kg', r.best_kg, 'n', p.character_name, 'me', r.player_id = v_me.player_id)
                 from game.mp_fish_book r join game.players p on p.player_id = r.player_id
                 where r.fish_id = t.id and t.kind = 'fish' order by r.best_kg desc, r.best_at limit 1)
    ) order by t.sort)
    from game.mp_fish_types t
    left join game.mp_fish_book b on b.fish_id = t.id and b.player_id = v_me.player_id
   where t.book = 'ikan'), '[]'::jsonb);
end $$;
select game.expose('api_mgfishbook');

-- Kait memancing: ikan legenda dulu, lalu Peti Karam Bjorneo (0022)
create or replace function game.fish_quest_weight(p_pid uuid, p_fish text, p_city text) returns numeric
language plpgsql stable as $$
begin
  if p_fish = 'naga_fajar' then
    if p_city = 'gading_island' and game.cb_step(p_pid) = 6 and game.cb_is_dawn() then return 40; end if;
    return 0;  -- tak pernah muncul di luar quest
  end if;
  return game.bx_fish_quest_weight(p_pid, p_fish, p_city);
end $$;

create or replace function game.fish_quest_catch(p_pid uuid, p_fish text) returns jsonb
language plpgsql as $$
declare v_kg numeric;
begin
  if p_fish = 'naga_fajar' then
    -- catatan disimpan di Buku Pancing Legenda (data quest), bukan Buku Ikan
    select best_kg into v_kg from game.mp_fish_book where player_id = p_pid and fish_id = 'naga_fajar';
    delete from game.mp_fish_book where player_id = p_pid and fish_id = 'naga_fajar';
    if game.cb_step(p_pid) = 6 and game.current_city(p_pid) = 'gading_island' then
      update game.player_quests set step = 7, data = data || jsonb_build_object('legend', true, 'legendKg', v_kg), updated_at = now()
       where player_id = p_pid and quest_id = 'cocoepan';
      perform game.log(p_pid, 'Ikan Naga Fajar tertangkap saat fajar di Gading Island. Halaman pertama Buku Pancing Legenda kini terisi.');
      return jsonb_build_object('itemId', 'qi_buku_pancing_maudy', 'name', 'Buku Pancing Legenda', 'quest', 'cocoepan',
        'message', 'Sisiknya berkilau keemasan seperti langit sebelum matahari. Di Buku Pancing Legenda, entri pertama bertanda bintang kini bisa dicoret.');
    end if;
    return null;
  end if;
  return game.bx_fish_quest_catch(p_pid, p_fish);
end $$;

-- ---------------------------------------------------------------------
-- Krisis pasar Quest 5: kota yang sudah menerima bantuan bank (Joungjava, IKN) pulih lebih cepat
-- (isi selain pengecualian identik dengan 0023)
-- ---------------------------------------------------------------------
create or replace function game.quest_price_mul(p_pid uuid, p_city text, p_comm text) returns double precision
language plpgsql stable as $$
declare lvl double precision; v_role text;
begin
  lvl := game.kp_crisis_level(p_pid);
  if lvl <= 0 then return 1; end if;
  if p_city in ('joungjava', 'ikn') and game.cb_step(p_pid) >= 3 then return 1; end if;
  select role into v_role from game.market where city_id = p_city and commodity_id = p_comm;
  return 1 + lvl * case coalesce(v_role, 'neutral')
    when 'produce' then -0.15
    when 'consume' then 0.25
    else 0.15 end;
end $$;

-- ---------------------------------------------------------------------
-- Status (kunci 'cocoepan' di api_getGameState)
-- ---------------------------------------------------------------------
create or replace function game.cb_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare q game.player_quests; v_kp bigint := game.cb_kp_done_ms(p_pid); v_step int; v_ready bigint;
  v_bank bigint; v_loan bigint; v_loan_day int; v_left int; v_ret_at bigint;
begin
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'cocoepan';
  if not found and v_kp is null then return null; end if;
  v_step := coalesce(q.step, 0);
  v_ready := coalesce(v_kp, 0) + (game.cb_ready_days() * game.cb_day_ms())::bigint;
  select coalesce(bank_balance, 0) into v_bank from game.players where player_id = p_pid;
  v_loan := coalesce((q.data ->> 'loan')::bigint, 0);
  v_loan_day := (q.data ->> 'loanDay')::int;
  if v_loan_day is not null then
    v_left := greatest(0, v_loan_day + game.cb_hold_days() - game.game_day());
    v_ret_at := game.cfg_num('WorldStartTimestamp', 0)::bigint + (v_loan_day + game.cb_hold_days())::bigint * game.cb_day_ms();
  end if;
  return jsonb_build_object(
    'step', v_step,
    'eligible', v_kp is not null,
    'timeOk', v_kp is not null and game.now_ms() >= v_ready,
    'readyInMs', case when v_step = 0 then greatest(0, v_ready - game.now_ms()) end,
    'bankNeed', game.cb_loan_min(),
    'loanMax', game.cb_loan_max(),
    'bankBalance', v_bank,
    'bankOk', v_bank >= game.cb_loan_min(),
    'declined', coalesce((q.data ->> 'declined')::boolean, false),
    'loan', case when v_loan > 0 then v_loan end,
    'repay', case when v_loan > 0 then game.cb_repay_amount(v_loan) end,
    'repaid', (q.data ->> 'repaid')::bigint,
    'holdDaysLeft', v_left,
    'returnInMs', case when v_ret_at is not null and v_step <= 8 then greatest(0, v_ret_at - game.now_ms()) end,
    'repayReady', v_step = 8 and coalesce(v_left, 1) = 0,
    'syah', coalesce((q.data ->> 'syah')::boolean, false),
    'gasing', q.data ->> 'gasing',
    'legendKg', (q.data ->> 'legendKg')::numeric,
    'hasCrate', game.item_qty(p_pid, 'qi_peti_bantuan') > 0,
    'hasFlower', game.item_qty(p_pid, 'qi_bunga_melati') > 0,
    'hasLetter', game.item_qty(p_pid, 'qi_surat_coco') > 0,
    'compass', game.item_qty(p_pid, 'qi_kompas_tedsky') > 0,
    'dawn', game.cb_is_dawn(),
    'done', v_step >= 11);
end $$;

-- ---------------------------------------------------------------------
-- Aksi quest. a = [action, arg]
--   status | talk | loan <jumlah> | decline | deliver | syahbandar ok|gagal | flower | stumpy
--   | grave | mural | return | gasing won|lost | surat
-- ---------------------------------------------------------------------
create or replace function game.cb_set(p_pid uuid, p_step int, p_data jsonb) returns void
language sql as $$
  update game.player_quests set step = p_step, data = data || coalesce(p_data, '{}'::jsonb), updated_at = now(),
    done_at = case when p_step >= 11 then now() else done_at end
   where player_id = p_pid and quest_id = 'cocoepan'
$$;

create or replace function public.api_cocoEpan(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status'); v_arg text := lower(btrim(coalesce(game.arg(a, 1), '')));
  q game.player_quests; v_step int; v_city text := game.current_city(v_pid); st jsonb; bk jsonb;
  v_amt bigint; v_bank bigint; v_repay bigint;
begin
  st := game.cb_state(v_pid);
  if v_act = 'status' then return jsonb_build_object('cocoepan', st); end if;
  if st is null or not coalesce((st ->> 'eligible')::boolean, false) then
    raise exception 'Pintu ruangan bankir itu masih tertutup untukmu, Kapten.';
  end if;
  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;

  select * into q from game.player_quests where player_id = v_pid and quest_id = 'cocoepan' for update;
  v_step := coalesce(q.step, 0);

  -- Babak 1: Javasche Bank
  if v_act = 'talk' then
    if v_city <> 'joungjava' then raise exception 'coco epan menunggu di Javasche Bank, Joungjava.'; end if;
    if v_step = 0 then
      if not coalesce((st ->> 'timeOk')::boolean, false) then raise exception 'coco epan sedang tidak menerima tamu, Kapten.'; end if;
      insert into game.player_quests(player_id, quest_id, step, data)
      values (v_pid, 'cocoepan', 1, '{}'::jsonb)
      on conflict (player_id, quest_id) do update set step = 1, data = '{}'::jsonb, started_at = now(), updated_at = now();
      perform game.log(v_pid, 'Pak Tua Karto: "Ada orang tua bertopi bulat yang menanyakan namamu." Javasche Bank sepi; brankasnya setengah kosong.');
    end if;
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;
  if v_step = 0 then raise exception 'coco epan belum memanggilmu.'; end if;

  if v_act = 'decline' then
    if v_step <> 1 then raise exception 'Tidak ada pinjaman yang sedang ditawarkan.'; end if;
    if v_city <> 'joungjava' then raise exception 'coco epan menunggu di Javasche Bank, Joungjava.'; end if;
    perform game.cb_set(v_pid, 1, jsonb_build_object('declined', true));
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  if v_act = 'loan' then
    if v_step <> 1 then raise exception 'Pinjaman itu sudah kau berikan, Kapten.'; end if;
    if v_city <> 'joungjava' then raise exception 'coco epan menunggu di Javasche Bank, Joungjava.'; end if;
    v_amt := game.arg_int(a, 1);
    if v_amt is null or v_amt < game.cb_loan_min() then raise exception 'Pinjaman minimal 1.000.000 gold, Kapten.'; end if;
    if v_amt > game.cb_loan_max() then
      raise exception 'coco epan menggeleng. "Saya meminjam secukupnya, Kapten. Paling banyak % gold."', to_char(game.cb_loan_max(), 'FM999G999G999G999');
    end if;
    bk := game.bank_state(v_pid);  -- hitung bunga bank yang tertunda dulu
    v_bank := (bk ->> 'bankBalance')::bigint;
    if v_amt > v_bank then raise exception 'Saldo Bank tidak cukup untuk pinjaman itu.'; end if;
    if game.item_qty(v_pid, 'qi_peti_bantuan') < 1 and game.cargo_free(v_pid) < game.cb_crate_size() then
      raise exception 'Palkamu penuh. Kosongkan 10 ruang untuk Peti Bantuan, Kapten.';
    end if;
    update game.players set bank_balance = v_bank - v_amt where player_id = v_pid;
    if game.item_qty(v_pid, 'qi_peti_bantuan') < 1 then perform game.item_adjust(v_pid, 'qi_peti_bantuan', 1); end if;
    perform game.cb_set(v_pid, 2, jsonb_build_object('loan', v_amt, 'loanDay', game.game_day(), 'declined', false));
    perform game.log(v_pid, 'Meminjamkan ' || v_amt || ' gold kepada coco epan dari saldo Bank. Ditahan 10 hari game, kembali 2x lipat.');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid), 'bank', game.bank_state(v_pid));
  end if;

  -- Babak 2: Peti Bantuan ke Kamp Pemulung IKN, Mata Syahbandar
  if v_act = 'deliver' then
    if v_step <> 2 then raise exception 'Peti Bantuan belum waktunya dibagikan.'; end if;
    if v_city <> 'ikn' then raise exception 'Kamp Pemulung ada di bawah sayap Garuda, IKN.'; end if;
    if game.item_qty(v_pid, 'qi_peti_bantuan') < 1 then raise exception 'Peti Bantuan tidak ada di palkamu.'; end if;
    perform game.item_adjust(v_pid, 'qi_peti_bantuan', -1);
    perform game.cb_set(v_pid, 3, null);
    perform game.log(v_pid, 'Peti Bantuan dibagikan di Kamp Pemulung IKN. Seorang anak bertanya: "Kenapa orang kaya itu membagi beras?"');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  if v_act = 'syahbandar' then
    if v_step <> 3 then raise exception 'Syahbandar sedang tidak butuh bantuanmu.'; end if;
    if v_city <> 'joungjava' then raise exception 'Syahbandar Joungjava menunggumu di menara.'; end if;
    if v_arg not in ('ok', 'gagal') then raise exception 'Hasil pemeriksaan tidak dikenal.'; end if;
    if v_arg = 'ok' and not coalesce((q.data ->> 'syah')::boolean, false) then
      perform game.cb_set(v_pid, 3, jsonb_build_object('syah', true));
      perform game.log(v_pid, 'Kapal penimbun yang menyamar sebagai kapal bantuan Javasche Bank tertangkap di Joungjava.');
    end if;
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  -- Babak 3: bunga melati -> Gading Island
  if v_act = 'flower' then
    if v_step <> 3 or not coalesce((q.data ->> 'syah')::boolean, false) then raise exception 'coco epan belum punya titipan untukmu.'; end if;
    if v_city <> 'joungjava' then raise exception 'coco epan menunggu di Javasche Bank, Joungjava.'; end if;
    if game.item_qty(v_pid, 'qi_bunga_melati') < 1 then perform game.item_adjust(v_pid, 'qi_bunga_melati', 1); end if;
    perform game.cb_set(v_pid, 4, null);
    perform game.log(v_pid, 'coco epan menitipkan seikat melati kering untuk sebuah pulau di timur, jauh melewati menara kaca. Peta duniamu meluas.');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid), 'unlocks', game.player_unlocks(v_pid),
      'cities', game.cities_json(), 'citiesVersion', game.cities_version());
  end if;

  if v_act = 'stumpy' then
    if v_step <> 4 then raise exception 'Kedai itu masih tutup.'; end if;
    if v_city <> 'gading_island' then raise exception 'Kedai Stumpy ada di Gading Island.'; end if;
    perform game.cb_set(v_pid, 5, null);
    perform game.log(v_pid, 'felyx menyeduh kopi tanpa gula di kedai Stumpy dan bercerita tentang lelaki bermonokel dan istrinya.');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  if v_act = 'grave' then
    if v_step <> 5 then raise exception 'Bukit di belakang klenteng itu sunyi.'; end if;
    if v_city <> 'gading_island' then raise exception 'Makam itu ada di bukit belakang klenteng, Gading Island.'; end if;
    if game.item_qty(v_pid, 'qi_bunga_melati') < 1 then raise exception 'Kau belum membawa bunga, Kapten.'; end if;
    perform game.item_adjust(v_pid, 'qi_bunga_melati', -1);
    if game.item_qty(v_pid, 'qi_buku_pancing_maudy') < 1 then perform game.item_adjust(v_pid, 'qi_buku_pancing_maudy', 1); end if;
    perform game.cb_set(v_pid, 6, null);
    perform game.log(v_pid, 'Melati diletakkan di makam Nyonya Maudy. felyx menyerahkan Buku Pancing Legenda.');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid),
      'item', jsonb_build_object('itemId', 'qi_buku_pancing_maudy', 'name', 'Buku Pancing Legenda'));
  end if;

  -- Babak 4: mural dua nakhoda (Sandi Pelikan dimainkan di klien)
  if v_act = 'mural' then
    if v_step <> 7 then raise exception 'Pintu gudang di balik Stumpy masih terkunci.'; end if;
    if v_city <> 'gading_island' then raise exception 'Gudang di balik Stumpy ada di Gading Island.'; end if;
    perform game.cb_set(v_pid, 8, null);
    perform game.log(v_pid, 'Sandi Pelikan terbaca: dua pendiri Moramora, armada Kumis Hitam, dan satu panel yang sengaja dikerok.');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  -- Babak 5: hari kesepuluh
  if v_act = 'return' then
    if v_step <> 8 then raise exception 'coco epan belum memanggilmu kembali.'; end if;
    if v_city <> 'joungjava' then raise exception 'coco epan menunggu di Javasche Bank, Joungjava.'; end if;
    if coalesce((st ->> 'holdDaysLeft')::int, 1) > 0 then
      raise exception 'Belum waktunya, Kapten. Saya menepati janji, bukan mempercepatnya.';
    end if;
    v_repay := game.cb_repay_amount(coalesce((q.data ->> 'loan')::bigint, 0));
    update game.players set gold = gold + v_repay where player_id = v_pid;
    perform game.cb_set(v_pid, 9, jsonb_build_object('repaid', v_repay));
    perform game.log(v_pid, 'coco epan melunasi pinjaman 2x lipat: ' || v_repay || ' gold. "Utang emas memang yang paling mudah dibayar."');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid), 'paid', v_repay,
      'newGold', (select gold from game.players where player_id = v_pid));
  end if;

  if v_act = 'gasing' then
    if v_step <> 9 then raise exception 'coco epan belum mengeluarkan gasing tuanya.'; end if;
    if v_city <> 'joungjava' then raise exception 'coco epan menunggu di Javasche Bank, Joungjava.'; end if;
    if v_arg not in ('won', 'lost') then raise exception 'Hasil adu gasing tidak dikenal.'; end if;
    if game.item_qty(v_pid, 'qi_surat_coco') < 1 then perform game.item_adjust(v_pid, 'qi_surat_coco', 1); end if;
    perform game.cb_set(v_pid, 10, jsonb_build_object('gasing', v_arg));
    perform game.log(v_pid, 'Adu gasing melawan coco epan: ' || case when v_arg = 'won' then 'menang' else 'kalah' end ||
      '. Ia bercerita tentang Moramora, lalu menitipkan surat bersegel lilin untuk Ratu Marlya.');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  -- Epilog: surat untuk Marlya
  if v_act = 'surat' then
    if v_step <> 10 then raise exception 'Tidak ada surat yang perlu diantar.'; end if;
    if v_city <> 'marie_regal' then raise exception 'Ratu Marlya ada di Istana Hening, Marie Regal.'; end if;
    if game.item_qty(v_pid, 'qi_surat_coco') > 0 then perform game.item_adjust(v_pid, 'qi_surat_coco', -1); end if;
    perform game.cb_set(v_pid, 11, null);
    perform game.log(v_pid, 'Surat coco epan sampai ke tangan Marlya. Ia melipatnya tanpa sepatah kata. Malam itu, sebuah lampu lama di Istana Hening menyala lagi.');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_cocoepan');

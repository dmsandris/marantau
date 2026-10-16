-- =====================================================================
-- Marantau (Supabase) - 0027 SAGA 2 · QUEST 7 "MALAM TIGA TANDA SILANG"
-- Prasyarat: Quest 6 (Bunga yang Tak Pernah Layu) selesai. Dimulai pada PELAYARAN KETIGA
-- setelah Quest 6 selesai (ke tujuan mana pun): sinematik "Langit Hitam".
-- Tiga pulau baru (terbuka permanen untuk pemain ini, berurutan lewat Peta Pengasingan):
--   Otoland (110,28) · Pulau em pe'er de pe'er (118,62) · FreeYork (150,75)
--
-- Langkah (game.player_quests, quest_id = 'tigasilang'):
--   0  menunggu: data.sails = jumlah pelayaran sejak Quest 6 selesai (ke-3 memicu langkah 1)
--   1  Babak 0  Langit Hitam sudah terjadi -> 'vault' di Joungjava
--   2  Babak 1  Brankas terbuka: 'jejak' (Olah Jejak), 'ask' diri|tedsky, lalu 'map'
--               -> Peta Pengasingan, Otoland terbuka
--   3  Babak 2  Otoland: 'upayy' bahagia|sendiri, 'gasing' won|lost (Joran & Kotak Alat Jam),
--               'sandi' (Sandi Pelikan, tabung surat gagak) -> em pe'er de pe'er terbuka
--   4  Babak 3  em pe'er de pe'er: 'ocid' (undangan), MALAM: 'pantun' ok|gagal, 'mata' ok|gagal,
--               'garlyena' bongkar|simpan -> Kunci Jam Agung, FreeYork terbuka
--   5  Babak 4  FreeYork: 'tassyaaa', 'jejak' (Olah Jejak bengkel),
--               'tempa' padam|biarkan [beras|garam] -> Palu Kecil Tempa
--   6  Babak 5  Paradiso (Kasino Mutiara): 'andry', 'dadu' besar|kecil, 'gasing' won|lost
--               -> Surat Bersegel Lilin Hitam. Titik Buta terbuka saat malam.
--   7  Babak 6  Titik Buta (malam): 'titikbuta' (pertempuran tak bisa dimenangkan dimainkan
--               di klien) -> kapal terdampar di TooGood, Pemukul Genderang Andry
--   8  Babak 7  TooGood: 'pemakaman' (Tari Genderang duka) -> Surat Wasiat Andry, 50.000 gold
--   9  Babak 8  TooGood: 'jarum' (coco epan & kompas). Pemburu Sayap Patah mulai mencegat.
--  10           Gading Island: 'cut' (Kunci Dua Jarum) -> Kompas Dua Jarum, pemburu berhenti
--  11           Joungjava: 'tutup' -> Kunci Jam Agung & Kotak Alat Jam diserahkan ke coco epan
--  12  selesai
-- Pilihan: upayy_answer, garlyena, tempa (+ truth dari Quest 5) memengaruhi pemburu & epilog Q8.
-- Pasar dunia TIDAK dikacaukan. Aman diulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Konstanta & helper
-- ---------------------------------------------------------------------
create or replace function game.ts_reward() returns bigint language sql immutable as $$ select 50000::bigint $$;
create or replace function game.ts_hunter_gold() returns bigint language sql immutable as $$ select 4000::bigint $$;
create or replace function game.ts_sails_need() returns int language sql immutable as $$ select 3 $$;

create or replace function game.ts_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'tigasilang'), 0) $$;

create or replace function game.ts_data(p_pid uuid) returns jsonb
language sql stable as $$ select coalesce((select data from game.player_quests where player_id = p_pid and quest_id = 'tigasilang'), '{}'::jsonb) $$;

-- Jawaban kepada Tedsky di Quest 5 (jujur|bohong); null bila tidak ada
create or replace function game.ts_truth(p_pid uuid) returns text
language sql stable as $$ select data ->> 'truth' from game.player_quests where player_id = p_pid and quest_id = 'kompas' $$;

-- ---------------------------------------------------------------------
-- Item quest
-- ---------------------------------------------------------------------
insert into game.item_catalog(item_id, name, type, effects, value, price, source, sort) values
  ('qi_peta_pengasingan', 'Peta Pengasingan', 'quest',
   '{"cargoSize": 0, "desc": "Peta tangan lusuh milik coco epan. Tiga pulau dilingkari tinta pudar. Di pojoknya, tulisan Nansy: \"Jalan pulang kita, kalau suatu hari kau ingin pulang.\""}',
   0, null, 'quest', 97),
  ('qi_joran_nansy', 'Joran Kecil Miss Nansy', 'quest',
   '{"cargoSize": 0, "desc": "Joran bambu kecil yang dulu dipakai Nansy belajar memancing saat fajar di Otoland. Ny. Upayy menyimpannya bertahun-tahun."}',
   0, null, 'quest', 98),
  ('qi_kotak_alat_jam', 'Kotak Alat Jam Coco', 'quest',
   '{"cargoSize": 0, "desc": "Kotak kayu kecil: obeng mungil, kaca pembesar, tali kulit jam. Ditinggalkan coco epan di Otoland. \"Di kota besar saya tidak akan butuh ini lagi.\""}',
   0, null, 'quest', 99),
  ('qi_kunci_jam_agung', 'Kunci Jam Agung', 'quest',
   '{"cargoSize": 0, "desc": "Kunci kuningan berukir mahkota dari Paman Ocid. \"Biar Baginda sendiri yang memutuskan kapan jam itu berjalan lagi.\""}',
   0, null, 'quest', 100),
  ('qi_palu_tempa', 'Palu Kecil Tempa', 'quest',
   '{"cargoSize": 0, "desc": "Palu pandai besi sebesar telapak tangan dari meja Tassyaaa di FreeYork. Gagangnya hitam oleh arang."}',
   0, null, 'quest', 101),
  ('qi_surat_hitam', 'Surat Bersegel Lilin Hitam', 'quest',
   '{"cargoSize": 0, "desc": "Dari Andry Ivankov. \"Buka kalau aku tidak datang. Kalau aku datang, kembalikan.\""}',
   0, null, 'quest', 102),
  ('qi_wasiat_andry', 'Surat Wasiat Andry', 'quest',
   '{"cargoSize": 0, "desc": "\"Kalau salah satu dari kita jatuh, dua yang lain datang. Sekarang tinggal kau yang bisa datang. - A.\""}',
   0, null, 'quest', 103),
  ('qi_pemukul_andry', 'Pemukul Genderang Andry', 'quest',
   '{"cargoSize": 0, "desc": "Mengapung ke kapalmu di Titik Buta. Kayunya masih hangat. +5 Combat (sudah ditambahkan), dan genderang terasa lebih ringan di tanganmu."}',
   0, null, 'quest', 104),
  ('qi_kompas_dua_jarum', 'Kompas Dua Jarum', 'quest',
   '{"cargoSize": 0, "desc": "Kompas Tedsky tanpa jarum ketiga. Dua jarum yang tersisa, emas dan perak, menunjuk satu arah: timur jauh, menembus kabut \"Belum Dipetakan\"."}',
   0, null, 'quest', 105)
on conflict (item_id) do update set name = excluded.name, type = excluded.type, effects = excluded.effects,
  value = excluded.value, price = excluded.price, source = excluded.source, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Tiga pulau baru (tersembunyi; terbuka per pemain lewat quest)
-- ---------------------------------------------------------------------
insert into game.cities(city_id, name, type, repair_cost_rate, image_url, map_x, map_y, sort, hidden) values
  ('otoland',       'Otoland',                 'Kincir', 1.1, '', 110, 28, 12, true),
  ('empeer_depeer', 'Pulau em pe''er de pe''er', 'Dewan',  1.3, '', 118, 62, 13, true),
  ('freeyork',      'FreeYork',                'Tempa',  0.9, '', 150, 75, 14, true)
on conflict (city_id) do update set name = excluded.name, type = excluded.type, repair_cost_rate = excluded.repair_cost_rate,
  map_x = excluded.map_x, map_y = excluded.map_y, sort = excluded.sort, hidden = true;

select game.cfg_set('CitiesVersion', '6-tigasilang');

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
    when 'Kincir' then 'Pulau datar yang tak pernah sepi angin. Puluhan kincir kayu memompa ladang garam dan menjemur biji kopi. Garam, ikan asin, dan kopinya murah; kain dan perkakas selalu dicari.'
    when 'Dewan' then 'Pulau para bangsawan pengungsi. Gedung Kubah di ujung tangga panjang, karpet merah yang menipis, dan izin bersandar yang harus dicap tujuh kali. Sutra dan porselennya halus; gula, arak, dan rempah selalu kurang.'
    when 'Tempa' then 'Tanah pandai besi. Tambang batu bara di lereng, cerobong yang menyala siang-malam, dan Dok Legenda tempat Black Pearl dulu ditempa. Besi, perkakas, dan senjata murah; beras dan garam dibeli mahal.'
    else '' end
$$;

-- Pulau terbuka (server) & daftar unlock (klien)
create or replace function game.city_open(p_pid uuid, p_city text) returns boolean
language sql stable as $$
  select coalesce((select not hidden from game.cities where city_id = p_city), false)
      or (p_city = 'paradiso' and game.gala_step(p_pid) >= 6)
      or (p_city = 'marie_regal' and game.ww_step(p_pid) >= 1)
      or (p_city = 'titik_buta' and game.fish_is_night() and (game.bx_step(p_pid) = 4 or game.ts_step(p_pid) = 7))
      or (p_city = 'pusaran' and game.bx_step(p_pid) between 7 and 15)
      or (p_city = 'gading_island' and game.cb_step(p_pid) >= 4)
      or (p_city = 'otoland' and game.ts_step(p_pid) >= 3)
      or (p_city = 'empeer_depeer' and game.ts_step(p_pid) >= 4)
      or (p_city = 'freeyork' and game.ts_step(p_pid) >= 5)
$$;

create or replace function game.player_unlocks(p_pid uuid) returns jsonb
language sql stable as $$
  select (case when game.gala_step(p_pid) >= 6 then '["paradiso"]'::jsonb else '[]'::jsonb end)
      || (case when game.ww_step(p_pid) >= 1 then '["marie_regal"]'::jsonb else '[]'::jsonb end)
      || (case when game.fish_is_night() and (game.bx_step(p_pid) = 4 or game.ts_step(p_pid) = 7) then '["titik_buta"]'::jsonb else '[]'::jsonb end)
      || (case when game.bx_step(p_pid) between 7 and 15 then '["pusaran"]'::jsonb else '[]'::jsonb end)
      || (case when game.cb_step(p_pid) >= 4 then '["gading_island"]'::jsonb else '[]'::jsonb end)
      || (case when game.ts_step(p_pid) >= 3 then '["otoland"]'::jsonb else '[]'::jsonb end)
      || (case when game.ts_step(p_pid) >= 4 then '["empeer_depeer"]'::jsonb else '[]'::jsonb end)
      || (case when game.ts_step(p_pid) >= 5 then '["freeyork"]'::jsonb else '[]'::jsonb end)
$$;

-- Laut timur jauh: tidak ikut rentang jarak dunia (waktu tempuh antar-pulau lama tetap)
create or replace function game.voy_far_city(p_city text) returns boolean
language sql immutable as $$ select p_city in ('gading_island', 'otoland', 'empeer_depeer', 'freeyork') $$;

-- ---------------------------------------------------------------------
-- Peran pasar tiga pulau baru. Ditulis ulang SETIAP deploy (0018 menyisipkan ulang semua
-- baris pasar dengan peran bawaan sebelum migrasi ini berjalan). Kopi premium Gading: netral.
-- ---------------------------------------------------------------------
create or replace function game.ts_market_role(p_city text, p_comm text) returns text
language sql immutable as $$
  select case p_city
    when 'otoland' then
      case when p_comm in ('garam', 'ikan_asin', 'kopi') then 'produce'
           when p_comm in ('batik', 'tools', 'beras') then 'consume' else 'neutral' end
    when 'empeer_depeer' then
      case when p_comm in ('silk', 'porselen') then 'produce'
           when p_comm in ('sugar', 'rum', 'cengkeh', 'pala') then 'consume' else 'neutral' end
    when 'freeyork' then
      case when p_comm in ('besi', 'tools', 'arms') then 'produce'
           when p_comm in ('beras', 'garam', 'kayu_jati') then 'consume' else 'neutral' end
    else null end
$$;

insert into game.market(city_id, commodity_id, base_price, current_price, role)
select ci.city_id, co.id, co.base, co.base, coalesce(game.ts_market_role(ci.city_id, co.id), 'neutral')
  from game.cities ci cross join game.commodities co
 where co.active and ci.city_id in ('otoland', 'empeer_depeer', 'freeyork')
on conflict (city_id, commodity_id) do update set base_price = excluded.base_price, role = excluded.role;

-- Cap Restu Dewan (pilihan "bongkar"): Sutra & Porselen -10% di em pe'er de pe'er.
-- Isi selain baris Cap Restu Dewan identik dengan 0024 (krisis pasar Quest 5).
create or replace function game.quest_price_mul(p_pid uuid, p_city text, p_comm text) returns double precision
language plpgsql stable as $$
declare lvl double precision; v_role text; m double precision := 1;
begin
  if p_city = 'empeer_depeer' and p_comm in ('silk', 'porselen')
     and game.ts_data(p_pid) ->> 'garlyena' = 'bongkar' then m := 0.9; end if;
  lvl := game.kp_crisis_level(p_pid);
  if lvl <= 0 then return m; end if;
  if p_city in ('joungjava', 'ikn') and game.cb_step(p_pid) >= 3 then return m; end if;
  select role into v_role from game.market where city_id = p_city and commodity_id = p_comm;
  return m * (1 + lvl * case coalesce(v_role, 'neutral')
    when 'produce' then -0.15
    when 'consume' then 0.25
    else 0.15 end);
end $$;

-- ---------------------------------------------------------------------
-- Buku Pancing Legenda: #11 Tiram Otoland (pagi) & #14 Bayang Paus Bisu kini punya pulau
-- (dulu "Pulau Seribu Tangga" - kini Pulau em pe'er de pe'er). 0025 menulis ulang barisnya
-- setiap deploy dengan l_available = false, jadi diperbarui lagi di sini.
-- ---------------------------------------------------------------------
update game.mp_fish_types set l_available = true, l_time = 'pagi', cities = array['otoland'], l_place = 'Otoland'
 where id = 'tiram_otoland';
update game.mp_fish_types set l_available = true, cities = array['empeer_depeer'], l_place = 'Pulau em pe''er de pe''er'
 where id = 'paus_bisu';

-- ---------------------------------------------------------------------
-- Status (kunci 'tigasilang' di api_getGameState)
-- ---------------------------------------------------------------------
create or replace function game.ts_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare q game.player_quests; v_step int; d jsonb; v_truth text;
begin
  if game.cb_step(p_pid) < 11 then return null; end if;
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'tigasilang';
  v_step := coalesce(q.step, 0);
  d := coalesce(q.data, '{}'::jsonb);
  v_truth := game.ts_truth(p_pid);
  return jsonb_build_object(
    'step', v_step,
    'eligible', true,
    'sails', coalesce((d ->> 'sails')::int, 0),
    'sailsNeed', game.ts_sails_need(),
    'skyAt', (d ->> 'skyAt')::bigint,
    'truth', v_truth,
    'night', game.fish_is_night(),
    'jejak1', coalesce((d ->> 'jejak1')::boolean, false),
    'asked', coalesce(d -> 'asked', '[]'::jsonb),
    'upayy', d ->> 'upayy_answer',
    'gasing1', d ->> 'gasing1',
    'ocid', coalesce((d ->> 'ocid')::boolean, false),
    'pantun', coalesce((d ->> 'pantun')::boolean, false),
    'mata', coalesce((d ->> 'mata')::boolean, false),
    'garlyena', d ->> 'garlyena',
    'tass', coalesce((d ->> 'tass')::boolean, false),
    'jejak2', coalesce((d ->> 'jejak2')::boolean, false),
    'tempa', d ->> 'tempa',
    'andryTalk', coalesce((d ->> 'andryTalk')::boolean, false),
    'dice', d ->> 'dice',
    'diceRoll', d -> 'diceRoll',
    'gasing2', d ->> 'gasing2',
    'hunted', v_step between 9 and 10,
    'huntChance', game.ts_hunt_chance(p_pid),
    'huntWins', coalesce((d ->> 'huntWins')::int, 0),
    'beras', game.item_qty(p_pid, 'beras'),
    'garam', game.item_qty(p_pid, 'garam'),
    'hasPeta', game.item_qty(p_pid, 'qi_peta_pengasingan') > 0,
    'hasJoran', game.item_qty(p_pid, 'qi_joran_nansy') > 0,
    'hasTools', game.item_qty(p_pid, 'qi_kotak_alat_jam') > 0,
    'hasKey', game.item_qty(p_pid, 'qi_kunci_jam_agung') > 0,
    'hasPalu', game.item_qty(p_pid, 'qi_palu_tempa') > 0,
    'hasLetter', game.item_qty(p_pid, 'qi_surat_hitam') > 0,
    'hasWill', game.item_qty(p_pid, 'qi_wasiat_andry') > 0,
    'compass', game.item_qty(p_pid, 'qi_kompas_tedsky') > 0,
    'compass2', game.item_qty(p_pid, 'qi_kompas_dua_jarum') > 0,
    'done', v_step >= 12);
end $$;

-- ---------------------------------------------------------------------
-- Pemicu: pelayaran ketiga setelah Quest 6 selesai -> Langit Hitam
-- ---------------------------------------------------------------------
create or replace function game.ts_on_sail(p_pid uuid, p_origin text, p_dest text) returns void
language plpgsql as $$
declare q game.player_quests; n int;
begin
  if game.cb_step(p_pid) < 11 then return; end if;
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'tigasilang' for update;
  if found and q.step > 0 then return; end if;
  n := coalesce((q.data ->> 'sails')::int, 0) + 1;
  if n < game.ts_sails_need() then
    insert into game.player_quests(player_id, quest_id, step, data) values (p_pid, 'tigasilang', 0, jsonb_build_object('sails', n))
    on conflict (player_id, quest_id) do update set data = game.player_quests.data || jsonb_build_object('sails', n), updated_at = now();
    return;
  end if;
  insert into game.player_quests(player_id, quest_id, step, data)
  values (p_pid, 'tigasilang', 1, jsonb_build_object('sails', n, 'skyAt', game.now_ms(), 'skyTo', p_dest))
  on conflict (player_id, quest_id) do update set step = 1,
    data = jsonb_build_object('sails', n, 'skyAt', game.now_ms(), 'skyTo', p_dest), started_at = now(), updated_at = now();
  perform game.log(p_pid, 'Langit sore menghitam di tengah pelayaran - bukan oleh awan. Ribuan gagak mesin hitam terbang rendah ke barat, ke arah Joungjava. Seekor mematuk-matuk tutup palkamu.');
end $$;

-- Patroli Bebas (0022): setelah Andry gugur, bendera Armada Bebas berkibar setengah tiang
create or replace function game.bx_on_sail(p_pid uuid, p_origin text, p_dest text) returns void
language plpgsql as $$
declare eff numeric; cond numeric; sh jsonb;
begin
  if game.bx_step(p_pid) < 16 then return; end if;
  if random() * 100 >= game.cfg_num('BarsatiPatrolChance', 12) then return; end if;
  sh := game.ship_json(p_pid);
  eff := game.voy_num(sh -> 'EffectiveMaxCondition'); cond := game.voy_num(sh -> 'Condition');
  if cond >= eff then return; end if;
  update game.ships set condition = eff where player_id = p_pid;
  update game.player_quests set data = data || jsonb_build_object('patrolAt', game.now_ms()), updated_at = now()
   where player_id = p_pid and quest_id = 'barsati';
  if game.ts_step(p_pid) >= 8 then
    perform game.log(p_pid, 'Kapal Patroli Bebas berpapasan di laut, benderanya setengah tiang. Tukang mereka menambal lambungmu tanpa bicara. Saat berpisah, mereka menabuh lambung kapal tiga kali.');
  else
    perform game.log(p_pid, 'Kapal Patroli Bebas berpapasan di laut - tukang mereka menambal lambungmu sampai mulus, gratis. "Untuk saudara keempat!"');
  end if;
end $$;

create or replace function game.quest_on_sail(p_pid uuid, p_origin text, p_dest text) returns void
language plpgsql as $$
begin
  perform game.mp_sail_guard(p_pid);
  perform game.ww_on_sail(p_pid, p_origin, p_dest);
  perform game.bx_on_sail(p_pid, p_origin, p_dest);
  perform game.kp_on_sail(p_pid, p_origin, p_dest);
  perform game.ts_on_sail(p_pid, p_origin, p_dest);
end $$;

-- ---------------------------------------------------------------------
-- Diburu: Pemburu Sayap Patah (langkah 9-10, sampai jarum ketiga dipatahkan)
--   Q5 jujur 50% · Q5 bohong 100% (+30% HP, gagak membuat tembakan pertama meleset)
--   simpan rahasia Garlyena: peluang -25 poin · padamkan tungku: -30% HP, tanpa tembakan meleset
-- ---------------------------------------------------------------------
create or replace function game.ts_hunt_chance(p_pid uuid) returns int
language plpgsql stable as $$
declare c int; d jsonb := game.ts_data(p_pid);
begin
  if game.ts_step(p_pid) not between 9 and 10 then return 0; end if;
  c := case when game.ts_truth(p_pid) = 'bohong' then 100 else 50 end;
  if d ->> 'garlyena' = 'simpan' then c := c - 25; end if;
  return greatest(0, least(100, c));
end $$;

create or replace function game.ts_hunter_enc(p_pid uuid) returns jsonb
language plpgsql volatile as $$
declare d jsonb := game.ts_data(p_pid); liar boolean := game.ts_truth(p_pid) = 'bohong';
  padam boolean := (d ->> 'tempa') = 'padam'; hp numeric := 900; ammo numeric := game.ww_ammo(p_pid);
begin
  if liar then hp := hp * 1.3; end if;
  if padam then hp := hp * 0.7; end if;
  hp := round(hp);
  return jsonb_build_object('ts', true, 'boss', 'pemburu', 'enemyName', 'Pemburu Sayap Patah',
    'bossTitle', 'Kapal kecil bersayap logam & kawanan gagak mesin',
    'displayLevel', 6, 'enemyLevel', 3, 'enemyMaxHp', hp, 'enemyHp', hp,
    'dmgTaken', 0.6, 'enemyDmgMul', 1.8, 'softSink', true,
    'rolledAt', game.iso(now()), 'round', 1, 'maxAmmo', ammo, 'ammoRemaining', ammo,
    'immuneFirst', liar and not padam,
    'immuneMsg', 'kawanan gagak menyambar haluanmu tepat saat meriam meletus - tembakan pertamamu meleset jauh.',
    'padam', padam, 'liar', liar,
    'noTalkMsg', 'Kapal itu tidak berbendera. Hanya mata-mata merah yang berkedip di tiangnya.');
end $$;

create or replace function game.ts_hunter_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql volatile as $$
declare c int;
begin
  if game.spot_city(p_dest) then return null; end if;
  c := game.ts_hunt_chance(p_pid);
  if c <= 0 or random() * 100 >= c then return null; end if;
  return game.ts_hunter_enc(p_pid);
end $$;

create or replace function game.quest_boss_encounter(p_pid uuid, p_dest text) returns jsonb
language sql as $$
  select coalesce(game.gala_boss_encounter(p_pid, p_dest), game.tg_hunter_encounter(p_pid, p_dest),
                  game.ww_encounter(p_pid, p_dest), game.bx_encounter(p_pid, p_dest),
                  game.ts_hunter_encounter(p_pid, p_dest))
$$;

create or replace function game.ts_boss_defeated(p_pid uuid) returns jsonb
language plpgsql as $$
declare enc jsonb;
begin
  select pending_encounter into enc from game.player_location where player_id = p_pid;
  if not coalesce((enc ->> 'ts')::boolean, false) then return null; end if;
  update game.player_quests set data = data || jsonb_build_object('huntWins', coalesce((data ->> 'huntWins')::int, 0) + 1), updated_at = now()
   where player_id = p_pid and quest_id = 'tigasilang';
  perform game.log(p_pid, 'Pemburu Sayap Patah karam. Gagak-gagaknya bubar menjadi titik-titik hitam, terbang ke timur.');
  return jsonb_build_object('gold', game.ts_hunter_gold(), 'event', 'pemburu',
    'message', 'Sayap logam kapal pemburu itu patah dan kapalnya miring ke laut. Kawanan gagak di atasnya bubar seperti abu ditiup angin, semua terbang ke timur. Di geladaknya kau menemukan ' || game.ts_hunter_gold() || ' gold dan secarik kertas: rutemu, ditulis dengan tinta merah.');
end $$;

create or replace function game.quest_boss_defeated(p_pid uuid) returns jsonb
language sql as $$ select coalesce(game.gala_boss_defeated(p_pid), game.ww_boss_defeated(p_pid), game.bx_boss_defeated(p_pid), game.ts_boss_defeated(p_pid)) $$;

-- ---------------------------------------------------------------------
-- Aksi quest. a = [action, arg, arg2]
--   status | vault | jejak | ask diri|tedsky | map | upayy bahagia|sendiri | gasing won|lost | sandi
--   | ocid | pantun ok|gagal | mata ok|gagal | garlyena bongkar|simpan | tassyaaa
--   | tempa padam|biarkan [beras|garam] | andry | dadu besar|kecil | titikbuta | pemakaman | jarum | cut | tutup
-- ---------------------------------------------------------------------
create or replace function game.ts_set(p_pid uuid, p_step int, p_data jsonb) returns void
language sql as $$
  update game.player_quests set step = p_step, data = data || coalesce(p_data, '{}'::jsonb), updated_at = now(),
    done_at = case when p_step >= 12 then now() else done_at end
   where player_id = p_pid and quest_id = 'tigasilang'
$$;

create or replace function game.ts_need_city(p_city text, p_need text, p_msg text) returns void
language plpgsql as $$ begin if p_city is distinct from p_need then raise exception '%', p_msg; end if; end $$;

create or replace function game.ts_unlock_payload(p_pid uuid) returns jsonb
language sql as $$
  select jsonb_build_object('tigasilang', game.ts_state(p_pid), 'unlocks', game.player_unlocks(p_pid),
    'cities', game.cities_json(), 'citiesVersion', game.cities_version())
$$;

create or replace function public.api_tigaSilang(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status'); v_arg text := lower(btrim(coalesce(game.arg(a, 1), '')));
  v_arg2 text := lower(btrim(coalesce(game.arg(a, 2), '')));
  q game.player_quests; v_step int; v_city text := game.current_city(v_pid); st jsonb; d jsonb; v_asked jsonb;
  v_need int; v_sum int; v_win boolean; dice jsonb; v_new boolean;
begin
  st := game.ts_state(v_pid);
  if v_act = 'status' then return jsonb_build_object('tigasilang', st); end if;
  if st is null then raise exception 'Langit masih biru untukmu, Kapten.'; end if;
  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;
  select * into q from game.player_quests where player_id = v_pid and quest_id = 'tigasilang' for update;
  v_step := coalesce(q.step, 0);
  d := coalesce(q.data, '{}'::jsonb);
  if v_step < 1 then raise exception 'Langit masih biru untukmu, Kapten.'; end if;

  -- Babak 1: Javasche Bank dibobol
  if v_act = 'vault' then
    perform game.ts_need_city(v_city, 'joungjava', 'Semua orang membicarakan Javasche Bank, Joungjava.');
    if v_step = 1 then
      perform game.ts_set(v_pid, 2, null);
      perform game.log(v_pid, 'Kubah kaca Javasche Bank pecah. Poster buronan baru di dinding Syahbandar: ANDRY IVANKOV - 1.000.000 GOLD.');
    end if;
    return jsonb_build_object('tigasilang', game.ts_state(v_pid));
  end if;

  if v_act = 'jejak' then
    if v_step = 2 then
      perform game.ts_need_city(v_city, 'joungjava', 'Ruang brankas ada di Javasche Bank, Joungjava.');
      perform game.ts_set(v_pid, 2, jsonb_build_object('jejak1', true));
    elsif v_step = 5 then
      perform game.ts_need_city(v_city, 'freeyork', 'Bengkel itu ada di FreeYork.');
      perform game.ts_set(v_pid, 5, jsonb_build_object('jejak2', true));
      perform game.log(v_pid, 'Di bengkel besar FreeYork: rangka sayap logam, mata kaca merah, pesanan bercap J.T., dan sebuah cetakan jarum kecil.');
    else
      raise exception 'Tidak ada jejak yang perlu diperiksa di sini.';
    end if;
    return jsonb_build_object('tigasilang', game.ts_state(v_pid));
  end if;

  if v_act = 'ask' then
    if v_step <> 2 then raise exception 'coco epan sudah menjawab semua yang bisa ia jawab.'; end if;
    perform game.ts_need_city(v_city, 'joungjava', 'coco epan ada di Javasche Bank, Joungjava.');
    if v_arg not in ('diri', 'tedsky') then raise exception 'Pertanyaan tidak dikenal.'; end if;
    v_asked := coalesce(d -> 'asked', '[]'::jsonb);
    if not v_asked ? v_arg then v_asked := v_asked || to_jsonb(v_arg); end if;
    perform game.ts_set(v_pid, 2, jsonb_build_object('asked', v_asked));
    return jsonb_build_object('tigasilang', game.ts_state(v_pid));
  end if;

  if v_act = 'map' then
    if v_step <> 2 then raise exception 'Peta itu sudah di tanganmu.'; end if;
    perform game.ts_need_city(v_city, 'joungjava', 'coco epan ada di Javasche Bank, Joungjava.');
    if not coalesce((d ->> 'jejak1')::boolean, false) then raise exception 'Periksa dulu ruang brankas, Kapten.'; end if;
    v_asked := coalesce(d -> 'asked', '[]'::jsonb);
    if not (v_asked ? 'diri' and v_asked ? 'tedsky') then raise exception 'coco epan menunggu pertanyaanmu.'; end if;
    if game.item_qty(v_pid, 'qi_peta_pengasingan') < 1 then perform game.item_adjust(v_pid, 'qi_peta_pengasingan', 1); end if;
    perform game.ts_set(v_pid, 3, null);
    perform game.log(v_pid, 'coco epan menyerahkan Peta Pengasingan. Kabut di timur Marie Regal tersibak: Otoland.');
    return game.ts_unlock_payload(v_pid) || jsonb_build_object('item', jsonb_build_object('itemId', 'qi_peta_pengasingan', 'name', 'Peta Pengasingan'));
  end if;

  -- Babak 2: Otoland
  if v_act = 'upayy' then
    if v_step <> 3 then raise exception 'Ny. Upayy sedang menambal jaring.'; end if;
    perform game.ts_need_city(v_city, 'otoland', 'Ny. Upayy ada di kincir tua berpintu biru, Otoland.');
    if v_arg not in ('bahagia', 'sendiri') then raise exception 'Jawablah pertanyaannya, Kapten.'; end if;
    if d ? 'upayy_answer' then raise exception 'Kau sudah menjawab Ny. Upayy.'; end if;
    perform game.ts_set(v_pid, 3, jsonb_build_object('upayy_answer', v_arg));
    perform game.log(v_pid, 'Ny. Upayy bercerita tentang lelaki asing yang memasang jam di pergelangan para nelayan Otoland.');
    return jsonb_build_object('tigasilang', game.ts_state(v_pid));
  end if;

  if v_act = 'gasing' and v_step = 3 then
    perform game.ts_need_city(v_city, 'otoland', 'Ny. Upayy ada di Otoland.');
    if not d ? 'upayy_answer' then raise exception 'Ny. Upayy belum selesai bercerita.'; end if;
    if v_arg not in ('won', 'lost') then raise exception 'Hasil adu gasing tidak dikenal.'; end if;
    if game.item_qty(v_pid, 'qi_joran_nansy') < 1 then perform game.item_adjust(v_pid, 'qi_joran_nansy', 1); end if;
    if game.item_qty(v_pid, 'qi_kotak_alat_jam') < 1 then perform game.item_adjust(v_pid, 'qi_kotak_alat_jam', 1); end if;
    perform game.ts_set(v_pid, 3, jsonb_build_object('gasing1', coalesce(d ->> 'gasing1', v_arg)));
    return jsonb_build_object('tigasilang', game.ts_state(v_pid),
      'items', jsonb_build_array(jsonb_build_object('itemId', 'qi_joran_nansy', 'name', 'Joran Kecil Miss Nansy'),
                                 jsonb_build_object('itemId', 'qi_kotak_alat_jam', 'name', 'Kotak Alat Jam Coco')));
  end if;

  if v_act = 'sandi' then
    if v_step <> 3 then raise exception 'Tabung surat itu sudah terbaca.'; end if;
    perform game.ts_need_city(v_city, 'otoland', 'Sarang gagak itu ada di puncak kincir tua, Otoland.');
    if not d ? 'gasing1' then raise exception 'Ny. Upayy masih ingin bicara denganmu.'; end if;
    perform game.ts_set(v_pid, 4, null);
    perform game.log(v_pid, 'Surat di sarang gagak terbaca: "Untuk G. - Pesta bulan mati. Tangga ke-999. Rajamu akan pulang." Peta Pengasingan: Pulau em pe''er de pe''er.');
    return game.ts_unlock_payload(v_pid);
  end if;

  -- Babak 3: em pe'er de pe'er
  if v_act = 'ocid' then
    if v_step <> 4 then raise exception 'Paman Ocid sedang menghitung detik jam yang tidak berjalan.'; end if;
    perform game.ts_need_city(v_city, 'empeer_depeer', 'Paman Ocid ada di bawah Jam Agung, Pulau em pe''er de pe''er.');
    if not coalesce((d ->> 'ocid')::boolean, false) then
      perform game.ts_set(v_pid, 4, jsonb_build_object('ocid', true));
      perform game.log(v_pid, 'Paman Ocid bercerita tentang raja yang meletakkan mahkotanya di anak tangga. Miss Garlyena mengundangmu ke Pesta Topeng Bulan Mati.');
    end if;
    return jsonb_build_object('tigasilang', game.ts_state(v_pid));
  end if;

  if v_act in ('pantun', 'mata', 'garlyena') then
    if v_step <> 4 then raise exception 'Pesta itu sudah usai.'; end if;
    perform game.ts_need_city(v_city, 'empeer_depeer', 'Pesta Topeng digelar di Gedung Kubah, Pulau em pe''er de pe''er.');
    if not coalesce((d ->> 'ocid')::boolean, false) then raise exception 'Kau belum menerima undangan, Kapten.'; end if;
    if v_act <> 'garlyena' and not game.fish_is_night() then
      raise exception 'Pesta Topeng hanya digelar saat malam. Lilin di tangga belum dinyalakan.';
    end if;
  end if;

  if v_act = 'pantun' then
    if v_arg not in ('ok', 'gagal') then raise exception 'Hasil pantun tidak dikenal.'; end if;
    if v_arg = 'ok' then perform game.ts_set(v_pid, 4, jsonb_build_object('pantun', true)); end if;
    return jsonb_build_object('tigasilang', game.ts_state(v_pid));
  end if;

  if v_act = 'mata' then
    if not coalesce((d ->> 'pantun')::boolean, false) then raise exception 'Pintu pesta belum dibuka untukmu.'; end if;
    if v_arg not in ('ok', 'gagal') then raise exception 'Hasil pengamatan tidak dikenal.'; end if;
    if v_arg = 'ok' then
      perform game.ts_set(v_pid, 4, jsonb_build_object('mata', true));
      perform game.log(v_pid, 'Di Pesta Topeng: pria tinggi bertopeng Garuda perunggu. Jendral Tedsky memuji kompasmu.');
    end if;
    return jsonb_build_object('tigasilang', game.ts_state(v_pid));
  end if;

  if v_act = 'garlyena' then
    if not coalesce((d ->> 'mata')::boolean, false) then raise exception 'Kau belum menemukan tamu yang tak diundang.'; end if;
    if v_arg not in ('bongkar', 'simpan') then raise exception 'Putuskan dulu nasib Miss Garlyena, Kapten.'; end if;
    if game.item_qty(v_pid, 'qi_kunci_jam_agung') < 1 then perform game.item_adjust(v_pid, 'qi_kunci_jam_agung', 1); end if;
    perform game.ts_set(v_pid, 5, jsonb_build_object('garlyena', v_arg));
    perform game.log(v_pid, case when v_arg = 'bongkar'
      then 'Persekongkolan Miss Garlyena dibongkar di Sidang Paripurna. Paman Ocid menjadi Ketua Dewan Mahkota dan memberimu Cap Restu Dewan.'
      else 'Kau menyimpan rahasia Miss Garlyena. "Sekarang Anda berutang pada saya, atau saya pada Anda?"' end);
    perform game.log(v_pid, 'Paman Ocid menyerahkan Kunci Jam Agung. Peta Pengasingan: FreeYork.');
    return game.ts_unlock_payload(v_pid) || jsonb_build_object('item', jsonb_build_object('itemId', 'qi_kunci_jam_agung', 'name', 'Kunci Jam Agung'));
  end if;

  -- Babak 4: FreeYork
  if v_act = 'tassyaaa' then
    if v_step <> 5 then raise exception 'Tassyaaa sedang menempa.'; end if;
    perform game.ts_need_city(v_city, 'freeyork', 'Tassyaaa ada di bengkel besar FreeYork.');
    perform game.ts_set(v_pid, 5, jsonb_build_object('tass', true));
    return jsonb_build_object('tigasilang', game.ts_state(v_pid));
  end if;

  if v_act = 'tempa' then
    if v_step <> 5 then raise exception 'Tungku itu sudah diputuskan nasibnya.'; end if;
    perform game.ts_need_city(v_city, 'freeyork', 'Tungku itu ada di FreeYork.');
    if not (coalesce((d ->> 'tass')::boolean, false) and coalesce((d ->> 'jejak2')::boolean, false)) then
      raise exception 'Telusuri dulu bengkel itu, Kapten.';
    end if;
    if v_arg = 'padam' then
      if game.item_qty(v_pid, 'beras') < 20 then raise exception 'Kampung itu akan kehilangan penghasilannya. Bawa 20 Beras di palka untuk mereka.'; end if;
      perform game.adjust_inventory(v_pid, 'beras', -20);
    elsif v_arg = 'biarkan' then
      if v_arg2 not in ('beras', 'garam') then v_arg2 := case when game.item_qty(v_pid, 'beras') >= 10 then 'beras' else 'garam' end; end if;
      if game.item_qty(v_pid, v_arg2) < 10 then raise exception 'Bawa 10 Beras atau 10 Garam untuk kampung pekerja, Kapten.'; end if;
      perform game.adjust_inventory(v_pid, v_arg2, -10);
    else
      raise exception 'Padamkan, atau biarkan menyala?';
    end if;
    if game.item_qty(v_pid, 'qi_palu_tempa') < 1 then perform game.item_adjust(v_pid, 'qi_palu_tempa', 1); end if;
    perform game.ts_set(v_pid, 6, jsonb_build_object('tempa', v_arg));
    perform game.log(v_pid, case when v_arg = 'padam'
      then 'Tungku utama FreeYork disiram air laut. Gagak-gagak di gudang padam matanya. Kau menyerahkan 20 Beras untuk kampung pekerja.'
      else 'Tungku FreeYork dibiarkan menyala. Kau menyerahkan 10 ' || case when v_arg2 = 'beras' then 'Beras' else 'Garam' end || ' untuk kampung pekerja. Tassyaaa menitip pesan untuk Petrik.' end);
    return jsonb_build_object('tigasilang', game.ts_state(v_pid), 'item', jsonb_build_object('itemId', 'qi_palu_tempa', 'name', 'Palu Kecil Tempa'));
  end if;

  -- Babak 5: Paradiso - wajah di poster
  if v_act in ('andry', 'dadu') or (v_act = 'gasing' and v_step = 6) then
    if v_step <> 6 then raise exception 'Ruang VIP itu kosong.'; end if;
    perform game.ts_need_city(v_city, 'paradiso', 'Seseorang menunggumu di ruang VIP Kasino Mutiara, Paradiso.');
  end if;

  if v_act = 'andry' then
    perform game.ts_set(v_pid, 6, jsonb_build_object('andryTalk', true));
    return jsonb_build_object('tigasilang', game.ts_state(v_pid));
  end if;

  if v_act = 'dadu' then
    if d ? 'dice' then raise exception 'Andry menggeleng. "Satu ronde. Demi masa lalu."'; end if;
    if v_arg not in ('besar', 'kecil') then raise exception 'Pilih Besar atau Kecil.'; end if;
    dice := jsonb_build_array(1 + floor(random() * 6)::int, 1 + floor(random() * 6)::int, 1 + floor(random() * 6)::int);
    v_sum := (dice ->> 0)::int + (dice ->> 1)::int + (dice ->> 2)::int;
    v_win := (v_sum >= 11) = (v_arg = 'besar');
    perform game.ts_set(v_pid, 6, jsonb_build_object('dice', case when v_win then 'won' else 'lost' end, 'diceRoll', dice));
    return jsonb_build_object('tigasilang', game.ts_state(v_pid), 'dice', dice, 'sum', v_sum, 'win', v_win);
  end if;

  if v_act = 'gasing' then
    if not (coalesce((d ->> 'andryTalk')::boolean, false) and d ? 'dice') then raise exception 'Andry belum selesai bicara.'; end if;
    if v_arg not in ('won', 'lost') then raise exception 'Hasil adu gasing tidak dikenal.'; end if;
    if game.item_qty(v_pid, 'qi_surat_hitam') < 1 then perform game.item_adjust(v_pid, 'qi_surat_hitam', 1); end if;
    perform game.ts_set(v_pid, 7, jsonb_build_object('gasing2', v_arg));
    perform game.log(v_pid, 'Andry Ivankov menyerahkan surat bersegel lilin hitam. "Buka kalau aku tidak datang." Besok malam, di tempat yang hanya muncul saat lampu dinyalakan.');
    return jsonb_build_object('tigasilang', game.ts_state(v_pid), 'item', jsonb_build_object('itemId', 'qi_surat_hitam', 'name', 'Surat Bersegel Lilin Hitam'),
      'unlocks', game.player_unlocks(v_pid));
  end if;

  -- Babak 6: Titik Buta - pertempuran yang tak bisa dimenangkan (dimainkan di klien)
  if v_act = 'titikbuta' then
    if v_step <> 7 then raise exception 'Lingkaran lentera itu sudah padam.'; end if;
    perform game.ts_need_city(v_city, 'titik_buta', 'Lingkaran lentera menunggu di Titik Buta, saat lampu-lampu dinyalakan.');
    v_new := game.item_qty(v_pid, 'qi_pemukul_andry') < 1;
    if v_new then
      perform game.item_adjust(v_pid, 'qi_pemukul_andry', 1);
      update game.character_stats set combat = combat + 5 where player_id = v_pid;
    end if;
    -- kapal terlempar keluar lingkaran dan terdampar di TooGood (tanpa kerugian muatan/gold)
    update game.player_location set city_id = 'toogood', destination_city_id = null, depart_at = null, arrive_at = null,
        pending_encounter = null, arrived_game_day = game.game_day()
     where player_id = v_pid;
    perform game.ts_set(v_pid, 8, null);
    perform game.log(v_pid, 'MALAM TIGA TANDA SILANG. Jarum ketiga Kompas Tedsky menunjuk dirimu. Sayap Patah datang. Andry Ivankov menabrakkan kapalnya ke lambung Sayap Patah. Marlya dan zafachmie diseret pergi.');
    perform game.log(v_pid, 'Kapal terdampar di TooGood. Pemukul genderang Andry mengapung ke lambungmu.');
    return jsonb_build_object('tigasilang', game.ts_state(v_pid), 'cityId', 'toogood',
      'item', jsonb_build_object('itemId', 'qi_pemukul_andry', 'name', 'Pemukul Genderang Andry'),
      'stats', game.stats_json(v_pid), 'unlocks', game.player_unlocks(v_pid));
  end if;

  -- Babak 7: Seribu Lentera
  if v_act = 'pemakaman' then
    if v_step <> 8 then raise exception 'Lentera-lentera itu sudah dilepas ke teluk.'; end if;
    perform game.ts_need_city(v_city, 'toogood', 'Seluruh TooGood menunggumu di dermaga.');
    if game.item_qty(v_pid, 'qi_surat_hitam') > 0 then perform game.item_adjust(v_pid, 'qi_surat_hitam', -game.item_qty(v_pid, 'qi_surat_hitam')); end if;
    if game.item_qty(v_pid, 'qi_wasiat_andry') < 1 then perform game.item_adjust(v_pid, 'qi_wasiat_andry', 1); end if;
    update game.players set gold = gold + game.ts_reward() where player_id = v_pid;
    perform game.ts_set(v_pid, 9, jsonb_build_object('reward', game.ts_reward()));
    perform game.log(v_pid, 'Seribu lentera di teluk TooGood untuk Andry Ivankov. Empat genderang, tiga penabuh, dan satu genderang yang ditabuh semua orang. Kantong Andry di tangan Teh Euis: ' || game.ts_reward() || ' gold.');
    return jsonb_build_object('tigasilang', game.ts_state(v_pid), 'paid', game.ts_reward(),
      'newGold', (select gold from game.players where player_id = v_pid),
      'item', jsonb_build_object('itemId', 'qi_wasiat_andry', 'name', 'Surat Wasiat Andry'));
  end if;

  -- Babak 8: memutus jarum
  if v_act = 'jarum' then
    if v_step <> 9 then raise exception 'coco epan sudah mengatakan semuanya.'; end if;
    perform game.ts_need_city(v_city, 'toogood', 'coco epan berdiri di pinggir dermaga TooGood.');
    perform game.ts_set(v_pid, 10, null);
    perform game.log(v_pid, 'coco epan: "Tedsky menambahkan jarum ketiga, ditempa di FreeYork. Jarum itulah yang menunjuk dirimu kepadanya." felyx di Gading Island bisa membantu.');
    return jsonb_build_object('tigasilang', game.ts_state(v_pid));
  end if;

  if v_act = 'cut' then
    if v_step <> 10 then raise exception 'Jarum itu sudah patah.'; end if;
    perform game.ts_need_city(v_city, 'gading_island', 'felyx menunggumu di Kedai Stumpy, Gading Island.');
    if game.item_qty(v_pid, 'qi_kotak_alat_jam') < 1 then raise exception 'Kotak Alat Jam Coco tidak ada padamu.'; end if;
    if game.item_qty(v_pid, 'qi_palu_tempa') < 1 then raise exception 'Kau butuh palu kecil dari FreeYork.'; end if;
    if game.item_qty(v_pid, 'qi_kompas_tedsky') > 0 then perform game.item_adjust(v_pid, 'qi_kompas_tedsky', -game.item_qty(v_pid, 'qi_kompas_tedsky')); end if;
    if game.item_qty(v_pid, 'qi_kompas_dua_jarum') < 1 then perform game.item_adjust(v_pid, 'qi_kompas_dua_jarum', 1); end if;
    perform game.ts_set(v_pid, 11, null);
    perform game.log(v_pid, 'Jarum ketiga Kompas Tedsky patah menjadi serbuk. Di laut jauh, kompas kembarannya padam. Pemburu Sayap Patah berhenti mencegat.');
    return jsonb_build_object('tigasilang', game.ts_state(v_pid), 'item', jsonb_build_object('itemId', 'qi_kompas_dua_jarum', 'name', 'Kompas Dua Jarum'));
  end if;

  if v_act = 'tutup' then
    if v_step <> 11 then raise exception 'Belum waktunya, Kapten.'; end if;
    perform game.ts_need_city(v_city, 'joungjava', 'coco epan menunggumu di Javasche Bank, Joungjava.');
    if game.item_qty(v_pid, 'qi_kunci_jam_agung') > 0 then perform game.item_adjust(v_pid, 'qi_kunci_jam_agung', -game.item_qty(v_pid, 'qi_kunci_jam_agung')); end if;
    if game.item_qty(v_pid, 'qi_kotak_alat_jam') > 0 then perform game.item_adjust(v_pid, 'qi_kotak_alat_jam', -game.item_qty(v_pid, 'qi_kotak_alat_jam')); end if;
    perform game.ts_set(v_pid, 12, null);
    perform game.log(v_pid, 'Kunci Jam Agung dan Kotak Alat Jam diserahkan kepada coco epan. "Dua puluh tahun saya lari dari utang darah. Kali ini, saya yang membayar."');
    return jsonb_build_object('tigasilang', game.ts_state(v_pid));
  end if;

  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_tigasilang');

-- ---------------------------------------------------------------------
-- Tide v31: nama istri coco epan adalah Miss Nansy (dulu "Nyonya Maudy" di catatan lama).
-- Rapikan catatan perjalanan pemain yang tertulis sebelum nama itu diganti.
-- ---------------------------------------------------------------------
update game.player_log set message = replace(replace(message, 'Nyonya Maudy', 'Miss Nansy'), 'Maudy', 'Nansy')
 where message like '%Maudy%';

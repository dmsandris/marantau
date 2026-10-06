-- =====================================================================
-- Marantau (Supabase) - 0022 QUEST "TIGA TANDA SILANG" (BarSaTi) - penutup Saga Pertama
-- Terbuka setelah Warwerwor selesai. 3 hari game kemudian warga di setiap pelabuhan
-- berteriak memanggil pemain ke IKN: sayap Garuda roboh, Tedsky kabur, BarSaTi berdiri.
--
-- Langkah (game.player_quests, quest_id = 'barsati'):
--   0  belum mulai (shout = sudah 3 hari game sejak Warwerwor selesai)
--   1  Babak 1   diusir dari IKN; pelayaran ke Joungjava dicegat 3 armada BERANTAI (data.chain)
--   2            tiba di Joungjava -> Pak Tua Karto
--   3  Babak 2   Kasino Mutiara (Paradiso): dadu a'dik (data.dice), setor 75.000 (pay)
--   4            Peti Selundupan ke Titik Buta (hanya muncul malam) -> kapal pengintai
--   5  Babak 3   Armada Terakhir: 6 sekutu (data.allies), Bjorneo terakhir
--   6  Babak 3b  memancing Peti Karam di Bjorneo -> Mahkota Karam (crown)
--   7  Babak 4   Pusaran Bjorneo terbuka; lempar mahkota (throw)
--   8            mini-game Arus Pusaran (navigate perfect|ok)
--   9            Hasiolan "Dendam Gaul-Wash" (engage)
--  10  Babak 5   geladak Tedsky (deck)
--  11  Babak 6   topeng a'dik + M.A.R.I.E. (mask)
--  12  Babak 7   raid: 3 penjelajah putih BERANTAI lalu Satnislaus fase 1 (Aegis) sampai separuh HP
--  13            Black Pearl menabrak Aegis (ram)
--  14            Satnislaus fase 3 (engage)
--  15            pilihan nasib alyfindi & Hasiolan (choice save|drown)
--  16            selesai: hadiah, kapal merapat di Skitraw, Patroli Bebas
-- Aman diulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Titik laut quest (bukan kota): Titik Buta & Pusaran Bjorneo
-- ---------------------------------------------------------------------
insert into game.cities(city_id, name, type, repair_cost_rate, image_url, map_x, map_y, sort, hidden) values
  ('titik_buta', 'Titik Buta',      'BlindSpot', 1.5, '', 36, 70, 9,  true),
  ('pusaran',    'Pusaran Bjorneo', 'Maelstrom', 1.6, '', 62, 84, 10, true)
on conflict (city_id) do update set name = excluded.name, type = excluded.type, repair_cost_rate = excluded.repair_cost_rate,
  map_x = excluded.map_x, map_y = excluded.map_y, sort = excluded.sort, hidden = true;

select game.cfg_set('CitiesVersion', '4-barsati');

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
    else '' end
$$;

-- ---------------------------------------------------------------------
-- Barang quest, artefak & buku hadiah
-- ---------------------------------------------------------------------
insert into game.item_catalog(item_id, name, type, effects, value, price, source, sort) values
  ('qi_peti_adik', 'Peti Selundupan a''dik', 'quest',
   '{"cargoSize": 10, "desc": "20 Besi, 15 Mesiu, 10 Senjata - dikemas rapat oleh orang-orang a''dik. Memakai 10 ruang palka. Tidak bisa dijual, dititip, atau dibuang sampai diserahkan di Titik Buta."}',
   0, null, 'quest', 90),
  ('qi_koin_tiga_silang', 'Koin Tiga Silang', 'quest',
   '{"cargoSize": 0, "desc": "Koin emas bersegel Moramora. Di sisi belakangnya: tiga goresan silang. \"Tanda masuk,\" kata a''dik."}',
   0, null, 'quest', 91),
  ('art_satnislaus_cannon', 'Meriam Satnislaus', 'artifact',
   '{"SpecialEffect": "satnislaus_cannon", "desc": "Meriam plasma dari puing Absolute Justice. +15% peluang menang dan +2 amunisi meriam saat terpasang."}',
   25000, null, 'quest', 20)
on conflict (item_id) do update set name = excluded.name, type = excluded.type, effects = excluded.effects,
  value = excluded.value, price = excluded.price, source = excluded.source, sort = excluded.sort;

insert into game.book_catalog(book_id, name, tier, stat_effects, special_effect, price, source, sort) values
  ('bk_ivankov_maelstrom', 'Navigasi Pusaran Ivankov', 'V', '{"Navigation":20}', 'ivankov_nav', 0, 'quest', 100)
on conflict (book_id) do update set name = excluded.name, tier = excluded.tier, stat_effects = excluded.stat_effects,
  special_effect = excluded.special_effect, price = 0, source = 'quest', sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Konstanta & helper
-- ---------------------------------------------------------------------
create or replace function game.bx_allies() returns text[]
language sql immutable as $$ select array['sunda_empire', 'joungjava', 'skitraw', 'toogood', 'marie_regal', 'bjorneo'] $$;

create or replace function game.bx_fleets() returns text[]
language sql immutable as $$ select array['kuning', 'merah', 'hitam'] $$;

create or replace function game.bx_sat_max() returns int language sql immutable as $$ select 18000 $$;
create or replace function game.bx_pay() returns bigint language sql immutable as $$ select 75000::bigint $$;
create or replace function game.bx_reward() returns bigint language sql immutable as $$ select 500000::bigint $$;
create or replace function game.bx_refund() returns bigint language sql immutable as $$ select 150000::bigint $$;

create or replace function game.bx_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'barsati'), 0) $$;

create or replace function game.bx_has_crown(p_pid uuid) returns boolean
language sql stable as $$
  select game.item_qty(p_pid, 'art_sunken_crown') > 0
      or exists (select 1 from game.ship_equipment where player_id = p_pid and item_id = 'art_sunken_crown')
$$;

-- ---------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------
create or replace function game.bx_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare q game.player_quests; w game.player_quests; v_step int; v_due bigint;
begin
  select * into w from game.player_quests where player_id = p_pid and quest_id = 'warwerwor';
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'barsati';
  if not found and coalesce(w.step, 0) < 12 then return null; end if;
  v_step := coalesce(q.step, 0);
  v_due := (extract(epoch from coalesce(w.done_at, w.updated_at, now())) * 1000)::bigint
           + (3 * game.cfg_num('GameDayLengthRealMinutes', 60) * 60000)::bigint;
  return jsonb_build_object(
    'step', v_step,
    'eligible', coalesce(w.step, 0) >= 12,
    'shout', v_step = 0 and coalesce(w.step, 0) >= 12 and game.now_ms() >= v_due,
    'shoutInMs', case when v_step = 0 then greatest(0, v_due - game.now_ms()) end,
    'chain', coalesce((q.data ->> 'chain')::int, 0),
    'chainNeed', 3,
    'dice', q.data ->> 'dice',
    'diceRoll', q.data -> 'diceRoll',
    'paid', coalesce((q.data ->> 'paid')::bigint, 0),
    'allies', coalesce(q.data -> 'allies', '[]'::jsonb),
    'alliesNeed', cardinality(game.bx_allies()),
    'perfect', (q.data ->> 'perfect')::boolean,
    'putih', coalesce((q.data ->> 'putih')::int, 0),
    'putihNeed', 3,
    'satHp', coalesce((q.data ->> 'satHp')::int, game.bx_sat_max()),
    'satMax', game.bx_sat_max(),
    'choice', q.data ->> 'choice',
    'done', v_step >= 16,
    'night', game.fish_is_night(),
    'patrolAt', (q.data ->> 'patrolAt')::bigint,
    'crown', game.bx_has_crown(p_pid),
    'peti', game.item_qty(p_pid, 'qi_peti_adik') > 0,
    'coin', game.item_qty(p_pid, 'qi_koin_tiga_silang') > 0);
end $$;

-- ---------------------------------------------------------------------
-- Pulau tersembunyi, penyembuhan, perjalanan
-- ---------------------------------------------------------------------
create or replace function game.city_open(p_pid uuid, p_city text) returns boolean
language sql stable as $$
  select coalesce((select not hidden from game.cities where city_id = p_city), false)
      or (p_city = 'paradiso' and game.gala_step(p_pid) >= 6)
      or (p_city = 'marie_regal' and game.ww_step(p_pid) >= 1)
      or (p_city = 'titik_buta' and game.bx_step(p_pid) = 4 and game.fish_is_night())
      or (p_city = 'pusaran' and game.bx_step(p_pid) between 7 and 15)
$$;

create or replace function game.player_unlocks(p_pid uuid) returns jsonb
language sql stable as $$
  select (case when game.gala_step(p_pid) >= 6 then '["paradiso"]'::jsonb else '[]'::jsonb end)
      || (case when game.ww_step(p_pid) >= 1 then '["marie_regal"]'::jsonb else '[]'::jsonb end)
      || (case when game.bx_step(p_pid) = 4 and game.fish_is_night() then '["titik_buta"]'::jsonb else '[]'::jsonb end)
      || (case when game.bx_step(p_pid) between 7 and 15 then '["pusaran"]'::jsonb else '[]'::jsonb end)
$$;

-- Armada Terakhir merawat kapal yang merapat di pusaran (+1 kondisi / 5 dtk)
create or replace function game.heal_city(p_pid uuid, p_city text) returns boolean
language sql stable as $$
  select p_city = 'paradiso' or (p_city = 'toogood' and game.toogood_freed(p_pid))
      or (p_city = 'pusaran' and game.bx_step(p_pid) between 7 and 15)
$$;

-- Patroli Bebas: setelah quest selesai, sesekali berpapasan saat berangkat dan memperbaiki kapal gratis
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
  perform game.log(p_pid, 'Kapal Patroli Bebas berpapasan di laut - tukang mereka menambal lambungmu sampai mulus, gratis. "Untuk saudara keempat!"');
end $$;

create or replace function game.quest_on_sail(p_pid uuid, p_origin text, p_dest text) returns void
language plpgsql as $$
begin
  perform game.ww_on_sail(p_pid, p_origin, p_dest);
  perform game.bx_on_sail(p_pid, p_origin, p_dest);
end $$;

-- ---------------------------------------------------------------------
-- Pertempuran
-- Level tampil (displayLevel) hanya drama; enemyLevel = level efektif untuk peluang kena.
-- Kesulitan diatur lewat dmgTaken, enemyDmgMul, perisai, sekutu & HP tersimpan
-- (lihat hasil simulasi di laporan Q4 / test/0022_barsati.test.js).
-- ---------------------------------------------------------------------
create or replace function game.bx_enc(p_pid uuid, p_kind text, p_n int default 0) returns jsonb
language plpgsql volatile as $$
declare ammo numeric := game.ww_ammo(p_pid); q game.player_quests; hp numeric; mx numeric := game.bx_sat_max();
  base jsonb; pnames text[] := array['Penjelajah Putih "Fajar Suci"', 'Penjelajah Putih "Salju Abadi"', 'Penjelajah Putih "Tabula Rasa"'];
  v_perfect boolean;
begin
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'barsati';
  base := jsonb_build_object('bx', true, 'boss', p_kind, 'rolledAt', game.iso(now()), 'round', 1,
    'maxAmmo', ammo, 'ammoRemaining', ammo, 'softSink', true, 'retreat', true);

  if p_kind in ('kuning', 'merah', 'hitam') then
    base := base || jsonb_build_object('displayLevel', 5, 'enemyLevel', 2, 'enemyMaxHp', 800,
      'enemyHp', least(800, greatest(1, coalesce((q.data -> 'bossHp' ->> p_kind)::numeric, 800))),
      'dmgTaken', 0.6, 'enemyDmgMul', 2.6, 'fleetNo', p_n + 1, 'fleetsNeed', 3,
      'noTalkMsg', 'Bendera BarSaTi berkibar - tiga tanda X merah di atas kain hitam. Tak ada yang mau mendengarmu.');
    if p_kind = 'kuning' then
      return base || jsonb_build_object('enemyName', 'Armada Kuning "Gading"',
        'bossTitle', 'Armada BarSaTi 1/3 - lambung berlapis gading', 'noRam', true,
        'noRamMsg', 'Haluanmu menghantam lambung gading dan memantul begitu saja - tabrakan tak berpengaruh apa-apa. Pakai meriam, Kapten!');
    elsif p_kind = 'merah' then
      return base || jsonb_build_object('enemyName', 'Armada Merah "Saga"',
        'bossTitle', 'Armada BarSaTi 2/3 - menyerbu saat meriammu diam', 'punishReload', 2);
    end if;
    return base || jsonb_build_object('enemyName', 'Armada Hitam "Jelaga"',
      'bossTitle', 'Armada BarSaTi 3/3 - menyerang dari balik asap', 'smoke', true);
  end if;

  if p_kind = 'pengintai' then
    return base || jsonb_build_object('enemyName', 'Kapal Pengintai BarSaTi', 'bossTitle', 'Ujian dari a''dik - Titik Buta',
      'displayLevel', 4, 'enemyLevel', 2, 'enemyMaxHp', 500, 'enemyHp', 500, 'dmgTaken', 0.8, 'enemyDmgMul', 1.4,
      'noTalkMsg', 'Kapal tanpa lampu itu hanya menjawab dengan dentum meriam.');
  end if;

  if p_kind = 'hasiolan2' then
    v_perfect := coalesce((q.data ->> 'perfect')::boolean, false);
    return base || jsonb_build_object('enemyName', 'Hasiolan', 'bossTitle', 'Panglima BarSaTi - kapal curian "Dendam Gaul-Wash"',
      'displayLevel', 8, 'enemyLevel', 4, 'enemyMaxHp', 3500,
      'enemyHp', least(3500, greatest(1, coalesce((q.data -> 'bossHp' ->> 'hasiolan2')::numeric, 3500))), 'dmgTaken', 0.3, 'enemyDmgMul', 3.0,
      'maxAmmo', ammo + case when v_perfect then 2 else 0 end, 'ammoRemaining', ammo + case when v_perfect then 2 else 0 end,
      'immuneFirst', not v_perfect, 'perfect', v_perfect,
      'immuneMsg', 'tembakan pertamamu memantul dari pelat baja purwarupa Gaul-Wash. Hasiolan tertawa: "Ambo yang merancang lambung ini!"',
      'maelstrom', true, 'noRam', true, 'retreatOk', true,
      'noRamMsg', 'Lambung "Dendam Gaul-Wash" dilapisi baja galangan - menabraknya sama saja bunuh diri.',
      'noTalkMsg', 'Hasiolan meludah ke pusaran: "Bicara? Uda Gala sudah cukup bicara seumur hidupnya!"',
      'retreatMsg', 'Kapal Skitraw memotong jalur Hasiolan - kau sempat mundur ke tepi pusaran untuk berbenah.');
  end if;

  if p_kind = 'putih' then
    return base || jsonb_build_object('enemyName', pnames[least(3, p_n + 1)], 'bossTitle', 'Armada Putih Pemerintah Dunia - pengawal Absolute Justice',
      'putihNo', p_n + 1, 'putihNeed', 3,
      'displayLevel', 9, 'enemyLevel', 4, 'enemyMaxHp', 2500,
      'enemyHp', least(2500, greatest(1, coalesce((q.data -> 'bossHp' ->> 'putih')::numeric, 2500))), 'dmgTaken', 0.34, 'enemyDmgMul', 2.9,
      'allyDmg', 210, 'allyNote', 'Armada Terakhir', 'maelstrom', true, 'noRam', true, 'retreatOk', true,
      'noRamMsg', 'Penjelajah putih itu dua kali lebih tinggi dari kapalmu - menabraknya sama saja menabrak tebing.',
      'noTalkMsg', 'Pengeras suara armada putih berderak: "Keadilan tidak bernegosiasi."',
      'retreatMsg', 'Black Pearl menembakkan tirai asap - kau mundur ke tepi pusaran. Penjelajah yang sudah tenggelam tak akan bangkit lagi.');
  end if;

  if p_kind in ('sat1', 'sat3') then
    hp := least(mx, greatest(1, coalesce((q.data ->> 'satHp')::numeric, mx)));
    base := base || jsonb_build_object('boss', 'satnislaus', 'enemyName', 'Capt Satnislaus S',
      'displayLevel', 15, 'enemyLevel', 5, 'enemyMaxHp', mx, 'enemyHp', hp,
      'maelstrom', true, 'noRam', true, 'retreatOk', true,
      'noRamMsg', 'Menabrak Absolute Justice? Bahkan Black Pearl butuh nyawa seorang Andry untuk itu.',
      'noTalkMsg', 'Satnislaus bahkan tidak menoleh: "Sampah tidak diajak bicara. Sampah dibuang."');
    if p_kind = 'sat1' then
      return base || jsonb_build_object('phase', 1, 'shield', true, 'shieldMul', 0.25, 'hpFloor', mx / 2,
        'bossTitle', 'Utusan Pemerintah Dunia - "Absolute Justice" (Aegis Shield aktif)',
        'dmgTaken', 0.7, 'enemyDmgMul', 2.2, 'allyDmg', 380, 'allyNote', 'Armada Terakhir & genderang Andry',
        'retreatMsg', 'Armada Terakhir menutup celah - kau mundur memperbaiki kapal. Luka Absolute Justice tidak akan sembuh.');
    end if;
    return base || jsonb_build_object('phase', 3, 'shield', false, 'final', true,
      'bossTitle', 'Utusan Pemerintah Dunia - "Absolute Justice" (perisai hancur, murka)',
      'dmgTaken', 0.2, 'enemyDmgMul', 4.4, 'allyDmg', 230, 'allyNote', 'Armada Terakhir',
      'retreatMsg', 'Andry membelokkan Black Pearl menghadang meriam Satnislaus - kau sempat mundur. "Pergi, Kapten! Belum selesai!"');
  end if;
  return null;
end $$;

-- Pencegatan di perjalanan: 3 armada ke Joungjava (langkah 1) & pengintai di Titik Buta (langkah 4)
create or replace function game.bx_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql volatile as $$
declare q game.player_quests; n int;
begin
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'barsati';
  if not found then return null; end if;
  if q.step = 1 and p_dest = 'joungjava' then
    n := least(2, coalesce((q.data ->> 'chain')::int, 0));
    return game.bx_enc(p_pid, (game.bx_fleets())[n + 1], n);
  end if;
  if q.step = 4 and p_dest = 'titik_buta' then return game.bx_enc(p_pid, 'pengintai'); end if;
  return null;
end $$;

create or replace function game.quest_boss_encounter(p_pid uuid, p_dest text) returns jsonb
language sql as $$
  select coalesce(game.gala_boss_encounter(p_pid, p_dest), game.tg_hunter_encounter(p_pid, p_dest),
                  game.ww_encounter(p_pid, p_dest), game.bx_encounter(p_pid, p_dest))
$$;

-- HP musuh tersimpan saat mundur / karam: Satnislaus (satHp), armada Babak 1 & Hasiolan (bossHp)
-- -> kapal Tier rendah tetap bisa menang dengan mundur - perbaiki - serang lagi.
create or replace function game.bx_combat_end(p_pid uuid, p_enc jsonb, p_result text) returns void
language plpgsql as $$
declare v_boss text := coalesce(p_enc ->> 'boss', ''); v_hp numeric := greatest(1, round(game.voy_num(p_enc -> 'enemyHp')));
begin
  if not coalesce((p_enc ->> 'bx')::boolean, false) or p_result = 'won' then return; end if;
  if v_boss = 'satnislaus' then
    update game.player_quests set data = data || jsonb_build_object('satHp', v_hp), updated_at = now()
     where player_id = p_pid and quest_id = 'barsati' and step in (12, 14);
  elsif v_boss in ('kuning', 'merah', 'hitam', 'hasiolan2', 'putih') then
    update game.player_quests set data = jsonb_set(data, '{bossHp}', coalesce(data -> 'bossHp', '{}'::jsonb) || jsonb_build_object(v_boss, v_hp)),
        updated_at = now()
     where player_id = p_pid and quest_id = 'barsati' and step in (1, 9, 12);
  end if;
end $$;

create or replace function game.quest_combat_end(p_pid uuid, p_enc jsonb, p_result text) returns void
language plpgsql as $$
begin
  perform game.ww_combat_end(p_pid, p_enc, p_result);
  perform game.bx_combat_end(p_pid, p_enc, p_result);
end $$;

create or replace function game.bx_boss_defeated(p_pid uuid) returns jsonb
language plpgsql as $$
declare enc jsonb; v_boss text; q game.player_quests; n int; v_gold int; v_next jsonb; v_half int := game.bx_sat_max() / 2; v_peti int;
begin
  select pending_encounter into enc from game.player_location where player_id = p_pid;
  if not coalesce((enc ->> 'bx')::boolean, false) then return null; end if;
  v_boss := coalesce(enc ->> 'boss', '');
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'barsati' for update;
  if not found then return null; end if;

  -- Babak 1: tiga armada berantai
  if v_boss in ('kuning', 'merah', 'hitam') and q.step = 1 then
    n := coalesce((q.data ->> 'chain')::int, 0) + 1;
    v_gold := case v_boss when 'hitam' then 2000 else 1500 end;
    if n < 3 then
      update game.player_quests set data = data || jsonb_build_object('chain', n), updated_at = now()
       where player_id = p_pid and quest_id = 'barsati';
      v_next := game.bx_enc(p_pid, (game.bx_fleets())[n + 1], n);
      perform game.log(p_pid, (enc ->> 'enemyName') || ' tenggelam (' || n || '/3). Belum sempat bernapas, layar ' || (v_next ->> 'enemyName') || ' muncul di cakrawala.');
      return jsonb_build_object('gold', v_gold, 'event', 'fleet', 'fleet', n, 'chain', v_next,
        'message', case v_boss
          when 'kuning' then 'Lambung gading itu akhirnya retak di bawah hujan peluru dan Armada Kuning tenggelam (+1.500 gold). Belum sempat kru bersorak, layar merah darah membelah kabut: Armada Merah "Saga" menyerbu!'
          else 'Armada Merah tenggelam dengan geladak terbakar (+1.500 gold). Lalu asap hitam menggulung dari utara, dan dari baliknya terdengar dentum meriam: Armada Hitam "Jelaga"!' end);
    end if;
    update game.player_quests set step = 2, data = data || jsonb_build_object('chain', 3), updated_at = now()
     where player_id = p_pid and quest_id = 'barsati';
    perform game.log(p_pid, 'Tiga armada BarSaTi tenggelam berturut-turut. Kapal compang-camping merapat di Joungjava.');
    return jsonb_build_object('gold', v_gold, 'event', 'fleets', 'fleet', 3, 'arrive', true,
      'message', 'Asap tersibak dan Armada Hitam karam ditelan ombak (+2.000 gold). Tiga armada, satu pelayaran. Kru-mu terduduk lemas di geladak - lalu tertawa. Pelabuhan Joungjava sudah terlihat.');
  end if;

  -- Babak 2: ujian a'dik di Titik Buta
  if v_boss = 'pengintai' and q.step = 4 then
    v_peti := game.item_qty(p_pid, 'qi_peti_adik');
    if v_peti > 0 then perform game.item_adjust(p_pid, 'qi_peti_adik', -v_peti); end if;
    update game.player_quests set step = 5, data = data || jsonb_build_object('allies', '[]'::jsonb), updated_at = now()
     where player_id = p_pid and quest_id = 'barsati';
    perform game.log(p_pid, 'Kapal pengintai BarSaTi tenggelam di Titik Buta. Perahu tanpa bendera mengambil Peti Selundupan tanpa sepatah kata.');
    return jsonb_build_object('gold', 0, 'event', 'pengintai',
      'message', 'Kapal pengintai itu oleng dan tenggelam. Tak lama, sebuah perahu tanpa bendera merapat tanpa suara. Kru berwajah tertutup mengangkat Peti Selundupan a''dik - tanpa sepatah kata pun - lalu menghilang ke dalam gelap. Ujian selesai. Sekarang kau tahu: BarSaTi dan armada Pemerintah Dunia akan berkumpul di satu titik. Kau butuh armada.');
  end if;

  -- Babak 4: Hasiolan di gerbang benteng
  if v_boss = 'hasiolan2' and q.step = 9 then
    update game.player_quests set step = 10, updated_at = now() where player_id = p_pid and quest_id = 'barsati';
    perform game.log(p_pid, '"Dendam Gaul-Wash" lumpuh di gerbang benteng. Hasiolan terjepit di antara puing. Hadiah 30.000 gold.');
    return jsonb_build_object('gold', 30000, 'event', 'hasiolan',
      'message', 'Tiang utama "Dendam Gaul-Wash" patah dan kapal curian itu terseret arus, menghantam tebing karang. Hasiolan terjepit di antara puing, memaki dalam bahasa Minang. Di kabinnya kau menemukan 30.000 gold milik galangan Gaul-Wash. Gerbang benteng Kapal Raja terbuka.');
  end if;

  -- Babak 7: tiga penjelajah putih berantai, lalu Satnislaus
  if v_boss = 'putih' and q.step = 12 then
    n := coalesce((q.data ->> 'putih')::int, 0) + 1;
    update game.player_quests set data = jsonb_set(data, '{bossHp}', coalesce(data -> 'bossHp', '{}'::jsonb) - 'putih')
                                         || jsonb_build_object('putih', n), updated_at = now()
     where player_id = p_pid and quest_id = 'barsati';
    v_next := game.bx_enc(p_pid, case when n < 3 then 'putih' else 'sat1' end, n);
    perform game.log(p_pid, (enc ->> 'enemyName') || ' tenggelam ke pusaran (' || n || '/3).');
    return jsonb_build_object('gold', 0, 'event', 'putih', 'putih', n, 'chain', v_next,
      'message', case when n < 3
        then 'Lampu biru di lambung ' || (enc ->> 'enemyName') || ' padam dan kapal raksasa itu miring ke pusaran (' || n || '/3). Penjelajah berikutnya maju menutup celah!'
        else 'Penjelajah putih terakhir terbelah dan tenggelam. Kini tak ada lagi yang berdiri di antara Armada Terakhir dan Absolute Justice. Kubah cahaya Aegis Shield berdengung - Capt Satnislaus S turun ke geladak.' end);
  end if;

  if v_boss = 'satnislaus' and coalesce((enc ->> 'phase')::int, 1) = 1 and q.step = 12 then
    update game.player_quests set step = 13, data = data || jsonb_build_object('satHp', v_half, 'putih', 3), updated_at = now()
     where player_id = p_pid and quest_id = 'barsati';
    perform game.log(p_pid, 'Absolute Justice terluka separuh. Aegis Shield masih berdiri - Andry membelokkan Black Pearl.');
    return jsonb_build_object('gold', 0, 'event', 'aegis',
      'message', 'Lambung Absolute Justice terbakar di belasan titik, tapi kubah Aegis Shield masih berdengung utuh. Lalu kau melihatnya: Black Pearl berbelok tajam, layar penuh, haluan lurus ke arah perisai. Di haluannya berdiri Andry.');
  end if;

  if v_boss = 'satnislaus' and coalesce((enc ->> 'phase')::int, 1) = 3 and q.step = 14 then
    update game.player_quests set step = 15, data = data || jsonb_build_object('satHp', 0), updated_at = now()
     where player_id = p_pid and quest_id = 'barsati';
    perform game.log(p_pid, 'ABSOLUTE JUSTICE TUMBANG. Capt Satnislaus S tenggelam bersama kapalnya, memberi hormat kepada laut.');
    return jsonb_build_object('gold', 0, 'event', 'satnislaus',
      'message', 'Absolute Justice terbelah dua dan miring ke pusaran. Di geladak yang tenggelam, Capt Satnislaus S berdiri tegak dan memberi hormat - bukan kepadamu, tapi kepada laut. "Kalian pikir sudah menang melawan keadilan? Keadilan... akan datang lagi. Dengan wajah lain."');
  end if;
  return null;
end $$;

create or replace function game.quest_boss_defeated(p_pid uuid) returns jsonb
language sql as $$ select coalesce(game.gala_boss_defeated(p_pid), game.ww_boss_defeated(p_pid), game.bx_boss_defeated(p_pid)) $$;

-- ---------------------------------------------------------------------
-- Memancing Peti Karam di Bjorneo (langkah 6): peluang dinaikkan & pasti berisi Mahkota Karam
-- ---------------------------------------------------------------------
create or replace function game.fish_quest_weight(p_pid uuid, p_fish text, p_city text) returns numeric
language plpgsql stable as $$
begin
  if p_fish = 'peti' and p_city = 'bjorneo' and game.bx_step(p_pid) = 6 and not game.bx_has_crown(p_pid) then return 8; end if;
  return 1;
end $$;

create or replace function game.fish_quest_catch(p_pid uuid, p_fish text) returns jsonb
language plpgsql as $$
begin
  if p_fish <> 'peti' or game.current_city(p_pid) <> 'bjorneo' or game.bx_step(p_pid) <> 6 or game.bx_has_crown(p_pid) then return null; end if;
  perform game.item_adjust(p_pid, 'art_sunken_crown', 1);
  perform game.log(p_pid, 'Peti Karam dari perairan dalam Bjorneo berisi MAHKOTA KARAM - mahkota Raja Bjorneo yang tenggelam.');
  return jsonb_build_object('itemId', 'art_sunken_crown', 'name', 'Mahkota Karam', 'quest', 'barsati',
    'message', 'Engsel peti yang berkarat patah. Di antara lumpur dan kerang, sesuatu berpendar keemasan: sebuah mahkota tua bertatah mutiara hitam. Mahkota Karam - mahkota Raja Bjorneo.');
end $$;

-- ---------------------------------------------------------------------
-- Dagang & misi tidak ada di titik laut quest
-- ---------------------------------------------------------------------
create or replace function game.eco_require_trade_here(p_pid uuid, p_city text) returns void
language plpgsql as $$
begin
  if game.current_city(p_pid) is distinct from p_city then
    raise exception 'Kamu harus berada di kota ini untuk berdagang.';
  end if;
  if game.in_transit(p_pid) then
    raise exception 'Kamu sedang berlayar - tidak bisa berdagang sampai kapal merapat.';
  end if;
  if game.spot_city(p_city) then
    raise exception 'Tak ada pedagang di tengah pusaran, Kapten. Yang ada hanya ombak, petir, dan meriam.';
  end if;
  if game.ww_market_closed(p_pid) then
    raise exception 'Toko tutup. Kami diminta diam oleh Pemerintah.';
  end if;
  if p_city = 'marie_regal' and game.ww_step(p_pid) < 12 then
    raise exception 'AKSES DITOLAK. Seluruh toko Marie Regal tertutup bagi tamu.';
  end if;
end $$;

create or replace function game.ww_mission_guard(p_pid uuid, p_city text) returns void
language plpgsql as $$
begin
  if game.spot_city(p_city) then
    raise exception 'Tak ada gubernur, apalagi papan misi, di tengah badai ini.';
  end if;
  if game.ww_angry(p_pid, p_city) then
    raise exception 'Gubernur menolak bekerja sama denganmu. "Kau menjual pulau kami, Kapten."';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Aksi quest. a = [action, arg]
--   status | garuda | karto | dice [besar|kecil] | pay | ally | crown | throw | navigate [perfect|ok]
--   engage | deck | mask | ram | choice [save|drown]
-- ---------------------------------------------------------------------
create or replace function game.bx_set(p_pid uuid, p_step int, p_data jsonb) returns void
language sql as $$
  update game.player_quests set step = p_step, data = data || coalesce(p_data, '{}'::jsonb), updated_at = now(),
    done_at = case when p_step >= 16 then now() else done_at end
   where player_id = p_pid and quest_id = 'barsati'
$$;

create or replace function public.api_barsati(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status'); v_arg text := lower(btrim(coalesce(game.arg(a, 1), '')));
  q game.player_quests; v_step int; v_city text := game.current_city(v_pid); st jsonb;
  v_list jsonb; d jsonb; v_sum int; v_win boolean; enc jsonb; v_slot text; v_equipped boolean := false; v_newbook boolean;
begin
  st := game.bx_state(v_pid);
  if v_act = 'status' then return jsonb_build_object('barsati', st); end if;
  if st is null then raise exception 'Laut masih tenang untukmu, Kapten. Belum ada yang memanggil.'; end if;
  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;
  select * into q from game.player_quests where player_id = v_pid and quest_id = 'barsati' for update;
  v_step := coalesce(q.step, 0);

  -- Pemicu: sayap Garuda roboh di IKN
  if v_act = 'garuda' then
    if v_step <> 0 then raise exception 'Garuda IKN sudah roboh - kau sudah dalam perjalanan.'; end if;
    if not coalesce((st ->> 'shout')::boolean, false) then raise exception 'IKN masih tenang. Belum waktunya.'; end if;
    if v_city <> 'ikn' then raise exception 'Warga berteriak menyuruhmu ke IKN, Kapten.'; end if;
    insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'barsati', 1, '{"chain": 0}')
    on conflict (player_id, quest_id) do update set step = 1, data = '{"chain": 0}', started_at = now(), updated_at = now();
    perform game.log(v_pid, 'Sebelah sayap Garuda perunggu IKN roboh. Rantai Jendral Tedsky kosong - hanya jubah putih yang terbakar. Armada BarSaTi mengusirmu dari IKN!');
    return jsonb_build_object('barsati', game.bx_state(v_pid), 'next', 'joungjava');
  end if;

  if v_step = 0 then raise exception 'Belum waktunya, Kapten.'; end if;

  -- Babak 1: Pak Tua Karto di Warung Pantai Joungjava
  if v_act = 'karto' then
    if v_step <> 2 then raise exception 'Pak Tua Karto sedang menyeruput kopinya. Tak ada yang perlu dibicarakan.'; end if;
    if v_city <> 'joungjava' then raise exception 'Pak Tua Karto ada di Warung Pantai Joungjava.'; end if;
    perform game.bx_set(v_pid, 3, null);
    perform game.log(v_pid, 'Pak Tua Karto: "Pergilah ke tempat uang berputar tanpa henti, di pulau penuh kenikmatan."');
    return jsonb_build_object('barsati', game.bx_state(v_pid));
  end if;

  -- Babak 2: Kasino Mutiara, Paradiso
  if v_act = 'dice' then
    if v_step <> 3 then raise exception 'Meja dadu itu bukan untukmu malam ini.'; end if;
    if v_city <> 'paradiso' then raise exception 'a''dik menunggu di ruang VIP Kasino Mutiara, Paradiso.'; end if;
    if q.data ? 'dice' then raise exception 'a''dik menggeleng sambil melempar koinnya. "Satu ronde cukup. Sekarang kita bicara."'; end if;
    if v_arg not in ('besar', 'kecil') then raise exception 'Pilih Besar atau Kecil.'; end if;
    d := jsonb_build_array(1 + floor(random() * 6)::int, 1 + floor(random() * 6)::int, 1 + floor(random() * 6)::int);
    v_sum := (d ->> 0)::int + (d ->> 1)::int + (d ->> 2)::int;
    v_win := (v_sum >= 11) = (v_arg = 'besar');
    perform game.bx_set(v_pid, 3, jsonb_build_object('dice', case when v_win then 'won' else 'lost' end, 'diceRoll', d, 'diceSide', v_arg));
    perform game.log(v_pid, 'Satu ronde Besar/Kecil melawan a''dik di Kasino Mutiara: ' || v_sum || ' - ' || case when v_win then 'menang.' else 'kalah.' end);
    return jsonb_build_object('dice', d, 'sum', v_sum, 'win', v_win, 'side', v_arg,
      'message', case when v_win then '"Kau berani bertaruh. Bagus. Orang yang berani bertaruh biasanya berani mati."'
                      else '"Kalah, tapi tidak lari dari meja. Itu lebih langka daripada menang."' end,
      'barsati', game.bx_state(v_pid));
  end if;

  if v_act = 'pay' then
    if v_step <> 3 then raise exception 'a''dik tidak menagih apa pun darimu.'; end if;
    if v_city <> 'paradiso' then raise exception 'a''dik menunggu di ruang VIP Kasino Mutiara, Paradiso.'; end if;
    if not q.data ? 'dice' then raise exception '"Dadu dulu, baru bicara," kata a''dik.'; end if;
    if v_me.gold < game.bx_pay() then raise exception 'a''dik melirik kantongmu. "75.000 gold, Kapten. Kurang dari itu, kau hanya membuang waktuku."'; end if;
    if game.cargo_free(v_pid) < 10 then raise exception 'Palkamu penuh. Kosongkan 10 ruang untuk Peti Selundupan a''dik.'; end if;
    update game.players set gold = gold - game.bx_pay() where player_id = v_pid;
    perform game.item_adjust(v_pid, 'qi_peti_adik', 1);
    if game.item_qty(v_pid, 'qi_koin_tiga_silang') < 1 then perform game.item_adjust(v_pid, 'qi_koin_tiga_silang', 1); end if;
    perform game.bx_set(v_pid, 4, jsonb_build_object('paid', game.bx_pay()));
    perform game.log(v_pid, 'Menyetor 75.000 gold kepada a''dik. Menerima Peti Selundupan dan sebuah Koin Tiga Silang sebagai "tanda masuk".');
    return jsonb_build_object('paid', game.bx_pay(), 'newGold', v_me.gold - game.bx_pay(),
      'items', jsonb_build_array(jsonb_build_object('itemId', 'qi_peti_adik', 'name', 'Peti Selundupan a''dik'),
                                 jsonb_build_object('itemId', 'qi_koin_tiga_silang', 'name', 'Koin Tiga Silang')),
      'barsati', game.bx_state(v_pid), 'unlocks', game.player_unlocks(v_pid),
      'cities', game.cities_json(), 'citiesVersion', game.cities_version());
  end if;

  -- Babak 3: Armada Terakhir (klien memanggil setelah mini-game / percakapan)
  if v_act = 'ally' then
    if v_step <> 5 then raise exception 'Belum waktunya mengumpulkan armada.'; end if;
    if not (v_city = any (game.bx_allies())) then raise exception 'Tak ada penguasa di sini yang bisa kau ajak berlayar.'; end if;
    v_list := coalesce(q.data -> 'allies', '[]'::jsonb);
    if v_list ? v_city then raise exception 'Armada % sudah berdiri di belakangmu.', game.city_name(v_city); end if;
    if v_city = 'bjorneo' and jsonb_array_length(v_list) < cardinality(game.bx_allies()) - 1 then
      raise exception '"Orang Bjorneo tidak berlayar sendirian, dan tidak pernah berlayar paling depan untuk perang orang lain. Kembalilah kalau seluruh Mare Nusantara sudah berdiri di belakangmu."';
    end if;
    v_list := v_list || to_jsonb(v_city);
    perform game.bx_set(v_pid, case when v_city = 'bjorneo' then 6 else 5 end, jsonb_build_object('allies', v_list));
    perform game.log(v_pid, game.city_name(v_city) || ' bergabung dengan Armada Terakhir (' || jsonb_array_length(v_list) || '/6).' ||
      case when v_city = 'bjorneo' then ' Api besar menyala di puncak gunung api Bjorneo.' else '' end);
    return jsonb_build_object('ally', v_city, 'count', jsonb_array_length(v_list), 'barsati', game.bx_state(v_pid));
  end if;

  -- Babak 3b: Mahkota Karam
  if v_act = 'crown' then
    if v_step <> 6 then raise exception 'Nenek Ulin belum memintamu apa-apa.'; end if;
    if v_city <> 'bjorneo' then raise exception 'Bawa mahkota itu kepada Nenek Ulin di mercusuar Bjorneo.'; end if;
    if not game.bx_has_crown(v_pid) then raise exception '"Mahkota raja hanya kembali pada laut yang mengambilnya. Pancinglah di tempat paling dalam."'; end if;
    perform game.bx_set(v_pid, 7, null);
    perform game.log(v_pid, 'Nenek Ulin menatap Mahkota Karam lama. Badai ungu di barat Bjorneo kini terlihat di peta: Pusaran Bjorneo.');
    return jsonb_build_object('barsati', game.bx_state(v_pid), 'unlocks', game.player_unlocks(v_pid),
      'cities', game.cities_json(), 'citiesVersion', game.cities_version());
  end if;

  -- Babak 4-7: semua terjadi di Pusaran Bjorneo
  if v_act in ('throw', 'navigate', 'engage', 'deck', 'mask', 'ram') and v_city <> 'pusaran' then
    raise exception 'Itu hanya bisa dilakukan di Pusaran Bjorneo.';
  end if;

  if v_act = 'throw' then
    if v_step <> 7 then raise exception 'Mahkota itu sudah kembali ke laut.'; end if;
    if not game.bx_has_crown(v_pid) then raise exception 'Kau tidak membawa Mahkota Karam.'; end if;
    if game.item_qty(v_pid, 'art_sunken_crown') > 0 then
      perform game.item_adjust(v_pid, 'art_sunken_crown', -1);
    else
      delete from game.ship_equipment where player_id = v_pid
         and slot_type = (select slot_type from game.ship_equipment where player_id = v_pid and item_id = 'art_sunken_crown' order by slot_type limit 1);
    end if;
    perform game.bx_set(v_pid, 8, null);
    perform game.log(v_pid, 'Melempar Mahkota Karam ke pusaran. Mahkota tenggelam berpendar emas - jalur cahaya terbentuk di permukaan arus.');
    return jsonb_build_object('barsati', game.bx_state(v_pid));
  end if;

  if v_act = 'navigate' then
    if v_step <> 8 then raise exception 'Jalur cahaya itu sudah kau lalui.'; end if;
    if v_arg not in ('perfect', 'ok') then raise exception 'Hasil navigasi tidak dikenal.'; end if;
    perform game.bx_set(v_pid, 9, jsonb_build_object('perfect', v_arg = 'perfect'));
    perform game.log(v_pid, 'Menembus Arus Pusaran sampai gerbang benteng Kapal Raja Bjorneo' ||
      case when v_arg = 'perfect' then ' tanpa satu goresan pun.' else '.' end);
    return jsonb_build_object('barsati', game.bx_state(v_pid));
  end if;

  if v_act = 'engage' then
    if v_step not in (9, 12, 14) then raise exception 'Tidak ada musuh yang menghadang saat ini.'; end if;
    if jsonb_typeof((select pending_encounter from game.player_location where player_id = v_pid)) = 'object' then
      raise exception 'Pertempuran masih berlangsung.';
    end if;
    enc := case v_step
      when 9 then game.bx_enc(v_pid, 'hasiolan2')
      when 12 then case when coalesce((q.data ->> 'putih')::int, 0) < 3
                        then game.bx_enc(v_pid, 'putih', coalesce((q.data ->> 'putih')::int, 0))
                        else game.bx_enc(v_pid, 'sat1') end
      else game.bx_enc(v_pid, 'sat3') end;
    -- "Pelayaran" pusaran -> pusaran yang langsung tiba, supaya alur pertempuran biasa bekerja
    update game.player_location set destination_city_id = 'pusaran', depart_at = now() - interval '1 second', arrive_at = now(),
        pending_encounter = enc
     where player_id = v_pid;
    perform game.log(v_pid, 'Menyerang dari tepi pusaran: ' || (enc ->> 'enemyName') || '.');
    return jsonb_build_object('barsati', game.bx_state(v_pid), 'encounter', enc, 'voyage', game.voyage_state(v_pid));
  end if;

  if v_act = 'deck' then
    if v_step <> 10 then raise exception 'Bukan saatnya.'; end if;
    perform game.bx_set(v_pid, 11, null);
    perform game.log(v_pid, 'Armada putih Capt Satnislaus S muncul dari badai - dan menembak geladak Tedsky, bukan kapalmu.');
    return jsonb_build_object('barsati', game.bx_state(v_pid));
  end if;

  if v_act = 'mask' then
    if v_step <> 11 then raise exception 'Bukan saatnya.'; end if;
    perform game.bx_set(v_pid, 12, jsonb_build_object('putih', 0, 'satHp', game.bx_sat_max()));
    perform game.log(v_pid, 'a''dik melempar topeng porselennya ke laut. Andry Ivankov. Di Marie Regal, M.A.R.I.E. berbicara lagi - dan armada putih menjadi tuli dan buta.');
    return jsonb_build_object('barsati', game.bx_state(v_pid));
  end if;

  if v_act = 'ram' then
    if v_step <> 13 then raise exception 'Bukan saatnya.'; end if;
    perform game.bx_set(v_pid, 14, null);
    perform game.log(v_pid, 'Andry menabrakkan haluan Black Pearl ke Absolute Justice. Aegis Shield pecah berkeping-keping!');
    return jsonb_build_object('barsati', game.bx_state(v_pid));
  end if;

  -- Pilihan bercabang & hadiah
  if v_act = 'choice' then
    if v_step <> 15 then raise exception 'Belum ada yang perlu diputuskan.'; end if;
    if v_arg not in ('save', 'drown') then raise exception 'Putuskan dulu, Kapten: lempar tali, atau biarkan laut menelan mereka.'; end if;
    perform game.bx_set(v_pid, 16, jsonb_build_object('choice', v_arg));
    update game.players set gold = gold + game.bx_reward() + game.bx_refund() where player_id = v_pid;
    -- Artefak Meriam Satnislaus (langsung dipasang bila ada slot kosong)
    perform game.item_adjust(v_pid, 'art_satnislaus_cannon', 1);
    if not exists (select 1 from game.ship_equipment where player_id = v_pid and item_id = 'art_satnislaus_cannon') then
      select s.slot into v_slot from unnest(game.artifact_slots()) with ordinality s(slot, ord)
       where not exists (select 1 from game.ship_equipment e where e.player_id = v_pid and e.slot_type = s.slot and coalesce(e.item_id, '') <> '')
       order by s.ord limit 1;
      if v_slot is not null then
        insert into game.ship_equipment(player_id, slot_type, item_id) values (v_pid, v_slot, 'art_satnislaus_cannon')
        on conflict (player_id, slot_type) do update set item_id = excluded.item_id;
        perform game.item_adjust(v_pid, 'art_satnislaus_cannon', -1);
        v_equipped := true;
      end if;
    end if;
    -- Buku Navigasi Pusaran Ivankov (+20 Navigation, waktu tempuh -10%)
    insert into game.player_books(player_id, book_id, date_acquired) values (v_pid, 'bk_ivankov_maelstrom', game.game_day())
    on conflict do nothing;
    get diagnostics v_sum = row_count;
    v_newbook := v_sum > 0;
    if v_newbook then update game.character_stats set navigation = navigation + 20 where player_id = v_pid; end if;
    -- Kapal merapat di Skitraw (adegan terakhir)
    update game.player_location set city_id = 'skitraw', destination_city_id = null, depart_at = null, arrive_at = null,
        pending_encounter = null, arrived_game_day = game.game_day()
     where player_id = v_pid;
    perform game.log(v_pid, case when v_arg = 'save'
      then 'Melempar tali kepada alyfindi dan Hasiolan. Hasiolan menyikat lambung kapal di bawah garis air Gaul-Wash seumur hidup; alyfindi menggambar peta bintang di sel TooGood.'
      else 'Membiarkan pusaran menelan alyfindi dan Hasiolan. dwi de''clown melukis dua nisan kosong di kanvas hitam.' end);
    perform game.log(v_pid, 'SAGA PERTAMA SELESAI. Pusaran Bjorneo mereda. Andry mengembalikan 150.000 gold; Pemerintah Moramora & para gubernur menghadiahkan 500.000 gold, Meriam Satnislaus, dan Navigasi Pusaran Ivankov.');
    return jsonb_build_object('barsati', game.bx_state(v_pid), 'choice', v_arg, 'cityId', 'skitraw',
      'rewards', jsonb_build_object('gold', game.bx_reward(), 'refund', game.bx_refund(), 'total', game.bx_reward() + game.bx_refund(),
        'artifact', jsonb_build_object('itemId', 'art_satnislaus_cannon', 'name', 'Meriam Satnislaus', 'equipped', v_equipped,
                                       'effect', '+15% peluang menang, +2 amunisi meriam'),
        'book', jsonb_build_object('id', 'bk_ivankov_maelstrom', 'name', 'Navigasi Pusaran Ivankov', 'new', v_newbook,
                                   'effect', '+20 Navigation, waktu tempuh -10%')),
      'newGold', (select gold from game.players where player_id = v_pid),
      'ship', game.ship_json(v_pid), 'stats', game.stats_json(v_pid),
      'unlocks', game.player_unlocks(v_pid), 'cities', game.cities_json(), 'citiesVersion', game.cities_version());
  end if;

  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_barsati');

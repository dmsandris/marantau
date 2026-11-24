-- =====================================================================
-- 0100 · Saga 4 Bagian II "Takhta Tanpa Mahkota" (langkah 41-60)
--   Konsep: claude/KONSEP-Saga4-Bagian-II-Takhta-Tanpa-Mahkota.md v1.5
--   Rencana: claude/PLAN-Coding-Saga4-Bagian-II.md
--
--   Penyimpanan: baris TERPISAH game.player_quests (quest_id = 'mahkota2', step 0..20 = langkah 41..60).
--   Baris 'mahkota' (Bagian I) tidak disentuh sama sekali, jadi mk_tamat (step >= 40), Sirkuit, Adu Kapten,
--   Set Kedai "Jaring Putus", pelepasan Mesin Jolt, dan semua kait Bagian I tetap persis seperti sebelumnya.
--   Klien tetap melihat satu quest "mahkota": mk_state dibungkus supaya step = 40 + langkah Bagian II.
--
--   Pemicu: Bagian I tamat (step 40) + Mk2JedaHari (3) hari game + gerbang Mahkota2Open (FiturPenguji ikut).
--   Pemain yang sudah memulai Bagian II selalu boleh lanjut.
--
--   Titik kait (pola bungkus, akhiran _mk2):
--     game.mk_state · public.api_mahkota · game.kd_enc · public.api_resolveCombat
--     game.quest_boss_defeated · game.quest_combat_end · game.kd_req_ok · game.kd_list
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('Mahkota2Open', '0'),          -- gerbang Bagian II (jangan diubah di migrasi; diatur GM)
  ('Mk2JedaHari', '3'),           -- hari game setelah langkah 40 sampai langkah 41 muncul
  ('Mk2GoldQ20', '1500000'), ('Mk2GoldQ21', '2000000'), ('Mk2GoldQ22', '2500000'),
  ('MkNavyPct', '50'),            -- peluang Navy di pelayaran yang BUKAN ke tujuan langkah aktif
  ('MkNavyHp1', '600'), ('MkNavyHp2', '1000'), ('MkNavyHp3', '1600'), ('MkNavyHp4', '1400'),
  ('MkNavyDmgKali', '1'),         -- pengali damage Navy ke kapal pemain (kenop keseimbangan)
  ('MkNavyKepingCap', '40'),      -- lewat batas ini per hari game, Keping per kemenangan = 1
  ('MkFlagshipHp', '6000'),
  ('Mk2BossDmgKali', '1')         -- pengali damage armada Battle Akhir ke kapal pemain
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Tabel langkah Bagian II. Indeks 0 = langkah 41.
--   c kota · p tempat · b tombol · g mini game · arr dipicu saat merapat
--   bahan  setoran sekaligus (sebelum mini game bila ada)   cicil setoran bertahap
--   race   balapan (Trektrek-an Kilat)  perang  rangkaian Battle Akhir Bersama
-- ---------------------------------------------------------------------
create or replace function game.mk2_steps() returns jsonb
language sql immutable as $$
  select '[
    {"n":41,"q":20,"p":"kota","b":"kabar"},
    {"n":42,"q":20,"c":"marie_regal","p":"istana","b":"suar","g":"sandi"},
    {"n":43,"q":20,"c":"joungjava","p":"bank","b":"coco"},
    {"n":44,"q":20,"c":"marie_regal","p":"istana","b":"koordinat","g":"tercecer"},
    {"n":45,"q":20,"c":"empeer_depeer","p":"arsip","b":"brankas"},
    {"n":46,"q":20,"c":"toogood","p":"pustaka","b":"kunci"},
    {"n":47,"q":20,"c":"rantai_lama","p":"tiba","b":"teluk","arr":true,"gold":"Mk2GoldQ20"},
    {"n":48,"q":21,"c":"rantai_lama","p":"kongsi","b":"kesaksian"},
    {"n":49,"q":21,"c":"karang_garam","p":"dermaga","b":"nasiulam","g":"selam","bahan":{"beras":10}},
    {"n":50,"q":21,"c":"freeyork","p":"dok","b":"tungku","bahan":{"besi":20,"mesiu":15}},
    {"n":51,"q":21,"c":"zentul","p":"garasi","b":"kalibrasi","g":"tempa","bahan":{"oli_hitam":15,"tools":10}},
    {"n":52,"q":21,"c":"marie_regal","p":"istana","b":"pengacau","bahan":{"emas":5,"mutiara":5}},
    {"n":53,"q":21,"c":"skitraw","p":"galangan","b":"penghangat","bahan":{"jackdaniels":20,"jhonnywalker":20}},
    {"n":54,"q":21,"c":"toogood","p":"dok","b":"ransum","cicil":{"beras":300,"ikan_asin":300,"tuak":150},"gold":"Mk2GoldQ21","tanda":"janjirantai"},
    {"n":55,"q":22,"c":"rantai_lama","p":"tiba","b":"blokade","arr":true},
    {"n":56,"q":22,"c":"rantai_lama","p":"dermaga","b":"gerbang","g":"sandi"},
    {"n":57,"q":22,"c":"rantai_lama","p":"kongsi","b":"dewan"},
    {"n":58,"q":22,"c":"rantai_lama","p":"dermaga","b":"barisan","race":"patroli","perang":true},
    {"n":59,"q":22,"c":"rantai_lama","p":"dermaga","b":"jantung","perang":true},
    {"n":60,"q":22,"c":"rantai_lama","p":"dermaga","b":"sovereign","perang":true,"pilih":["hancurkan","ocid"],"gold":"Mk2GoldQ22","tanda":"penakluk","tamat":true}
  ]'::jsonb
$$;
create or replace function game.mk2_ada() returns int language sql immutable as $$ select jsonb_array_length(game.mk2_steps()) $$;

create or replace function game.mk2_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'mahkota2'), 0) $$;
create or replace function game.mk2_mulai(p_pid uuid) returns boolean
language sql stable as $$ select exists (select 1 from game.player_quests where player_id = p_pid and quest_id = 'mahkota2') $$;
create or replace function game.mk2_tamat(p_pid uuid) returns boolean
language sql stable as $$ select game.mk2_step(p_pid) >= game.mk2_ada() $$;
create or replace function game.mk2_data(p_pid uuid) returns jsonb
language sql stable as $$ select coalesce((select data from game.player_quests where player_id = p_pid and quest_id = 'mahkota2'), '{}'::jsonb) $$;

-- Hari game saat langkah 40 ditamatkan (done_at; cadangan updated_at)
create or replace function game.mk2_hari40(p_pid uuid) returns int
language plpgsql stable as $$
declare v_at timestamptz; v_start bigint; v_len numeric;
begin
  select coalesce(done_at, updated_at) into v_at from game.player_quests where player_id = p_pid and quest_id = 'mahkota' and step >= 40;
  if v_at is null then return null; end if;
  v_start := game.cfg_num('WorldStartTimestamp', 0)::bigint;
  v_len := game.cfg_num('GameDayLengthRealMinutes', 60);
  if v_start = 0 or v_len <= 0 then return 0; end if;
  return floor((extract(epoch from v_at) * 1000 - v_start) / (v_len * 60000))::int;
exception when others then return null;
end $$;

create or replace function game.mk2_eligible(p_pid uuid) returns boolean
language plpgsql stable as $$
declare h int;
begin
  if p_pid is null or game.mk_step(p_pid) < 40 then return false; end if;
  if game.mk2_mulai(p_pid) then return true; end if;
  if not game.fitur_on(p_pid, 'Mahkota2Open') then return false; end if;
  if coalesce(game.pasir_era(p_pid), 'kini') <> 'kini' then return false; end if;
  h := game.mk2_hari40(p_pid);
  return h is not null and game.game_day() >= h + greatest(0, game.cfg_num('Mk2JedaHari', 3))::int;
exception when others then return false;
end $$;

-- Navy aktif selama langkah 41 sudah dibaca sampai sebelum Battle Akhir dimenangkan (langkah aktif 42-59)
create or replace function game.mk2_navy_tier(p_pid uuid) returns int
language plpgsql stable as $$
declare s int;
begin
  if not game.mk2_mulai(p_pid) then return 0; end if;
  s := game.mk2_step(p_pid);          -- langkah aktif = 41 + s
  if s < 1 or s > 18 then return 0; end if;
  return case when s <= 3 then 1 when s <= 8 then 2 when s <= 13 then 3 else 4 end;
end $$;

create or replace function game.mk2_view(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v int := game.mk2_step(p_pid); d jsonb := game.mk2_data(p_pid); q jsonb;
begin
  select data into q from game.player_quests where player_id = p_pid and quest_id = 'mahkota';
  q := coalesce(q, '{}'::jsonb);
  return jsonb_build_object(
    'step', v, 'tamat', v >= game.mk2_ada(), 'data', d,
    'stempel', coalesce(q ->> 'stempel', 'patahkan'), 'marlya', coalesce(q ->> 'marlya', 'maafkan'),
    'fate', case when coalesce(game.dt_data(p_pid) ->> 'fate', 'dewan') = 'ikn' then 'ikn' else 'dewan' end,
    'navy', game.mk2_navy_tier(p_pid), 'navyMenang', coalesce((d ->> 'navyMenang')::int, 0),
    'ba', coalesce((d ->> 'ba')::int, 0), 'kilat', coalesce((d ->> 'kilat')::boolean, false),
    'menang', coalesce((d ->> 'menang')::boolean, false));
exception when others then return jsonb_build_object('step', v);
end $$;

-- =====================================================================
-- mk_state: tampilan gabungan (klien memakai satu mesin langkah 1-60)
-- =====================================================================
do $$
begin
  drop function if exists game.mk_state_mk2(uuid);
  alter function game.mk_state(uuid) rename to mk_state_mk2;
end $$;
revoke all on function game.mk_state_mk2(uuid) from public, anon, authenticated;

create or replace function game.mk_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare s jsonb; v int;
begin
  s := game.mk_state_mk2(p_pid);
  if s is null or coalesce((s ->> 'step')::int, 0) < 40 then return s; end if;
  begin
    if not game.mk2_eligible(p_pid) then return s; end if;
    v := game.mk2_step(p_pid);
    return s || jsonb_build_object('step', 40 + v, 'ada', 40 + game.mk2_ada(), 'last', 40 + game.mk2_ada(),
      'd', game.mk2_steps() -> v, 'mk2', game.mk2_view(p_pid));
  exception when others then return s;
  end;
end $$;

-- =====================================================================
-- Battle Akhir Bersama: 8 gelombang dalam satu rangkaian
--   0 KPD Tembok Utara · 1 KPD Tembok Selatan            -> langkah 58 selesai
--   2-4 Armada Pemburu "Algojo" (sekutu menembak)         -> langkah 59 selesai
--   5-7 Sovereign Mahkota fase 1-3 (HP tersimpan)         -> menang, pilihan mahkota (langkah 60)
-- =====================================================================
create or replace function game.mk2_enc(p_pid uuid, p_w int) returns jsonb
language plpgsql volatile as $$
declare ammo numeric := game.ww_ammo(p_pid); d jsonb := game.mk2_data(p_pid); mx numeric := greatest(1000, game.cfg_num('MkFlagshipHp', 6000));
  hp numeric; k numeric := greatest(0.2, game.cfg_num('Mk2BossDmgKali', 1)); base jsonb;
  algojo text[] := array['Algojo "Sayap Kiri"', 'Algojo "Sayap Kanan"', 'Algojo "Komando Tengah"'];
  sekutu text[] := array['Salvo meriam Bang Rimba', 'Armada Skitraw di bawah Hasiolan', 'Petrik dengan Sayap Tempa'];
begin
  base := jsonb_build_object('mk2b', true, 'boss', 'mk2', 'w', p_w, 'rolledAt', game.iso(now()), 'round', 1, 'navyLook', true, 'shipLook', case when p_w >= 5 then jsonb_build_object('masts', 3, 'hull', '#141018', 'trim', '#e0b84a', 'sail', '#1e1a26', 'flag', '#0c0a10', 'flagShape', 'swallow', 'emblem', 'crest', 'emblemColor', '#e0b84a', 'pennant', '#e0b84a', 'ports', 7, 'muzzles', true, 'railGuns', true, 'chaser', true, 'gilded', true, 'gildLine', true, 'gunDeck2', true, 'sizeK', 1.34, 'studding', 2, 'royal', true)
      else jsonb_build_object('masts', 3, 'hull', '#1c2438', 'trim', '#9fb4d8', 'sail', '#34476e', 'flag', '#14203a', 'flagShape', 'rect', 'emblem', 'crest', 'emblemColor', '#c9d6f0', 'pennant', '#2a4a8a', 'ports', 7, 'muzzles', true, 'railGuns', true, 'copper', true, 'sizeK', 1.2) end,
    'maxAmmo', ammo, 'ammoRemaining', ammo, 'softSink', true, 'retreatOk', true, 'retreat', true,
    'noTalkMsg', 'Tidak ada yang mau berunding di Teluk Dalam hari ini, Kapten. Hanya meriam yang bicara.',
    'retreatMsg', 'Armada aliansi menutupi manuvermu. Kau mundur ke dermaga Rantai Lama untuk berbenah.',
    'softSinkMsg', 'Lambungmu jebol! Black Pearl menyeretmu mundur ke dermaga Rantai Lama. Perbaiki kapal, lalu kembali ke barisan.');
  if p_w <= 1 then
    return base || jsonb_build_object('enemyName', case when p_w = 0 then 'KPD Tembok Utara' else 'KPD Tembok Selatan' end,
      'bossTitle', 'Gugus Tugas "Tembok Mahkota" ' || (p_w + 1) || '/2 - barikade mulut Teluk Dalam',
      'displayLevel', 9, 'enemyLevel', 8, 'enemyMaxHp', 1400, 'enemyHp', 1400, 'dmgTaken', 0.5, 'enemyDmgMul', 2.6 * k)
      || case when p_w = 1 then jsonb_build_object('punishReload', 1.5) else '{}'::jsonb end;
  end if;
  if p_w <= 4 then
    return base || jsonb_build_object('enemyName', algojo[p_w - 1],
      'bossTitle', 'Armada Pemburu "Algojo" ' || (p_w - 1) || '/3 - mengepung dari tengah palung',
      'displayLevel', 9, 'enemyLevel', 8, 'enemyMaxHp', 1600, 'enemyHp', 1600, 'dmgTaken', 0.45, 'enemyDmgMul', 2.8 * k,
      'allyDmg', 160, 'allyNote', sekutu[p_w - 1], 'noRam', false);
  end if;
  hp := least(mx, greatest(1, coalesce((d ->> 'baHp')::numeric, mx)));
  if p_w = 5 then
    return base || jsonb_build_object('enemyName', 'Sovereign Mahkota', 'phase', 1,
      'bossTitle', 'Kumis Hitam - fase 1/3: Perisai Arus Kuno', 'displayLevel', 10, 'enemyLevel', 9,
      'enemyMaxHp', mx, 'enemyHp', greatest(hp, round(mx * 2 / 3) + 1), 'hpFloor', round(mx * 2 / 3),
      'dmgTaken', 0.4, 'shield', true, 'shieldMul', 0.5, 'enemyDmgMul', 2.5 * k, 'noRam', true,
      'noRamMsg', 'Pusaran Mahkota Karam memutar haluanmu sebelum sempat menabrak.');
  elsif p_w = 6 then
    return base || jsonb_build_object('enemyName', 'Sovereign Mahkota', 'phase', 2,
      'bossTitle', 'Kumis Hitam - fase 2/3: Murka Stempel Mutlak', 'displayLevel', 10, 'enemyLevel', 9,
      'enemyMaxHp', mx, 'enemyHp', least(round(mx * 2 / 3), greatest(hp, round(mx * 0.3) + 1)), 'hpFloor', round(mx * 0.3),
      'dmgTaken', 0.4, 'enemyDmgMul', 3.4 * k, 'noRam', true, 'allyDmg', 60, 'allyNote', 'Ratu Marlya dengan Pengacau Frekuensi');
  end if;
  return base || jsonb_build_object('enemyName', 'Sovereign Mahkota', 'phase', 3,
    'bossTitle', 'Kumis Hitam - fase 3/3: Tembakan Penghabisan Bersama', 'displayLevel', 10, 'enemyLevel', 9,
    'enemyMaxHp', mx, 'enemyHp', least(round(mx * 0.3), hp),
    'dmgTaken', 0.4, 'enemyDmgMul', 2.0 * k, 'noRam', true, 'allyDmg', 320, 'allyNote', 'Seluruh aliansi (Black Pearl, Marlya, Hasiolan, Bang Rimba, Petrik, cangcimen)');
end $$;

create or replace function game.mk2_boss_defeated(p_pid uuid) returns jsonb
language plpgsql as $$
declare enc jsonb; w int; v_next jsonb; v_msg text; v_step int;
begin
  select pending_encounter into enc from game.player_location where player_id = p_pid;
  if jsonb_typeof(enc) <> 'object' or not coalesce((enc ->> 'mk2b')::boolean, false) then return null; end if;
  w := coalesce((enc ->> 'w')::int, 0);
  select step into v_step from game.player_quests where player_id = p_pid and quest_id = 'mahkota2' for update;
  if v_step is null or v_step < 17 then return null; end if;

  if w = 7 then
    update game.player_quests set data = (data - 'baHp') || jsonb_build_object('ba', 8, 'menang', true, 'baHp', 0), updated_at = now()
     where player_id = p_pid and quest_id = 'mahkota2';
    perform game.log(p_pid, 'Sovereign Mahkota karam di Palung Arus Mati. Mahkota Karam retak terbelah.');
    return jsonb_build_object('gold', 0, 'event', 'mk2_menang', 'arrive', true,
      'message', 'Hujan tembakan seluruh aliansi menghantam anjungan. Mahkota Karam di kepala Kumis Hitam retak terbelah, dan Sovereign Mahkota miring pelan ke Palung Arus Mati. Arus teluk berhenti berputar.');
  end if;

  update game.player_quests set
      step = case when w = 1 then greatest(step, 18) when w = 4 then greatest(step, 19) else step end,
      data = (case when w >= 5 then data || jsonb_build_object('baHp', case w when 5 then round(greatest(1000, game.cfg_num('MkFlagshipHp', 6000)) * 2 / 3)
                                                                            else round(greatest(1000, game.cfg_num('MkFlagshipHp', 6000)) * 0.3) end)
                  else data - 'baHp' end)
             || jsonb_build_object('ba', w + 1, 's' || (case when w = 1 then 58 when w = 4 then 59 else 0 end), game.now_ms()) - 's0',
      updated_at = now()
   where player_id = p_pid and quest_id = 'mahkota2';
  v_next := game.mk2_enc(p_pid, w + 1);
  v_msg := case w
    when 0 then 'KPD Tembok Utara patah tiangnya dan terseret arus. Di belakangnya, KPD Tembok Selatan memutar meriam jarak jauhnya. cangcimen di corong: "Barisan Pacu, potong zona bidiknya!"'
    when 1 then 'Barikade selat bersih! cangcimen lewat corong: "Tapi tiga kapal Algojo mengepung dari tengah pusaran - tahan posisi, Kapten!" Dari kabut timur, armada Skitraw muncul; dari selatan, meriam Armada Bebas dan Sayap Tempa.'
    when 2 then 'Algojo "Sayap Kiri" terbakar dan miring. Hasiolan: "Satu jatuh! Sayap kanan, Bang Rimba!"'
    when 3 then 'Algojo "Sayap Kanan" karam ditelan arus. Petrik memotong haluan kapal komando dengan Sayap Tempa.'
    when 4 then 'Kapal komando Algojo tumbang. Hasiolan: "Sayap mereka runtuh! Di depanmu kapal induk Sovereign Mahkota - Kumis Hitam sudah mengenakan Mahkota Karam!"'
    when 5 then 'Ratu Marlya mendekat dengan Pengacau Frekuensi di haluan. Gelombang balik M.A.R.I.E. menghantam pusaran: Perisai Arus Kuno runtuh! "Aku yang membuatkan mesinnya. Biar aku yang mematikannya."'
    else 'Salvo Mahkota merobek lambungmu - lalu Black Pearl menerjang masuk di sisimu dan menahan meriam utama dengan lambungnya sendiri. zafachmie berteriak: "Untuk Andry!" Meriam rantainya melumpuhkan kemudi Sovereign Mahkota. Seluruh aliansi mengepung.' end;
  if w = 1 then perform game.log(p_pid, 'Mahkota: langkah 58 selesai (barikade selat bersih).'); end if;
  if w = 4 then perform game.log(p_pid, 'Mahkota: langkah 59 selesai (armada Algojo tumbang).'); end if;
  return jsonb_build_object('gold', 0, 'event', 'mk2_gelombang', 'w', w + 1, 'chain', v_next, 'message', v_msg);
end $$;

do $$
begin
  drop function if exists game.quest_boss_defeated_mk2(uuid);
  alter function game.quest_boss_defeated(uuid) rename to quest_boss_defeated_mk2;
  drop function if exists game.quest_combat_end_mk2(uuid, jsonb, text);
  alter function game.quest_combat_end(uuid, jsonb, text) rename to quest_combat_end_mk2;
end $$;
create or replace function game.quest_boss_defeated(p_pid uuid) returns jsonb
language sql as $$ select coalesce(game.mk2_boss_defeated(p_pid), game.quest_boss_defeated_mk2(p_pid)) $$;

-- HP Sovereign Mahkota tersimpan saat mundur / kalah (gelombang lain diulang utuh)
create or replace function game.quest_combat_end(p_pid uuid, p_enc jsonb, p_result text) returns void
language plpgsql as $$
begin
  perform game.quest_combat_end_mk2(p_pid, p_enc, p_result);
  begin
    if jsonb_typeof(p_enc) = 'object' and coalesce((p_enc ->> 'mk2b')::boolean, false) and p_result <> 'won'
       and coalesce((p_enc ->> 'w')::int, 0) >= 5 then
      update game.player_quests set data = data || jsonb_build_object('baHp', game.voy_num(p_enc -> 'enemyHp')), updated_at = now()
       where player_id = p_pid and quest_id = 'mahkota2';
    end if;
  exception when others then null;
  end;
end $$;

-- =====================================================================
-- NAVY SAGA 4 (langkah 42-59): pencegatan pelayaran
-- =====================================================================
create or replace function game.mk2_navy_enc(p_pid uuid, p_tier int, p_ke int default 1) returns jsonb
language plpgsql volatile as $$
declare ammo numeric := game.ww_ammo(p_pid); hp numeric; k numeric := greatest(0.2, game.cfg_num('MkNavyDmgKali', 1)); e jsonb;
begin
  hp := greatest(100, game.cfg_num('MkNavyHp' || p_tier, case p_tier when 1 then 600 when 2 then 1000 when 3 then 1600 else 1400 end));
  e := jsonb_build_object('navyLook', true, 'kind', 'navy', 'mk2navy', p_tier, 'ke', p_ke, 'rolledAt', game.iso(now()), 'round', 1, 'shipLook', jsonb_build_object('masts', 3, 'hull', '#1c2438', 'trim', '#9fb4d8', 'sail', '#34476e', 'flag', '#14203a', 'flagShape', 'rect', 'emblem', 'crest', 'emblemColor', '#c9d6f0', 'pennant', '#2a4a8a', 'ports', 6, 'muzzles', true, 'railGuns', true, 'bands', true, 'copper', true, 'sizeK', 1.12),
    'maxAmmo', ammo, 'ammoRemaining', ammo, 'enemyMaxHp', hp, 'enemyHp', hp,
    'noTalk', true, 'noTalkMsg', 'Bendera biru tua berkibar: darurat militer Kumis Hitam. Tidak ada suap, tidak ada runding.',
    'noFleeMsg', 'Kapal-kapal Navy menutup jalur di depan dan di belakang. Tidak ada celah untuk kabur.',
    'softSink', true,
    'softSinkMsg', 'Lambungmu jebol di bawah gempuran Navy! Kapalmu terseret arus kembali ke pelabuhan asal. Muatan dan gold aman, tapi kapal harus diperbaiki.');
  if p_tier = 1 then
    return e || jsonb_build_object('enemyName', 'Patroli Stempel Biru', 'bossTitle', 'Navy Pemerintah Dunia - Tier 1',
      'enemyLevel', 5, 'dmgTaken', 1.0, 'enemyDmgMul', 1.6 * k);
  elsif p_tier = 2 then
    return e || jsonb_build_object('enemyName', 'Skuadron Tinta Besi', 'bossTitle', 'Navy Pemerintah Dunia - Tier 2',
      'enemyLevel', 6, 'dmgTaken', 0.85, 'enemyDmgMul', 2.2 * k);
  elsif p_tier = 3 then
    return e || jsonb_build_object('enemyName', 'Armada Pemburu "Algojo"', 'bossTitle', 'Navy Pemerintah Dunia - Tier 3',
      'enemyLevel', 7, 'dmgTaken', 0.7, 'enemyDmgMul', 2.8 * k, 'punishReload', 1.5, 'immuneFirst', true,
      'immuneMsg', 'tembakan pertamamu pecah di perisai gelombang M.A.R.I.E. mini milik Algojo.');
  end if;
  return e || jsonb_build_object('enemyName', case when p_ke = 1 then 'KPD Tembok Timur' else 'KPD Tembok Barat' end,
    'bossTitle', 'Gugus Tugas "Tembok Mahkota" - kapal ' || p_ke || '/2', 'enemyLevel', 8, 'dmgTaken', 0.6, 'enemyDmgMul', 3.2 * k);
end $$;

create or replace function game.mk2_navy_roll(p_pid uuid) returns jsonb
language plpgsql volatile as $$
declare t int; l game.player_location; d jsonb; v_tony boolean := false;
begin
  t := game.mk2_navy_tier(p_pid);
  if t = 0 then return null; end if;
  select * into l from game.player_location where player_id = p_pid;
  if coalesce(l.destination_city_id, '') = '' then return null; end if;
  begin v_tony := (game.tony_active(l.city_id, l.destination_city_id)).id is not null; exception when others then v_tony := false; end;
  if v_tony then return null; end if;
  d := game.mk2_steps() -> game.mk2_step(p_pid);
  if not (d ? 'c' and d ->> 'c' = l.destination_city_id) and random() * 100 >= game.cfg_num('MkNavyPct', 50) then
    return null;
  end if;
  return game.mk2_navy_enc(p_pid, t, 1);
end $$;

do $$
begin
  drop function if exists game.kd_enc_mk2(uuid, jsonb);
  alter function game.kd_enc(uuid, jsonb) rename to kd_enc_mk2;
end $$;
-- Prioritas: bos quest > Tony and Gank > Navy Saga 4 > patroli / bajak laut acak
create or replace function game.kd_enc(p_pid uuid, p_enc jsonb) returns jsonb
language plpgsql as $$
declare c jsonb;
begin
  if p_enc is null or jsonb_typeof(p_enc) <> 'object' or coalesce((p_enc ->> 'randomPirate')::boolean, false) then
    begin c := game.mk2_navy_roll(p_pid); exception when others then c := null; end;
    if c is not null then return c; end if;
  end if;
  return game.kd_enc_mk2(p_pid, p_enc);
end $$;

-- Pertempuran Navy: kabur dikunci, kapal kedua Tier 4, jarahan Keping + bonus gold per tier
do $$
begin
  drop function if exists game.api_resolvecombat_mk2(jsonb);
  alter function public.api_resolvecombat(jsonb) rename to api_resolvecombat_mk2;
  alter function public.api_resolvecombat_mk2(jsonb) set schema game;
end $$;
revoke all on function game.api_resolvecombat_mk2(jsonb) from public, anon, authenticated;

create or replace function game.mk2_navy_hadiah(p_pid uuid, p_tier int) returns jsonb
language plpgsql as $$
declare v_hari int := game.game_day(); d jsonb; v_n int; v_k int; v_lo int; v_gold bigint; v_menang int;
begin
  select data into d from game.player_quests where player_id = p_pid and quest_id = 'mahkota2' for update;
  d := coalesce(d, '{}'::jsonb);
  v_n := case when (d -> 'nk' ->> 'h') = v_hari::text then coalesce((d -> 'nk' ->> 'n')::int, 0) else 0 end;
  v_lo := p_tier * 2 - 1;                                     -- T1 1-2 · T2 3-4 · T3 5-6 · T4 7-8
  v_k := case when v_n >= greatest(0, game.cfg_num('MkNavyKepingCap', 40))::int then 1 else v_lo + floor(random() * 2)::int end;
  -- Gold Proporsional: jarahan inti (200 x level) sudah dibayar; tier tinggi dapat tambahan
  v_gold := round(game.cfg_num('CombatLootGoldPerLevel', 200) * (4 + p_tier) * (case p_tier when 1 then 0 when 2 then 0.5 when 3 then 1 else 2 end))::bigint;
  v_menang := coalesce((d ->> 'navyMenang')::int, 0) + 1;
  perform game.keping_add(p_pid, v_k, 'mk2navy', 'Navy Tier ' || p_tier);
  if v_gold > 0 then update game.players set gold = gold + v_gold where player_id = p_pid; end if;
  update game.player_quests set data = data || jsonb_build_object('nk', jsonb_build_object('h', v_hari, 'n', v_n + v_k), 'navyMenang', v_menang), updated_at = now()
   where player_id = p_pid and quest_id = 'mahkota2';
  return jsonb_build_object('keping', v_k, 'gold', v_gold, 'navyMenang', v_menang);
end $$;

create or replace function public.api_resolveCombat(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); enc jsonb; r jsonb; t int; h jsonb; nx jsonb; l game.player_location;
begin
  select pending_encounter into enc from game.player_location where player_id = v_pid;
  if jsonb_typeof(enc) <> 'object' or coalesce(enc ->> 'kind', '') <> 'navy' then
    return game.api_resolvecombat_mk2(a);
  end if;
  if game.arg(a, 0) = 'flee' then raise exception '%', enc ->> 'noFleeMsg'; end if;
  t := coalesce((enc ->> 'mk2navy')::int, 1);
  r := game.api_resolvecombat_mk2(a);
  if coalesce((r ->> 'ongoing')::boolean, false) or r ->> 'result' is distinct from 'won' then return r; end if;
  -- Tier 4: kapal kedua langsung maju (pelayaran semu ke pelabuhan yang sama, pola Pusaran Q4)
  if t = 4 and coalesce((enc ->> 'ke')::int, 1) = 1 then
    select * into l from game.player_location where player_id = v_pid for update;
    nx := game.mk2_navy_enc(v_pid, 4, 2);
    update game.player_location set destination_city_id = l.city_id, depart_at = now() - interval '1 second', arrive_at = now(),
        pending_encounter = nx where player_id = v_pid;
    return jsonb_build_object('ongoing', true, 'chained', true, 'success', true, 'result', 'won',
      'message', coalesce(r ->> 'message', '') || ' Belum sempat bernapas, kapal kedua Gugus Tugas "Tembok Mahkota" menutup jalur!',
      'encounter', nx, 'voyage', game.voyage_state(v_pid),
      'newCondition', game.ship_json(v_pid) -> 'Condition', 'newGold', (select gold from game.players where player_id = v_pid));
  end if;
  begin
    h := game.mk2_navy_hadiah(v_pid, t);
    r := r || jsonb_build_object('message', coalesce(r ->> 'message', '') ||
        case when (h ->> 'gold')::bigint > 0 then ' Kas perang Navy ikut terjarah: +' || (h ->> 'gold') || ' gold.' else '' end ||
        ' +' || (h ->> 'keping') || ' Keping Rantau.',
      'keping', (h ->> 'keping')::int, 'navyMenang', (h ->> 'navyMenang')::int,
      'newGold', (select gold from game.players where player_id = v_pid));
  exception when others then null;
  end;
  return r;
end $$;
select game.expose('api_resolvecombat');

-- =====================================================================
-- Kedai: rupa "Takhta Bebas" (hadiah tamat, tidak dijual)
-- =====================================================================
insert into game.kd_items(id, rak, slot, set_id, name, rarity, price, price_admin, info, tokoh, req, exclusive, active, sort)
values ('layar_takhta_bebas', 'rupa', 'layar', null, 'Layar Hitam-Emas "Takhta Bebas"', 'legenda', 0, null,
        'Layar hitam berpinggir emas dari kain bendera Sovereign Mahkota. Hanya untuk kapten yang menumbangkan Mahkota Karam.',
        'Kumis Hitam', null, true, true, 397)
on conflict (id) do update set
  rak = excluded.rak, slot = excluded.slot, name = excluded.name, rarity = excluded.rarity,
  price = excluded.price, info = excluded.info, tokoh = excluded.tokoh,
  exclusive = excluded.exclusive, active = excluded.active, sort = excluded.sort;

-- =====================================================================
-- api_mahkota: langkah 41-60 lewat mk2_act, sisanya ke versi lama
-- =====================================================================
do $$
begin
  drop function if exists game.api_mahkota_mk2(jsonb);
  alter function public.api_mahkota(jsonb) rename to api_mahkota_mk2;
  alter function public.api_mahkota_mk2(jsonb) set schema game;
end $$;
revoke all on function game.api_mahkota_mk2(jsonb) from public, anon, authenticated;

create or replace function game.mk2_act(a jsonb) returns jsonb
language plpgsql as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status');
  v_want int := game.arg_int(a, 1);
  v_res text := lower(btrim(coalesce(game.arg(a, 2), '')));
  v_step int; v_data jsonb; d jsonb; v_city text; v_gold bigint := 0; b record; v_kurang text := '';
  v_cicil jsonb; v_ambil int; v_sisa int; v_lengkap boolean := true; v_dari jsonb := '{}'::jsonb;
  t jsonb; h jsonb; v_id uuid; enc jsonb; v_w int; v_tamat boolean := false;
begin
  if v_act not in ('maju', 'setor', 'balap', 'selesai', 'serang', 'pilih') then raise exception 'Aksi tidak dikenal.'; end if;
  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;

  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'mahkota2', 0, '{}'::jsonb)
  on conflict (player_id, quest_id) do nothing;
  select step, data into v_step, v_data from game.player_quests where player_id = v_pid and quest_id = 'mahkota2' for update;
  v_data := coalesce(v_data, '{}'::jsonb);

  if v_step >= game.mk2_ada() then raise exception 'Laut ini sudah bebas, Kapten.'; end if;
  if v_want is null or v_want <> 40 + v_step then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;
  d := game.mk2_steps() -> v_step;
  v_city := game.current_city(v_pid);
  if d ? 'c' and v_city is distinct from (d ->> 'c') then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;

  -- ---------------- setoran barang ----------------
  if v_act = 'setor' then
    if d ? 'bahan' then
      if coalesce((v_data ->> ('bahan' || (d ->> 'n')))::boolean, false) then
        return jsonb_build_object('mahkota', game.mk_state(v_pid), 'setor', true, 'lengkap', true);
      end if;
      for b in select key as id, value::text::int as n from jsonb_each(d -> 'bahan') loop
        if game.item_qty(v_pid, b.id) < b.n then
          v_kurang := v_kurang || case when v_kurang = '' then '' else ', ' end ||
            (b.n - game.item_qty(v_pid, b.id))::text || ' ' || coalesce((select name from game.commodities where id = b.id), b.id);
        end if;
      end loop;
      if v_kurang <> '' then raise exception 'Barangnya masih kurang, Kapten: %.', v_kurang; end if;
      for b in select key as id, value::text::int as n from jsonb_each(d -> 'bahan') loop
        perform game.adjust_inventory(v_pid, b.id, -b.n);
      end loop;
      v_data := v_data || jsonb_build_object('bahan' || (d ->> 'n'), true);
      update game.player_quests set data = v_data, updated_at = now() where player_id = v_pid and quest_id = 'mahkota2';
      if d ? 'g' then
        return jsonb_build_object('mahkota', game.mk_state(v_pid), 'setor', true, 'lengkap', true);
      end if;
      v_res := 'ok';   -- tanpa mini game: setoran langsung menutup langkah
    elsif d ? 'cicil' then
      v_cicil := coalesce(v_data -> 'cicil', '{}'::jsonb);
      for b in select key as id, value::text::int as n from jsonb_each(d -> 'cicil') loop
        v_sisa := greatest(0, b.n - coalesce((v_cicil ->> b.id)::int, 0));
        v_ambil := least(v_sisa, game.item_qty(v_pid, b.id));
        if v_ambil > 0 then
          perform game.adjust_inventory(v_pid, b.id, -v_ambil);
          v_cicil := v_cicil || jsonb_build_object(b.id, coalesce((v_cicil ->> b.id)::int, 0) + v_ambil);
          v_dari := v_dari || jsonb_build_object(b.id, v_ambil);
        end if;
        if coalesce((v_cicil ->> b.id)::int, 0) < b.n then v_lengkap := false; end if;
      end loop;
      update game.player_quests set data = data || jsonb_build_object('cicil', v_cicil), updated_at = now()
       where player_id = v_pid and quest_id = 'mahkota2';
      if not v_lengkap then
        if v_dari = '{}'::jsonb then raise exception 'Palkamu belum membawa ransum yang diminta, Kapten.'; end if;
        return jsonb_build_object('mahkota', game.mk_state(v_pid), 'setor', true, 'lengkap', false, 'masuk', v_dari, 'cicil', v_cicil);
      end if;
      v_res := 'ok';
    else
      raise exception 'Tidak ada yang perlu disetor di sini, Kapten.';
    end if;
  end if;

  -- ---------------- Trektrek-an Kilat (langkah 58) ----------------
  if v_act = 'balap' then
    if not (d ? 'race') then raise exception 'Tidak ada balapan di langkah ini, Kapten.'; end if;
    if coalesce((v_data ->> 'kilat')::boolean, false) then raise exception 'Barisan Pacu sudah menembus zona bidik, Kapten. Serbu barikadenya!'; end if;
    t := game.trek_mulai(v_pid, 'turnamen', d ->> 'race', game.trek_kapal(v_pid));
    return jsonb_build_object('trek', t, 'mahkota', game.mk_state(v_pid));
  end if;
  if v_act = 'selesai' then
    if not (d ? 'race') then raise exception 'Tidak ada balapan di langkah ini, Kapten.'; end if;
    begin v_id := game.arg(a, 2)::uuid; exception when others then raise exception 'Balapan tidak ditemukan.'; end;
    h := game.trek_selesai(v_pid, v_id, case when jsonb_typeof(a) = 'array' then a -> 3 end, 'turnamen');
    if coalesce((h ->> 'win')::boolean, false) then
      update game.player_quests set data = data || jsonb_build_object('kilat', true), updated_at = now()
       where player_id = v_pid and quest_id = 'mahkota2';
    end if;
    return jsonb_build_object('hasil', h, 'mahkota', game.mk_state(v_pid), 'maju', false, 'kilat', coalesce((h ->> 'win')::boolean, false));
  end if;

  -- ---------------- Battle Akhir Bersama (langkah 58-60) ----------------
  if v_act = 'serang' then
    if not coalesce((d ->> 'perang')::boolean, false) then raise exception 'Belum saatnya menyerbu, Kapten.'; end if;
    if d ? 'race' and not coalesce((v_data ->> 'kilat')::boolean, false) then raise exception 'Tembus dulu zona bidik meriamnya bersama Barisan Pacu, Kapten.'; end if;
    if coalesce((v_data ->> 'menang')::boolean, false) then raise exception 'Sovereign Mahkota sudah karam, Kapten.'; end if;
    if jsonb_typeof((select pending_encounter from game.player_location where player_id = v_pid)) = 'object' then
      raise exception 'Pertempuran masih berlangsung.';
    end if;
    v_w := greatest(coalesce((v_data ->> 'ba')::int, 0), case v_step when 18 then 2 when 19 then 5 else 0 end);
    enc := game.mk2_enc(v_pid, v_w);
    update game.player_location set destination_city_id = v_city, depart_at = now() - interval '1 second', arrive_at = now(),
        pending_encounter = enc where player_id = v_pid;
    perform game.log(v_pid, 'Battle Akhir Bersama: menyerbu ' || (enc ->> 'enemyName') || '.');
    return jsonb_build_object('mahkota', game.mk_state(v_pid), 'encounter', enc, 'voyage', game.voyage_state(v_pid));
  end if;

  -- ---------------- pilihan nasib Mahkota Karam (langkah 60) ----------------
  if v_act = 'pilih' then
    if not (d ? 'pilih') then raise exception 'Tidak ada yang harus dipilih di sini, Kapten.'; end if;
    if not coalesce((v_data ->> 'menang')::boolean, false) then raise exception 'Sovereign Mahkota masih berdiri, Kapten.'; end if;
    if not (d -> 'pilih' @> to_jsonb(v_res)) then raise exception 'Pilihan tidak dikenali.'; end if;
    update game.player_quests set data = data || jsonb_build_object('mahkota', v_res) where player_id = v_pid and quest_id = 'mahkota2';
    v_res := 'ok';
  elsif d ? 'pilih' and v_act = 'maju' then
    raise exception 'Keputusannya ada di tanganmu, Kapten.';
  end if;

  -- ---------------- syarat maju ----------------
  if v_act = 'maju' then
    if coalesce((d ->> 'perang')::boolean, false) then raise exception 'Armada musuh masih berdiri, Kapten.'; end if;
    if d ? 'cicil' then raise exception 'Setor dulu ransumnya, Kapten.'; end if;
    if d ? 'bahan' and not coalesce((v_data ->> ('bahan' || (d ->> 'n')))::boolean, false) then raise exception 'Serahkan dulu barangnya, Kapten.'; end if;
    if d ? 'g' and v_res not in ('ok', 'menang') then raise exception 'Belum berhasil, Kapten. Coba lagi.'; end if;
  end if;

  -- ---------------- hadiah & penutup ----------------
  if d ? 'gold' then
    v_gold := greatest(0, game.cfg_num(d ->> 'gold', 0))::bigint;
    if v_gold > 0 then update game.players set gold = gold + v_gold where player_id = v_pid; end if;
  end if;
  if coalesce((d ->> 'tamat')::boolean, false) then
    v_tamat := true;
    update game.player_quests set done_at = now() where player_id = v_pid and quest_id = 'mahkota2';
    begin perform game.kd_grant(v_pid, 'layar_takhta_bebas', 1, 'mahkota2'); exception when others then null; end;
    perform game.log(v_pid, 'Saga Keempat lengkap: Mahkota Karam tumbang di Teluk Dalam Rantai Lama.');
  end if;

  update game.player_quests set step = v_step + 1, updated_at = now(),
    data = data || jsonb_build_object('s' || (41 + v_step), game.now_ms())
   where player_id = v_pid and quest_id = 'mahkota2';
  if not v_tamat then perform game.log(v_pid, 'Mahkota: langkah ' || (41 + v_step) || ' selesai.'); end if;

  return jsonb_build_object('mahkota', game.mk_state(v_pid), 'maju', true, 'gold', v_gold,
    'tanda', d ->> 'tanda', 'tamat', v_tamat, 'newGold', (select gold from game.players where player_id = v_pid));
end $$;
revoke all on function game.mk2_act(jsonb) from public, anon, authenticated;

create or replace function public.api_mahkota(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid();
begin
  if coalesce(game.arg(a, 0), 'status') <> 'status' and v_pid is not null
     and game.mk_step(v_pid) >= 40 and game.mk2_eligible(v_pid) then
    return game.mk2_act(a);
  end if;
  return game.api_mahkota_mk2(a);
end $$;
select game.expose('api_mahkota');

-- =====================================================================
-- Kedai: barang ber-syarat mahkota2 (cadangan bila ada barang baru yang dijual)
-- =====================================================================
do $$
begin
  drop function if exists game.kd_req_ok_mk2(uuid, text);
  alter function game.kd_req_ok(uuid, text) rename to kd_req_ok_mk2;
end $$;
create or replace function game.kd_req_ok(p_pid uuid, p_id text) returns boolean
language plpgsql stable as $$
declare r jsonb;
begin
  select i.req into r from game.kd_items i where i.id = p_id;
  if r is not null and r ? 'mahkota2' then return game.mk2_tamat(p_pid); end if;
  return game.kd_req_ok_mk2(p_pid, p_id);
end $$;

-- =====================================================================
-- Alat GM:  select game.admin_mahkota2('abuy', 47);   -- langkah 40..60 (40 = baru boleh mulai, tanpa jeda)
-- =====================================================================
create or replace function game.admin_mahkota2(p_username text, p_langkah int) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid; s int;
begin
  select player_id into v_pid from game.players where lower(username) = lower(p_username);
  if v_pid is null then raise exception 'Pemain % tidak ditemukan.', p_username; end if;
  s := greatest(0, least(game.mk2_ada(), coalesce(p_langkah, 40) - 40));
  insert into game.player_quests(player_id, quest_id, step, data, done_at) values (v_pid, 'mahkota', 40, '{}'::jsonb, now())
  on conflict (player_id, quest_id) do update set step = greatest(game.player_quests.step, 40),
    done_at = coalesce(game.player_quests.done_at, now()), updated_at = now();
  update game.mh_player set krisis = false, tembus = false, gelap = false, paksa = false, aman = false,
    zona_tuju = null, gelap_city = null, updated_at = now() where player_id = v_pid;
  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'mahkota2', s,
      case when s >= 18 then '{"kilat":true}'::jsonb else '{}'::jsonb end)
  on conflict (player_id, quest_id) do update set step = s, updated_at = now(), done_at = null,
    data = (game.player_quests.data - 'menang' - 'baHp') || jsonb_build_object('ba', case when s >= 19 then 5 when s >= 18 then 2 else 0 end,
      'kilat', s >= 18);
  return game.mk_state(v_pid);
end $$;
revoke all on function game.admin_mahkota2(text, int) from public, anon, authenticated;

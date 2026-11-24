-- =====================================================================
-- 0103 · Saga 4 Bagian II: pertempuran di tengah laut + Medan Tempur Teluk Dalam (Tide v83)
--
--   Langkah 54 -> 55  Ransum penuh -> kartu zafachmie -> Hadiah Q21 -> kapal otomatis berlayar ke
--                     Pelabuhan Rantai Lama. +3 dtk setelah berangkat: Navy Tier 4 (dua kapal) mencegat
--                     DI TENGAH LAUT. Menang -> pelayaran berlanjut, sinematik 1,5 dtk sebelum sandar.
--                     Kalah -> terseret ke pelabuhan asal, berlayar lagi untuk mencoba.
--   Langkah 57        Dewan Perang -> "Kita semua menunggumu di Galangan!"
--   Langkah 58        Galangan Rantai Lama -> "Pimpin Barisan Depan" -> kapal otomatis berlayar ke titik
--                     baru "Medan Tempur Teluk Dalam" (kiri Zentul, di atas Gading Island).
--                     +5 dtk: Gelombang 1 = KPD Tembok Utara -> Trektrek-an Kilat -> KPD Tembok Selatan.
--                     Kalah / gagal di mana pun -> kapal kembali ke Rantai Lama, Gelombang 1 diulang dari Galangan.
--   Langkah 59        Lolos Gelombang 1 -> pelayaran berlanjut, +5 dtk: 3 kapal Algojo (sekutu menembak).
--                     Kalah -> kembali ke Rantai Lama, ulang Gelombang 2 dari Galangan (Gelombang 1 tetap lolos).
--   Langkah 60        Tiba di Medan Tempur Teluk Dalam -> duel armada 4 lawan 4 (realtime, tanpa batas waktu,
--                     last man standing) -> Pilihan Akhir Mahkota -> Ending Sinematik -> Hadiah Q22.
--
--   Mesin "laut" (data mahkota2):
--     laut  {w, dest, at?}  w = blokade | g1 | kilat | g1b | g2  (at = ms kapan pencegatan muncul)
--     jeda  {jalan, sisa}   potret waktu pelayaran saat pencegatan muncul; dipakai saat pelayaran berlanjut
--   Pencegatan memakai jalur bos berantai (quest_boss_defeated -> 'chain'), jadi pelayaran TIDAK selesai
--   saat menang; api_resolveCombat (bungkus _tdl) menghapus penanda lanjut dan menyambung waktu pelayaran.
--
--   Titik kait (pola bungkus, akhiran _tdl):
--     resolve_arrival_if_due · quest_arrival_redirect · quest_boss_defeated · quest_combat_end · kd_enc
--     api_setSail · api_resolveCombat · mk2_act · mk2_view · city_open · player_unlocks · spot_city
--     voy_far_city · city_flavor · admin_mahkota2 (dibuat ulang)
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('Mk2CegatDetik55', '3'),        -- detik setelah berangkat sampai Navy Tier 4 mencegat (langkah 55)
  ('Mk2CegatDetikTeluk', '5'),     -- detik pelayaran sebelum Gelombang 1 / Gelombang 2
  ('MkArenaMinDetik', '30'),       -- duel armada paling cepat sekian detik (pagar laporan menang)
  ('MkArenaSovHp', '2600'),        -- HP Sovereign Mahkota di duel armada
  ('MkArenaNavyHp', '950'),        -- HP tiap kapal Navy pengawal
  ('MkArenaSekutuHp', '1700'),     -- HP tiap kapal sekutu (Black Pearl, Armada Skitraw, Ratu Marlya)
  ('MkArenaDmgKu', '64'),          -- damage dasar satu salvo kapal pemain (dikali pengali upgrade Cannons)
  ('MkArenaDmgMusuh', '1')         -- pengali damage armada Kumis Hitam (kenop keseimbangan)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Titik laut: Medan Tempur Teluk Dalam
-- ---------------------------------------------------------------------
insert into game.cities(city_id, name, type, repair_cost_rate, image_url, map_x, map_y, sort, hidden) values
  ('teluk_dalam', 'Medan Tempur Teluk Dalam', 'TelukDalam', 1.0, '', 158, 24, 42, true)
on conflict (city_id) do update set name = excluded.name, type = excluded.type, repair_cost_rate = excluded.repair_cost_rate,
  map_x = excluded.map_x, map_y = excluded.map_y, sort = excluded.sort, hidden = true;
delete from game.market where city_id = 'teluk_dalam';
select game.cfg_set('CitiesVersion', '12-teluk-dalam');

-- ---------------------------------------------------------------------
-- Tabel langkah (58-60 berubah: Galangan, berlayar, duel armada)
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
    {"n":49,"q":21,"c":"karang_garam","p":"dermaga","b":"nasiulam","g":"selam","bahan":{"beras":100}},
    {"n":50,"q":21,"c":"freeyork","p":"dok","b":"tungku","bahan":{"besi":30,"mesiu":35}},
    {"n":51,"q":21,"c":"zentul","p":"garasi","b":"kalibrasi","g":"tempa","batas":true,"bahan":{"oli_hitam":20,"tools":10}},
    {"n":52,"q":21,"c":"marie_regal","p":"istana","b":"pengacau","bahan":{"emas":5,"mutiara":5}},
    {"n":53,"q":21,"c":"skitraw","p":"galangan","b":"penghangat","bahan":{"jackdaniels":20,"jhonnywalker":20}},
    {"n":54,"q":21,"c":"toogood","p":"dok","b":"ransum","cicil":{"beras":300,"ikan_asin":300,"tuak":150},"gold":"Mk2GoldQ21","tanda":"janjirantai"},
    {"n":55,"q":22,"c":"rantai_lama","p":"tiba","b":"blokade","arr":true,"laut":"blokade"},
    {"n":56,"q":22,"c":"rantai_lama","p":"dermaga","b":"gerbang","g":"sandi"},
    {"n":57,"q":22,"c":"rantai_lama","p":"kongsi","b":"dewan"},
    {"n":58,"q":22,"c":"rantai_lama","p":"galangan","b":"barisan","perang":true,"laut":"g1","tuju":"teluk_dalam"},
    {"n":59,"q":22,"c":"rantai_lama","p":"galangan","b":"jantung","perang":true,"laut":"g2","tuju":"teluk_dalam"},
    {"n":60,"q":22,"c":"teluk_dalam","p":"tiba","b":"sovereign","perang":true,"arena":true,"tuju":"teluk_dalam","pilih":["hancurkan","ocid"],"gold":"Mk2GoldQ22","tanda":"penakluk","tamat":true}
  ]'::jsonb
$$;

-- ---------------------------------------------------------------------
-- Pembantu
-- ---------------------------------------------------------------------
-- Pelayaran khusus: Navy acak / bajak laut biasa tidak ikut mencegat di detik kedatangan
create or replace function game.mk2_laut_khusus(p_pid uuid, p_dest text) returns boolean
language plpgsql stable as $$
declare s int;
begin
  if p_pid is null or p_dest is null or not game.mk2_mulai(p_pid) then return false; end if;
  s := game.mk2_step(p_pid);
  return (s = 14 and p_dest = 'rantai_lama') or (s between 17 and 19 and p_dest = 'teluk_dalam');
exception when others then return false;
end $$;

-- Medan Tempur Teluk Dalam terbuka selama langkah 58-60 (dan selama kapten masih berada di sana)
create or replace function game.mk2_teluk_buka(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  if p_pid is null or not game.mk2_mulai(p_pid) then return false; end if;
  if game.mk2_step(p_pid) between 17 and 19 then return true; end if;
  return exists (select 1 from game.player_location where player_id = p_pid and (city_id = 'teluk_dalam' or destination_city_id = 'teluk_dalam'));
exception when others then return false;
end $$;

create or replace function game.mk2_laut_set(p_pid uuid, p_patch jsonb, p_hapus text[] default '{}') returns void
language sql as $$
  update game.player_quests set data = (coalesce(data, '{}'::jsonb) - p_hapus) || coalesce(p_patch, '{}'::jsonb), updated_at = now()
   where player_id = p_pid and quest_id = 'mahkota2'
$$;

-- Pencegatan tengah laut: encounter dengan penanda midSea + kode gelombang lw
create or replace function game.mk2_laut_enc(p_pid uuid, p_lw text, p_ke int default 1) returns jsonb
language plpgsql volatile as $$
declare e jsonb; k numeric;
begin
  if p_lw = 'blokade' then
    e := game.mk2_navy_enc(p_pid, 4, p_ke);
    -- jalur bos dipakai supaya pelayaran tidak selesai saat menang; Meriam Warlord x5 tetap berlaku melawan Navy (K2)
    k := coalesce(nullif(game.meriam_dmg_kali(p_pid), 0), 1);
    return (e - 'kind' - 'mk2navy') || jsonb_build_object('boss', 'mk2laut', 'midSea', true, 'lw', 'blokade', 'ke', p_ke,
      'noFleeMid', true, 'noTalkMsg', e ->> 'noTalkMsg', 'dmgTaken', game.voy_num(e -> 'dmgTaken') * k,
      'displayLevel', 9, 'retreat', true,
      'bossTitle', 'Blokade luar Rantai Lama - Gugus Tugas "Tembok Mahkota" ' || p_ke || '/2',
      'softSinkMsg', 'Lambungmu jebol di bawah gempuran Gugus Tugas "Tembok Mahkota"! Black Pearl menyeretmu mundur ke pelabuhan asal. Muatan dan gold aman. Perbaiki kapal, lalu angkat sauh lagi ke Rantai Lama.');
  end if;
  if p_lw = 'g1a' then e := game.mk2_enc(p_pid, 0);
  elsif p_lw = 'g1b' then e := game.mk2_enc(p_pid, 1);
  else e := game.mk2_enc(p_pid, greatest(2, least(4, 1 + p_ke)));   -- g2: Algojo 1..3 = w 2..4
  end if;
  return e || jsonb_build_object('midSea', true, 'lw', p_lw, 'ke', p_ke, 'rolledAt', game.iso(clock_timestamp()),
    'retreatMsg', 'Armada aliansi menutupi manuvermu. Kau memutar haluan kembali ke Pelabuhan Rantai Lama.',
    'softSinkMsg', 'Lambungmu jebol! Black Pearl menyeretmu mundur ke Pelabuhan Rantai Lama. Perbaiki kapal, lalu pimpin lagi barisan dari Galangan.');
end $$;

-- Waktu pencegatan tiba: pasang encounter, simpan potret waktu pelayaran
create or replace function game.mk2_laut_cek(p_pid uuid) returns boolean
language plpgsql as $$
declare l game.player_location; d jsonb; lt jsonb; v_now bigint := game.now_ms(); v_dep bigint; v_arr bigint; enc jsonb; v_lw text;
begin
  if p_pid is null then return false; end if;
  select data into d from game.player_quests where player_id = p_pid and quest_id = 'mahkota2';
  lt := d -> 'laut';
  if jsonb_typeof(lt) <> 'object' or not (lt ? 'at') or (lt ->> 'at')::bigint > v_now then return false; end if;
  select * into l from game.player_location where player_id = p_pid for update;
  if not found or coalesce(l.destination_city_id, '') = '' or l.destination_city_id is distinct from (lt ->> 'dest') then
    perform game.mk2_laut_set(p_pid, null, array['laut', 'jeda']);
    return false;
  end if;
  if jsonb_typeof(l.pending_encounter) = 'object' then return false; end if;
  -- baca ulang setelah lokasi terkunci (dua poll bersamaan)
  select data into d from game.player_quests where player_id = p_pid and quest_id = 'mahkota2' for update;
  lt := d -> 'laut';
  if jsonb_typeof(lt) <> 'object' or not (lt ? 'at') or (lt ->> 'at')::bigint > v_now then return false; end if;
  v_lw := case lt ->> 'w' when 'blokade' then 'blokade' when 'g1' then 'g1a' when 'g2' then 'g2' else null end;
  if v_lw is null then return false; end if;
  v_dep := (extract(epoch from l.depart_at) * 1000)::bigint;
  v_arr := (extract(epoch from l.arrive_at) * 1000)::bigint;
  enc := game.mk2_laut_enc(p_pid, v_lw, 1);
  update game.player_location set pending_encounter = enc where player_id = p_pid;
  perform game.mk2_laut_set(p_pid, jsonb_build_object(
      'laut', (lt - 'at') || jsonb_build_object('aktif', v_lw),
      'jeda', jsonb_build_object('jalan', greatest(0, v_now - v_dep), 'sisa', greatest(6000, v_arr - v_now))));
  perform game.log(p_pid, case v_lw when 'blokade' then 'Gugus Tugas "Tembok Mahkota" mencegat di tengah laut, sebelum Rantai Lama terlihat!'
    when 'g1a' then 'Gelombang 1: barikade mulut Teluk Dalam menghadang!' else 'Gelombang 2: tiga kapal Algojo mengepung!' end);
  return true;
end $$;

-- Pelayaran berlanjut dari titik pencegatan
create or replace function game.mk2_laut_jalan(p_pid uuid) returns void
language plpgsql as $$
declare j jsonb;
begin
  select data -> 'jeda' into j from game.player_quests where player_id = p_pid and quest_id = 'mahkota2';
  update game.player_location set pending_encounter = null,
      depart_at = case when jsonb_typeof(j) = 'object' then now() - make_interval(secs => greatest(0, (j ->> 'jalan')::numeric) / 1000) else depart_at end,
      arrive_at = case when jsonb_typeof(j) = 'object' then now() + make_interval(secs => greatest(6000, (j ->> 'sisa')::numeric) / 1000)
                       else greatest(arrive_at, now() + interval '6 seconds') end
   where player_id = p_pid and coalesce(destination_city_id, '') <> '';
end $$;

-- ---------------------------------------------------------------------
-- Menang di tengah laut: kapal berikutnya (chain) atau penanda lanjut
-- ---------------------------------------------------------------------
create or replace function game.mk2_laut_menang(p_pid uuid) returns jsonb
language plpgsql as $$
declare enc jsonb; v_lw text; v_ke int; h jsonb; v_msg text; d jsonb;
begin
  select pending_encounter into enc from game.player_location where player_id = p_pid;
  if jsonb_typeof(enc) <> 'object' or not coalesce((enc ->> 'midSea')::boolean, false) then return null; end if;
  v_lw := enc ->> 'lw'; v_ke := coalesce((enc ->> 'ke')::int, 1);
  perform 1 from game.player_quests where player_id = p_pid and quest_id = 'mahkota2' for update;
  select data into d from game.player_quests where player_id = p_pid and quest_id = 'mahkota2';

  if v_lw = 'blokade' and v_ke = 1 then
    return jsonb_build_object('gold', 0, 'event', 'mk2_blokade1', 'chain', game.mk2_laut_enc(p_pid, 'blokade', 2),
      'message', 'KPD Tembok Timur patah tiangnya dan terseret arus. Belum sempat bernapas, KPD Tembok Barat menutup jalur!');
  end if;
  if v_lw = 'blokade' then
    begin h := game.mk2_navy_hadiah(p_pid, 4); exception when others then h := jsonb_build_object('keping', 0, 'gold', 0); end;
    perform game.mk2_laut_set(p_pid, jsonb_build_object('blokadeOk', true), array['laut']);
    perform game.log(p_pid, 'Blokade luar Rantai Lama jebol di tengah laut.');
    return jsonb_build_object('gold', 0, 'event', 'mk2_blokade', 'chain', jsonb_build_object('mk2lanjut', true, 'lanjut', 'jalan'),
      'keping', (h ->> 'keping')::int,
      'message', 'Garis depan Gugus Tugas "Tembok Mahkota" jebol! zafachmie di corong laut: "Terus, Kapten! Rantai Lama sudah dekat!"' ||
        case when coalesce((h ->> 'gold')::bigint, 0) > 0 then ' Kas perang Navy ikut terjarah: +' || (h ->> 'gold') || ' gold.' else '' end ||
        ' +' || coalesce(h ->> 'keping', '0') || ' Keping Rantau.');
  end if;
  if v_lw = 'g1a' then
    perform game.mk2_laut_set(p_pid, jsonb_build_object('laut', jsonb_build_object('w', 'kilat', 'dest', 'teluk_dalam', 'hold', true), 'kilat', false));
    return jsonb_build_object('gold', 0, 'event', 'mk2_kilat', 'chain', jsonb_build_object('mk2lanjut', true, 'lanjut', 'kilat'),
      'message', 'KPD Tembok Utara patah tiangnya dan terseret arus. Di belakangnya, KPD Tembok Selatan memutar meriam jarak jauhnya. cangcimen di corong: "Barisan Pacu, potong zona bidiknya! Ikuti garis apiku, Kapten!"');
  end if;
  if v_lw = 'g1b' then
    update game.player_quests set step = greatest(step, 18), updated_at = now(),
        data = (data - 'laut') || jsonb_build_object('ba', 2, 's58', game.now_ms(),
          -- jam +5 dtk dimulai saat kapten menutup ringkasan tempur (aksi lautMulai); cadangan 20 dtk bila klien diam
          'laut', jsonb_build_object('w', 'g2', 'dest', 'teluk_dalam', 'tunda', true, 'at', game.now_ms() + 20000))
     where player_id = p_pid and quest_id = 'mahkota2';
    perform game.log(p_pid, 'Mahkota: langkah 58 selesai (barikade selat bersih).');
    return jsonb_build_object('gold', 0, 'event', 'mk2_g1', 'chain', jsonb_build_object('mk2lanjut', true, 'lanjut', 'jalan'),
      'message', 'Barikade selat bersih! cangcimen lewat corong: "Tahan posisi, Kapten! Tiga kapal Algojo menunggu di tengah palung." Layarmu kembali terkembang menuju Medan Tempur Teluk Dalam.');
  end if;
  -- g2: Algojo 1..3
  if v_ke < 3 then
    v_msg := case v_ke when 1 then 'Algojo "Sayap Kiri" terbakar dan miring. Hasiolan: "Satu jatuh! Sayap kanan, Bang Rimba!"'
                       else 'Algojo "Sayap Kanan" karam ditelan arus. Petrik memotong haluan kapal komando dengan Sayap Tempa.' end;
    return jsonb_build_object('gold', 0, 'event', 'mk2_algojo', 'chain', game.mk2_laut_enc(p_pid, 'g2', v_ke + 1), 'message', v_msg);
  end if;
  update game.player_quests set step = greatest(step, 19), updated_at = now(),
      data = (data - 'laut') || jsonb_build_object('ba', 5, 's59', game.now_ms(), 'hasiolan', true)
   where player_id = p_pid and quest_id = 'mahkota2';
  perform game.log(p_pid, 'Mahkota: langkah 59 selesai (armada Algojo tumbang).');
  return jsonb_build_object('gold', 0, 'event', 'mk2_g2', 'chain', jsonb_build_object('mk2lanjut', true, 'lanjut', 'jalan'),
    'message', 'Kapal komando Algojo tumbang. Hasiolan: "Sayap mereka runtuh! Di depanmu kapal induk Sovereign Mahkota. Kumis Hitam sudah mengenakan Mahkota Karam!"');
end $$;

do $$
begin
  drop function if exists game.quest_boss_defeated_tdl(uuid);
  alter function game.quest_boss_defeated(uuid) rename to quest_boss_defeated_tdl;
  drop function if exists game.quest_combat_end_tdl(uuid, jsonb, text);
  alter function game.quest_combat_end(uuid, jsonb, text) rename to quest_combat_end_tdl;
  drop function if exists game.resolve_arrival_if_due_tdl(uuid);
  alter function game.resolve_arrival_if_due(uuid) rename to resolve_arrival_if_due_tdl;
  drop function if exists game.quest_arrival_redirect_tdl(uuid, text, text);
  alter function game.quest_arrival_redirect(uuid, text, text) rename to quest_arrival_redirect_tdl;
  drop function if exists game.kd_enc_tdl(uuid, jsonb);
  alter function game.kd_enc(uuid, jsonb) rename to kd_enc_tdl;
  drop function if exists game.city_open_tdl(uuid, text);
  alter function game.city_open(uuid, text) rename to city_open_tdl;
  drop function if exists game.player_unlocks_tdl(uuid);
  alter function game.player_unlocks(uuid) rename to player_unlocks_tdl;
  drop function if exists game.spot_city_tdl(text);
  alter function game.spot_city(text) rename to spot_city_tdl;
  drop function if exists game.voy_far_city_tdl(text);
  alter function game.voy_far_city(text) rename to voy_far_city_tdl;
  drop function if exists game.city_flavor_tdl(text);
  alter function game.city_flavor(text) rename to city_flavor_tdl;
  drop function if exists game.mk2_view_tdl(uuid);
  alter function game.mk2_view(uuid) rename to mk2_view_tdl;
  drop function if exists game.mk2_act_tdl(jsonb);
  alter function game.mk2_act(jsonb) rename to mk2_act_tdl;
  drop function if exists game.api_setsail_tdl(jsonb);
  alter function public.api_setsail(jsonb) rename to api_setsail_tdl;
  alter function public.api_setsail_tdl(jsonb) set schema game;
  drop function if exists game.api_resolvecombat_tdl(jsonb);
  alter function public.api_resolvecombat(jsonb) rename to api_resolvecombat_tdl;
  alter function public.api_resolvecombat_tdl(jsonb) set schema game;
end $$;
revoke all on function game.api_setsail_tdl(jsonb) from public, anon, authenticated;
revoke all on function game.api_resolvecombat_tdl(jsonb) from public, anon, authenticated;
revoke all on function game.mk2_act_tdl(jsonb) from public, anon, authenticated;

create or replace function game.quest_boss_defeated(p_pid uuid) returns jsonb
language sql as $$ select coalesce(game.mk2_laut_menang(p_pid), game.quest_boss_defeated_tdl(p_pid)) $$;

-- Kalah / mundur di tengah laut: penanda dibersihkan; Gelombang 1 diulang utuh
create or replace function game.quest_combat_end(p_pid uuid, p_enc jsonb, p_result text) returns void
language plpgsql as $$
begin
  perform game.quest_combat_end_tdl(p_pid, p_enc, p_result);
  begin
    if jsonb_typeof(p_enc) = 'object' and coalesce((p_enc ->> 'midSea')::boolean, false) and p_result <> 'won' then
      perform game.mk2_laut_set(p_pid, case when p_enc ->> 'lw' in ('g1a', 'g1b') then '{"kilat":false,"ba":0}'::jsonb else null end,
        array['laut', 'jeda']);
    end if;
  exception when others then null;
  end;
end $$;

create or replace function game.resolve_arrival_if_due(p_pid uuid) returns jsonb
language plpgsql as $$
begin
  -- jalur cepat: hanya kapten yang sedang punya jadwal pencegatan yang masuk sub-transaksi
  if exists (select 1 from game.player_quests where player_id = p_pid and quest_id = 'mahkota2' and data ? 'laut') then
    begin perform game.mk2_laut_cek(p_pid); exception when others then null; end;
  end if;
  return game.resolve_arrival_if_due_tdl(p_pid);
end $$;

-- Selama Trektrek-an Kilat (atau pencegatan yang belum muncul) kapal tidak boleh sandar
create or replace function game.quest_arrival_redirect(p_pid uuid, p_origin text, p_dest text) returns jsonb
language plpgsql as $$
declare lt jsonb;
begin
  begin
    select data -> 'laut' into lt from game.player_quests where player_id = p_pid and quest_id = 'mahkota2';
    if jsonb_typeof(lt) = 'object' and lt ->> 'dest' = p_dest and (coalesce((lt ->> 'hold')::boolean, false) or lt ? 'at') then
      return jsonb_build_object('hold', true);
    end if;
  exception when others then null;
  end;
  if p_dest = 'teluk_dalam' and not game.mk2_teluk_buka(p_pid) and p_origin is distinct from 'teluk_dalam' then
    return jsonb_build_object('city', p_origin,
      'message', 'Teluk Dalam sudah tenang. Tak ada lagi yang menunggu di sana. Kapalmu berbalik ke pelabuhan asal.');
  end if;
  return game.quest_arrival_redirect_tdl(p_pid, p_origin, p_dest);
end $$;

-- Pelayaran khusus: hanya pencegatan quest (bos) yang boleh muncul di detik kedatangan
create or replace function game.kd_enc(p_pid uuid, p_enc jsonb) returns jsonb
language plpgsql as $$
declare l game.player_location;
begin
  begin
    select * into l from game.player_location where player_id = p_pid;
    if game.mk2_laut_khusus(p_pid, l.destination_city_id) then
      if jsonb_typeof(p_enc) = 'object' and coalesce(p_enc ->> 'boss', '') <> '' then return p_enc; end if;
      return null;
    end if;
  exception when others then null;
  end;
  return game.kd_enc_tdl(p_pid, p_enc);
end $$;

create or replace function game.city_open(p_pid uuid, p_city text) returns boolean
language plpgsql stable as $$
begin
  if p_city = 'teluk_dalam' then return coalesce(game.pasir_era(p_pid), 'kini') = 'kini' and game.mk2_teluk_buka(p_pid); end if;
  return game.city_open_tdl(p_pid, p_city);
end $$;

create or replace function game.player_unlocks(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare u jsonb := game.player_unlocks_tdl(p_pid);
begin
  if game.city_open(p_pid, 'teluk_dalam') then u := coalesce(u, '[]'::jsonb) || '["teluk_dalam"]'::jsonb; end if;
  return u;
end $$;

create or replace function game.spot_city(p_city text) returns boolean
language sql immutable as $$ select p_city = 'teluk_dalam' or game.spot_city_tdl(p_city) $$;

create or replace function game.voy_far_city(p_city text) returns boolean
language sql immutable as $$ select coalesce(p_city = 'teluk_dalam', false) or game.voy_far_city_tdl(p_city) $$;

create or replace function game.city_flavor(p_type text) returns text
language sql immutable as $$
  select case when p_type = 'TelukDalam'
    then 'Perairan di ujung Teluk Dalam, tempat arus palung berputar di atas altar segel yang menyala. Tak ada dermaga, tak ada pasar. Hanya Sovereign Mahkota dan armada pengawalnya.'
    else game.city_flavor_tdl(p_type) end
$$;

-- ---------------------------------------------------------------------
-- Berlayar: pasang jadwal pencegatan
-- ---------------------------------------------------------------------
create or replace function public.api_setSail(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); v_dest text := game.arg(a, 0); r jsonb; s int := -1; d jsonb := '{}'::jsonb;
  v_lw text := null; v_det numeric; v_min int; v_arr timestamptz;
begin
  if v_pid is not null and game.mk2_mulai(v_pid) then
    s := game.mk2_step(v_pid); d := game.mk2_data(v_pid);
    if v_dest = 'teluk_dalam' and s between 17 and 19 and game.current_city(v_pid) is distinct from 'rantai_lama'
       and not game.in_transit(v_pid) then
      raise exception 'Armada aliansi berkumpul di Pelabuhan Rantai Lama, Kapten. Pimpin barisan dari Galangan di sana.';
    end if;
  end if;
  r := game.api_setsail_tdl(a);
  if s < 0 then return r; end if;
  begin
    if s = 14 and v_dest = 'rantai_lama' and not coalesce((d ->> 'blokadeOk')::boolean, false) then
      v_lw := 'blokade'; v_det := greatest(1, game.cfg_num('Mk2CegatDetik55', 3)); v_min := 12;
    elsif s = 17 and v_dest = 'teluk_dalam' then
      v_lw := 'g1'; v_det := greatest(1, game.cfg_num('Mk2CegatDetikTeluk', 5)); v_min := 20;
    elsif s = 18 and v_dest = 'teluk_dalam' then
      v_lw := 'g2'; v_det := greatest(1, game.cfg_num('Mk2CegatDetikTeluk', 5)); v_min := 14;
    end if;
    if v_lw is null then
      if d ? 'laut' or d ? 'jeda' then perform game.mk2_laut_set(v_pid, null, array['laut', 'jeda']); end if;
      return r;
    end if;
    perform game.mk2_laut_set(v_pid, jsonb_build_object('laut', jsonb_build_object('w', v_lw, 'dest', v_dest, 'at', game.now_ms() + v_det * 1000))
        || case when v_lw = 'g1' then '{"kilat":false,"ba":0}'::jsonb else '{}'::jsonb end, array['jeda']);
    -- pelayaran sependek apa pun tetap memberi ruang untuk pencegatan + layar terkembang lagi
    update game.player_location set arrive_at = greatest(arrive_at, depart_at + make_interval(secs => v_min))
     where player_id = v_pid returning arrive_at into v_arr;
    if v_arr is not null then
      r := r || jsonb_build_object('arriveAt', game.iso(v_arr),
        'travelSeconds', greatest(coalesce((r ->> 'travelSeconds')::int, 0), v_min));
    end if;
  exception when others then null;
  end;
  return r;
end $$;
select game.expose('api_setsail');

-- ---------------------------------------------------------------------
-- Pertempuran tengah laut: kabur dikunci (blokade), penanda lanjut disambung jadi pelayaran
-- ---------------------------------------------------------------------
create or replace function public.api_resolveCombat(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); enc jsonb; r jsonb; nx jsonb; v_lanjut text;
begin
  select pending_encounter into enc from game.player_location where player_id = v_pid;
  if jsonb_typeof(enc) <> 'object' or not coalesce((enc ->> 'midSea')::boolean, false) then
    return game.api_resolvecombat_tdl(a);
  end if;
  if game.arg(a, 0) = 'flee' and coalesce((enc ->> 'noFleeMid')::boolean, false) then
    raise exception '%', coalesce(enc ->> 'noFleeMsg', 'Tidak ada celah untuk kabur.');
  end if;
  r := game.api_resolvecombat_tdl(a);
  nx := r -> 'encounter';
  if not coalesce((r ->> 'chained')::boolean, false) or jsonb_typeof(nx) <> 'object' or not coalesce((nx ->> 'mk2lanjut')::boolean, false) then
    return r;
  end if;
  v_lanjut := coalesce(nx ->> 'lanjut', 'jalan');
  if v_lanjut = 'jalan' then
    perform game.mk2_laut_jalan(v_pid);
  else
    update game.player_location set pending_encounter = null where player_id = v_pid;   -- Trektrek-an Kilat menyusul, kapal ditahan
  end if;
  return (r - 'encounter' - 'chained') || jsonb_build_object('ongoing', false, 'success', true, 'result', 'won', 'cityId', null,
    'midSea', true, 'lanjut', v_lanjut, 'questEvent', 'mk2laut_' || v_lanjut,
    'voyage', game.voyage_state(v_pid),
    'newCondition', game.ship_json(v_pid) -> 'Condition', 'newGold', (select gold from game.players where player_id = v_pid));
end $$;
select game.expose('api_resolvecombat');

-- ---------------------------------------------------------------------
-- Tampilan klien
-- ---------------------------------------------------------------------
create or replace function game.mk2_view(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v jsonb := game.mk2_view_tdl(p_pid); d jsonb := game.mk2_data(p_pid); lt jsonb := d -> 'laut';
begin
  return v || jsonb_build_object(
    'laut', case when jsonb_typeof(lt) = 'object' then jsonb_build_object('w', lt ->> 'w', 'dest', lt ->> 'dest',
        'hold', coalesce((lt ->> 'hold')::boolean, false), 'aktif', lt ->> 'aktif',
        'dalam', case when lt ? 'at' then greatest(0, (lt ->> 'at')::bigint - game.now_ms()) end) end,
    'blokadeOk', coalesce((d ->> 'blokadeOk')::boolean, false),
    'arenaKalah', coalesce((d ->> 'arenaKalah')::int, 0),
    'hasiolan', coalesce((d ->> 'hasiolan')::boolean, false));
exception when others then return v;
end $$;

-- Angka duel armada (dihitung server, klien hanya mensimulasikan)
create or replace function game.mk2_arena_cfg(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare mx numeric; k numeric; up int := 0; wl boolean := false;
begin
  mx := coalesce(game.voy_max_cond(p_pid), 1500);
  begin up := game.voy_abs_step(game.voy_player_upgrades(p_pid) -> 'cannons'); exception when others then up := 0; end;
  begin wl := game.wl_has(p_pid, 'cannons'); exception when others then wl := false; end;
  k := game.meriam_dmg_langkah(up);   -- Meriam Warlord x5 tidak berlaku di Battle Akhir (K2)
  return jsonb_build_object(
    'hpKu', least(3400, greatest(1800, round(mx))),
    'dmgKu', round(greatest(10, game.cfg_num('MkArenaDmgKu', 64)) * k),
    'meriam', least(20, greatest(0, up)), 'warlord', wl,
    'hpSov', greatest(500, game.cfg_num('MkArenaSovHp', 2600)),
    'hpNavy', greatest(200, game.cfg_num('MkArenaNavyHp', 950)),
    'hpSekutu', greatest(200, game.cfg_num('MkArenaSekutuHp', 1700)),
    'dmgMusuh', greatest(0.2, game.cfg_num('MkArenaDmgMusuh', 1)),
    'minDetik', greatest(5, game.cfg_num('MkArenaMinDetik', 30)));
end $$;

-- ---------------------------------------------------------------------
-- mk2_act: Trektrek-an Kilat di tengah laut, mundur, duel armada, pagar langkah 55 & 58-60
-- ---------------------------------------------------------------------
create or replace function game.mk2_act(a jsonb) returns jsonb
language plpgsql as $$
declare
  v_act text := coalesce(game.arg(a, 0), 'status');
  v_pid uuid; v_want int := game.arg_int(a, 1); v_step int; v_data jsonb; d jsonb; lt jsonb;
  t jsonb; h jsonb; v_id uuid; enc jsonb; r jsonb; v_hasil jsonb; v_ms bigint; v_el bigint; v_run jsonb; v_win boolean;
begin
  v_pid := (game.me(true)).player_id;
  if v_act in ('kilat', 'kilatSelesai', 'mundur', 'arena', 'arenaHasil', 'serang', 'maju', 'pilih', 'lautMulai') then
    insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'mahkota2', 0, '{}'::jsonb)
    on conflict (player_id, quest_id) do nothing;
    select step, data into v_step, v_data from game.player_quests where player_id = v_pid and quest_id = 'mahkota2' for update;
    v_data := coalesce(v_data, '{}'::jsonb); lt := v_data -> 'laut';
    d := game.mk2_steps() -> v_step;
  else
    return game.mk2_act_tdl(a);
  end if;

  -- ---------- jam pencegatan Gelombang 2 mulai berdetak (kapten menutup ringkasan tempur) ----------
  if v_act = 'lautMulai' then
    if jsonb_typeof(lt) = 'object' and coalesce((lt ->> 'tunda')::boolean, false) and lt ? 'at' then
      perform game.mk2_laut_set(v_pid, jsonb_build_object('laut', (lt - 'tunda') ||
        jsonb_build_object('at', least((lt ->> 'at')::bigint, game.now_ms() + greatest(1, game.cfg_num('Mk2CegatDetikTeluk', 5)) * 1000))));
    end if;
    return jsonb_build_object('mahkota', game.mk_state(v_pid));
  end if;

  -- ---------- Trektrek-an Kilat (Gelombang 1, di tengah laut) ----------
  if v_act in ('kilat', 'kilatSelesai', 'mundur') then
    if v_want is null or v_want <> 40 + v_step or v_step <> 17 or jsonb_typeof(lt) <> 'object' or lt ->> 'w' <> 'kilat' then
      raise exception 'Barisan Pacu sedang tidak menunggumu, Kapten.';
    end if;
    if not game.in_transit(v_pid) then
      perform game.mk2_laut_set(v_pid, '{"kilat":false,"ba":0}'::jsonb, array['laut', 'jeda']);
      raise exception 'Barisan Pacu sudah bubar, Kapten. Pimpin lagi dari Galangan Rantai Lama.';
    end if;
    if v_act = 'kilat' then
      t := game.trek_mulai(v_pid, 'turnamen', 'patroli', game.trek_kapal(v_pid));
      return jsonb_build_object('trek', t, 'mahkota', game.mk_state(v_pid));
    end if;
    if v_act = 'kilatSelesai' then
      begin v_id := game.arg(a, 2)::uuid; exception when others then raise exception 'Balapan tidak ditemukan.'; end;
      h := game.trek_selesai(v_pid, v_id, case when jsonb_typeof(a) = 'array' then a -> 3 end, 'turnamen');
      v_win := coalesce((h ->> 'win')::boolean, false);
    else
      h := null; v_win := false;
    end if;
    if v_win then
      enc := game.mk2_laut_enc(v_pid, 'g1b', 1);
      update game.player_location set pending_encounter = enc where player_id = v_pid;
      perform game.mk2_laut_set(v_pid, jsonb_build_object('kilat', true,
        'laut', jsonb_build_object('w', 'g1b', 'dest', 'teluk_dalam', 'aktif', 'g1b')));
      return jsonb_build_object('hasil', h, 'kilat', true, 'mahkota', game.mk_state(v_pid), 'voyage', game.voyage_state(v_pid));
    end if;
    -- gagal / mundur: kapal kembali ke Rantai Lama, Gelombang 1 diulang dari Galangan
    perform game.mk2_laut_set(v_pid, '{"kilat":false,"ba":0}'::jsonb, array['laut', 'jeda']);
    r := game.voy_finalize_arrival(v_pid, 'rantai_lama', case when v_act = 'mundur'
      then 'Kau memutar haluan. Barisan Pacu ikut mundur ke Pelabuhan Rantai Lama.'
      else 'Salvo barikade memaksa perahu-perahu Barisan Pacu memutar. Kapalmu kembali ke Pelabuhan Rantai Lama.' end);
    perform game.log(v_pid, 'Gelombang 1 gagal: kembali ke Pelabuhan Rantai Lama.');
    return jsonb_build_object('hasil', h, 'kilat', false, 'pulang', true, 'cityId', r -> 'cityId', 'mahkota', game.mk_state(v_pid));
  end if;

  -- ---------- pagar langkah ----------
  if v_act = 'serang' and v_step between 17 and 19 then
    raise exception 'Pimpin armada dari Galangan Rantai Lama, Kapten. Pertempurannya ada di laut.';
  end if;
  if v_act = 'maju' and v_step = 14 and not coalesce((v_data ->> 'blokadeOk')::boolean, false) then
    raise exception 'Blokade Kumis Hitam masih menutup jalan, Kapten. Angkat sauh ke Pelabuhan Rantai Lama.';
  end if;

  -- ---------- duel armada di Medan Tempur Teluk Dalam (langkah 60) ----------
  if v_act in ('arena', 'arenaHasil') then
    if v_want is null or v_want <> 40 + v_step or v_step <> 19 then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;
    if game.in_transit(v_pid) then raise exception 'Merapat dulu di Medan Tempur Teluk Dalam, Kapten.'; end if;
    if game.current_city(v_pid) is distinct from 'teluk_dalam' then raise exception 'Sovereign Mahkota menunggu di Medan Tempur Teluk Dalam, Kapten.'; end if;
    if coalesce((v_data ->> 'menang')::boolean, false) then raise exception 'Sovereign Mahkota sudah karam, Kapten.'; end if;
    if v_act = 'arena' then
      v_run := jsonb_build_object('id', substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 20),
        't', game.now_ms(), 'seed', 1 + floor(random() * 2000000000)::bigint);
      perform game.mk2_laut_set(v_pid, jsonb_build_object('arena', v_run));
      perform game.log(v_pid, 'Duel armada di Medan Tempur Teluk Dalam dimulai.');
      return jsonb_build_object('arena', (v_run - 't') || game.mk2_arena_cfg(v_pid), 'mahkota', game.mk_state(v_pid));
    end if;
    v_run := v_data -> 'arena';
    if jsonb_typeof(v_run) <> 'object' or v_run ->> 'id' is distinct from game.arg(a, 2) then raise exception 'Duel ini tidak tercatat, Kapten. Mulai lagi.'; end if;
    v_hasil := case when jsonb_typeof(a) = 'array' and jsonb_typeof(a -> 3) = 'object' then a -> 3 else '{}'::jsonb end;
    v_win := coalesce((v_hasil ->> 'win')::boolean, false);
    v_el := game.now_ms() - (v_run ->> 't')::bigint;
    begin v_ms := greatest(0, (v_hasil ->> 'ms')::bigint); exception when others then v_ms := 0; end;
    if v_win and (v_el < game.cfg_num('MkArenaMinDetik', 30) * 1000 or v_ms > v_el + 5000) then
      raise exception 'Catatan duel tidak wajar, Kapten.';
    end if;
    if v_win then
      update game.player_quests set data = (data - 'arena' - 'baHp') || jsonb_build_object('menang', true, 'ba', 8, 'baHp', 0,
          'arenaMs', v_ms), updated_at = now()
       where player_id = v_pid and quest_id = 'mahkota2';
      perform game.log(v_pid, 'Sovereign Mahkota karam di Medan Tempur Teluk Dalam. Mahkota Karam retak terbelah.');
    else
      perform game.mk2_laut_set(v_pid, jsonb_build_object('arenaKalah', coalesce((v_data ->> 'arenaKalah')::int, 0) + 1), array['arena']);
      perform game.log(v_pid, 'Duel armada: kapalmu tumbang. Armada aliansi berkumpul lagi.');
    end if;
    return jsonb_build_object('menang', v_win, 'mahkota', game.mk_state(v_pid));
  end if;

  r := game.mk2_act_tdl(a);
  -- tamat: Medan Tempur ditutup, kapten diantar armada kembali ke Rantai Lama
  if v_act = 'pilih' and coalesce((r ->> 'tamat')::boolean, false) then
    update game.player_location set city_id = 'rantai_lama'
     where player_id = v_pid and city_id = 'teluk_dalam' and coalesce(destination_city_id, '') = '';
    perform game.mk2_laut_set(v_pid, null, array['laut', 'jeda', 'arena']);
    r := r || jsonb_build_object('pulang', 'rantai_lama');
  end if;
  return r;
end $$;
revoke all on function game.mk2_act(jsonb) from public, anon, authenticated;

-- api_mahkota (0100) mengirim semua aksi bukan-'status' ke mk2_act, kecuali saat berlayar ditolak mk2_act_inti.
-- Aksi Kilat dijalankan saat berlayar; jalur 0100 tidak memeriksa transit sebelum mk2_act, jadi aman.

-- ---------------------------------------------------------------------
-- Alat GM (dibuat ulang): ikut membersihkan penanda laut / duel
-- ---------------------------------------------------------------------
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
    data = (game.player_quests.data - 'menang' - 'baHp' - 'laut' - 'jeda' - 'arena' - 'blokadeOk' - 'hasiolan' - 'arenaKalah')
      || jsonb_build_object('ba', case when s >= 19 then 5 when s >= 18 then 2 else 0 end, 'kilat', s >= 18)
      || case when s > 14 then '{"blokadeOk":true}'::jsonb else '{}'::jsonb end;
  return game.mk_state(v_pid);
end $$;
revoke all on function game.admin_mahkota2(text, int) from public, anon, authenticated;

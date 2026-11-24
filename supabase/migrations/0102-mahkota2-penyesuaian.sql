-- =====================================================================
-- 0102 · Saga 4 Bagian II: penyesuaian jumlah barang & batas tempa (Tide v83)
--   langkah 49  Ama Kerang : 10 -> 100 Beras
--   langkah 50  Tassyaaa   : 20 Besi + 15 Mesiu -> 30 Besi + 35 Mesiu
--   langkah 51  Yaptob     : 15 -> 20 Oli Hitam (+10 Perkakas); kalibrasi 2 percobaan per hari game
--               (MkBatasHari, sama dengan tempa katup Bagian I). Barang cukup diserahkan sekali.
--   Pemain yang sudah menyerahkan barang langkah itu tidak ditagih ulang (penanda data.bahanNN tetap).
-- Aman diulang.
-- =====================================================================

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
    {"n":55,"q":22,"c":"rantai_lama","p":"tiba","b":"blokade","arr":true},
    {"n":56,"q":22,"c":"rantai_lama","p":"dermaga","b":"gerbang","g":"sandi"},
    {"n":57,"q":22,"c":"rantai_lama","p":"kongsi","b":"dewan"},
    {"n":58,"q":22,"c":"rantai_lama","p":"dermaga","b":"barisan","race":"patroli","perang":true},
    {"n":59,"q":22,"c":"rantai_lama","p":"dermaga","b":"jantung","perang":true},
    {"n":60,"q":22,"c":"rantai_lama","p":"dermaga","b":"sovereign","perang":true,"pilih":["hancurkan","ocid"],"gold":"Mk2GoldQ22","tanda":"penakluk","tamat":true}
  ]'::jsonb
$$;

-- api: aksi 'coba' (dihitung sebelum mini game dibuka, pola langkah 15 Bagian I)
do $$
begin
  drop function if exists game.mk2_act_inti(jsonb);
  alter function game.mk2_act(jsonb) rename to mk2_act_inti;
end $$;
revoke all on function game.mk2_act_inti(jsonb) from public, anon, authenticated;

create or replace function game.mk2_act(a jsonb) returns jsonb
language plpgsql as $$
declare v_pid uuid; v_want int := game.arg_int(a, 1); v_step int; v_data jsonb; d jsonb;
  v_maks int; v_hari int; v_kb text; v_cn int;
begin
  if coalesce(game.arg(a, 0), '') <> 'coba' then return game.mk2_act_inti(a); end if;
  v_pid := (game.me(true)).player_id;
  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;
  select step, data into v_step, v_data from game.player_quests where player_id = v_pid and quest_id = 'mahkota2' for update;
  if v_step is null or v_want is null or v_want <> 40 + v_step then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;
  d := game.mk2_steps() -> v_step;
  if d is null or not (d ? 'batas') or d ->> 'g' is distinct from 'tempa' then raise exception 'Tidak ada yang perlu ditempa di sini, Kapten.'; end if;
  if d ? 'c' and game.current_city(v_pid) is distinct from (d ->> 'c') then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;
  v_data := coalesce(v_data, '{}'::jsonb);
  if d ? 'bahan' and not coalesce((v_data ->> ('bahan' || (d ->> 'n')))::boolean, false) then raise exception 'Serahkan dulu barangnya, Kapten.'; end if;
  v_maks := greatest(0, game.cfg_num('MkBatasHari', 2))::int;   -- 0 = tanpa batas
  v_hari := game.game_day();
  v_kb := 'cb' || (d ->> 'n');
  v_cn := case when (v_data -> v_kb ->> 'h') = v_hari::text then coalesce((v_data -> v_kb ->> 'n')::int, 0) else 0 end;
  if v_maks > 0 and v_cn >= v_maks then
    raise exception 'Tungku tempa sudah terlalu panas, kembalilah besok, Kapten. (Hari game berikutnya sekitar % menit lagi.)', game.minutes_to_next_day();
  end if;
  update game.player_quests set data = data || jsonb_build_object(v_kb, jsonb_build_object('h', v_hari, 'n', v_cn + 1)), updated_at = now()
   where player_id = v_pid and quest_id = 'mahkota2';
  return jsonb_build_object('mahkota', game.mk_state(v_pid), 'coba', true,
    'sisaHari', case when v_maks > 0 then greatest(0, v_maks - v_cn - 1) end);
end $$;
revoke all on function game.mk2_act(jsonb) from public, anon, authenticated;

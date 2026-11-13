-- =====================================================================
-- 0076 · Saga 4 batch 4a — QUEST MAHKOTA langkah 16-23 (Q17 "Dua Detik")
--   16 Babak 1 diulang dengan Mesin Jolt (wajib menang)   20 Teka-teki Nenek Ulin (dinilai server)
--   17 Semifinal lawan KapalMber (wajib menang)           21 Tembus Jaring pertama (saat dicegat patroli)
--   18 Lapor ke Yaptob                                    22 Koin bercap biru -> Pasar Gelap resmi terbuka
--   19 Pola rantai (Sandi Mercusuar) di Skitraw           23 Rencana Banjir Sutra -> hadiah Q17
-- Menimpa game.mk_steps dari 0075 (daftar langkah tumbuh tiap batch). Aman diulang.
-- =====================================================================

insert into game.config(key, value) values ('MkGoldQ17', '100000'), ('MkTekaJedaDetik', '20')
on conflict (key) do nothing;

-- flags = kolom game.mh_player yang disetel saat langkah selesai (lihat 0074)
create or replace function game.mk_steps() returns jsonb
language sql immutable as $$
  select '[
    {"n":1,"q":15,"p":"kota","b":"surat"},
    {"n":2,"q":15,"c":"ikn","p":"monumen","b":"dekret","g":"pantun","krisis":true},
    {"n":3,"q":15,"c":"ikn","p":"kamp","b":"jurutulis","g":"warga"},
    {"n":4,"q":15,"c":"joungjava","p":"syahbandar","b":"antrean","g":"syahbandar"},
    {"n":5,"q":15,"c":"joungjava","p":"warung","b":"dekretsalin"},
    {"n":6,"q":15,"c":"toogood","p":"dok","b":"blackpearl","cine":"mk_pantul"},
    {"n":7,"q":15,"c":"toogood","p":"alley","t":"malam","b":"hasiolan","g":"kuli","gold":"MkGoldQ15"},
    {"n":8,"q":16,"c":"paradiso","p":"vip","t":"malam","b":"rimba","g":"dadu"},
    {"n":9,"q":16,"c":"paradiso","p":"vip","b":"peta","g":"tercecer","zentul":true},
    {"n":10,"q":16,"c":"zentul","p":"tiba","b":"kabut","g":"angin","arr":true,"cine":"mk_zentul"},
    {"n":11,"q":16,"c":"zentul","p":"lapau","b":"daftar"},
    {"n":12,"q":16,"c":"zentul","p":"sirkuit","b":"babak1","race":"pariopelan","garasi":true},
    {"n":13,"q":16,"c":"zentul","p":"garasi","b":"kencang"},
    {"n":14,"q":16,"c":"zentul","p":"pasar","b":"sukucadang","g":"manifest"},
    {"n":15,"q":16,"c":"zentul","p":"garasi","b":"katup","g":"tempa","jolt":true,"gold":"MkGoldQ16"},
    {"n":16,"q":17,"c":"zentul","p":"sirkuit","b":"babak1ulang","race":"pariopelan","win":true,"hint":3},
    {"n":17,"q":17,"c":"zentul","p":"sirkuit","b":"semifinal","race":"kapalmber","win":true,"kiat":3},
    {"n":18,"q":17,"c":"zentul","p":"garasi","b":"lapor"},
    {"n":19,"q":17,"c":"skitraw","p":"galangan","b":"polarantai","g":"sandi"},
    {"n":20,"q":17,"c":"bjorneo","p":"mercusuar","b":"nenekulin","teka":true,
      "flags":{"tembus":true,"paksa":true,"aman":true}},
    {"n":21,"q":17,"p":"tembus","b":"tembus","arr":true,"zona":true},
    {"n":22,"q":17,"p":"pasar","b":"agen","g":"timbang","zonaHere":true,
      "flags":{"gelap":true,"paksa":false,"aman":false}},
    {"n":23,"q":17,"c":"paradiso","p":"vip","t":"malam","b":"lapor2","gold":"MkGoldQ17","tanda":"duadetik"}
  ]'::jsonb
$$;

-- Lawan latihan Sirkuit tumbuh mengikuti babak yang sudah dilewati.
create or replace function game.trek_lawan(p_pid uuid) returns text[]
language sql stable as $$
  select case
    when not game.mk_mulai(p_pid) then array['pariopelan', 'kapalmber', 'cangcimen', 'yaptob']
    when game.mk_step(p_pid) >= 17 then array['pariopelan', 'kapalmber']
    when game.mk_step(p_pid) >= 15 then array['pariopelan']
    else array[]::text[]
  end
$$;

-- ---------------------------------------------------------------------
-- Jawaban teka-teki Nenek Ulin: batre / baterai / batu baterai (+ salah eja yang lazim).
-- ---------------------------------------------------------------------
create or replace function game.mk_teka_benar(p_jawab text) returns boolean
language sql immutable as $$
  select regexp_replace(lower(btrim(coalesce(p_jawab, ''))), '[^a-z]', '', 'g')
         in ('batre', 'baterai', 'batubaterai', 'batere', 'baterei', 'batrai', 'batubatre', 'batubaterei', 'batubatere')
$$;

-- ---------------------------------------------------------------------
-- Langkah 21 & 22: hasil Tembus Jaring memajukan quest.
--   menang di langkah 21 -> langkah 22 terbuka di pasar kota tempat tiba
-- ---------------------------------------------------------------------
do $$
begin
  drop function if exists game.mh_cukai_act_mk(uuid, text, text, jsonb);
  alter function game.mh_cukai_act(uuid, text, text, jsonb) rename to mh_cukai_act_mk;
end $$;
revoke all on function game.mh_cukai_act_mk(uuid, text, text, jsonb) from public, anon, authenticated;

create or replace function game.mh_cukai_act(p_pid uuid, p_tactic text, p_run text default null, p_log jsonb default null) returns jsonb
language plpgsql as $$
declare r jsonb; v_step int; d jsonb;
begin
  r := game.mh_cukai_act_mk(p_pid, p_tactic, p_run, p_log);
  begin
    if coalesce((r ->> 'success')::boolean, false) and r ->> 'result' = 'tembus' then
      v_step := game.mk_step(p_pid);
      d := game.mk_steps() -> v_step;
      if d is not null and coalesce((d ->> 'zona')::boolean, false) then
        update game.player_quests
           set step = v_step + 1, updated_at = now(),
               data = data || jsonb_build_object('s' || (v_step + 1), game.now_ms(), 'zona', r ->> 'cityId')
         where player_id = p_pid and quest_id = 'mahkota';
        perform game.log(p_pid, 'Mahkota: langkah ' || (v_step + 1) || ' selesai.');
        r := r || jsonb_build_object('mahkota', game.mk_state(p_pid));
      end if;
    end if;
  exception when others then null;
  end;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- api_mahkota: tambahan aksi 'teka' + syarat langkah baru.
--   teka, n, jawaban  -> jawab teka-teki Nenek Ulin
-- ---------------------------------------------------------------------
create or replace function public.api_mahkota(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status');
  v_want int := game.arg_int(a, 1);
  v_res text := lower(btrim(coalesce(game.arg(a, 2), '')));
  v_step int; d jsonb; v_city text; v_gold bigint := 0; v_oli int := 0; v_id uuid; h jsonb; t jsonb;
  v_data jsonb; v_jeda numeric; k text; v_f jsonb;
begin
  if v_act = 'status' then return jsonb_build_object('mahkota', game.mk_state(v_pid)); end if;
  if v_act not in ('maju', 'balap', 'selesai', 'teka') then raise exception 'Aksi tidak dikenal.'; end if;
  if not game.mk_eligible(v_pid) then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;
  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;

  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'mahkota', 0, '{}'::jsonb)
  on conflict (player_id, quest_id) do nothing;
  select step, data into v_step, v_data from game.player_quests where player_id = v_pid and quest_id = 'mahkota' for update;
  v_data := coalesce(v_data, '{}'::jsonb);

  if v_step >= game.mk_ada() then raise exception 'Ceritanya berhenti di sini dulu, Kapten. Bersambung.'; end if;
  if v_want is null or v_want <> v_step then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;

  d := game.mk_steps() -> v_step;
  v_city := game.current_city(v_pid);
  if d ? 'c' and v_city is distinct from (d ->> 'c') then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;
  -- langkah 22: hanya di kota Zona Cukai tempat kau menembus jaring
  if coalesce((d ->> 'zonaHere')::boolean, false) and v_city is distinct from (v_data ->> 'zona') then
    raise exception 'Agen itu menunggu di pasar tempat kau menembus jaring, Kapten.';
  end if;
  -- langkah yang dipicu kedatangan (Tembus Jaring) tidak punya tombol sendiri
  if coalesce((d ->> 'zona')::boolean, false) and v_act <> 'status' then
    raise exception 'Berlayarlah ke pulau bertanda cukai, Kapten. Jaring itu yang akan menemukanmu.';
  end if;
  if d ->> 't' = 'malam' and not game.fish_is_night() then raise exception 'Datanglah lagi saat lampu-lampu dinyalakan, Kapten.'; end if;

  -- ---------------- teka-teki Nenek Ulin ----------------
  if v_act = 'teka' then
    if not coalesce((d ->> 'teka')::boolean, false) then raise exception 'Tidak ada teka-teki di sini, Kapten.'; end if;
    v_jeda := greatest(0, game.cfg_num('MkTekaJedaDetik', 20)) * 1000;
    if coalesce((v_data ->> 'tekaAt')::bigint, 0) + v_jeda > game.now_ms() then
      return jsonb_build_object('mahkota', game.mk_state(v_pid), 'maju', false, 'teka', false,
        'tunggu', ceil((coalesce((v_data ->> 'tekaAt')::bigint, 0) + v_jeda - game.now_ms()) / 1000.0)::int,
        'pesan', 'Nenek Ulin menutup matanya. "Sabar, Nak. Pikir dulu, baru bicara."');
    end if;
    if not game.mk_teka_benar(v_res) then
      update game.player_quests set data = data || jsonb_build_object('tekaAt', game.now_ms(), 'tekaSalah',
        coalesce((v_data ->> 'tekaSalah')::int, 0) + 1), updated_at = now()
       where player_id = v_pid and quest_id = 'mahkota';
      return jsonb_build_object('mahkota', game.mk_state(v_pid), 'maju', false, 'teka', false,
        'tunggu', ceil(v_jeda / 1000.0)::int,
        'pesan', 'Nenek Ulin menggeleng pelan. "Bukan itu, Nak. Batu itu tidak diam. Ia menyimpan sesuatu."');
    end if;
  elsif coalesce((d ->> 'teka')::boolean, false) and v_act = 'maju' then
    raise exception 'Jawab dulu teka-tekinya, Kapten.';
  end if;

  -- ---------------- balapan turnamen ----------------
  if v_act = 'balap' then
    if not (d ? 'race') then raise exception 'Tidak ada balapan di langkah ini, Kapten.'; end if;
    t := game.trek_mulai(v_pid, 'turnamen', d ->> 'race', game.trek_kapal(v_pid));
    return jsonb_build_object('trek', t, 'mahkota', game.mk_state(v_pid));
  end if;

  if v_act = 'selesai' then
    if not (d ? 'race') then raise exception 'Tidak ada balapan di langkah ini, Kapten.'; end if;
    begin v_id := game.arg(a, 2)::uuid; exception when others then raise exception 'Balapan tidak ditemukan.'; end;
    h := game.trek_selesai(v_pid, v_id, case when jsonb_typeof(a) = 'array' then a -> 3 end, 'turnamen');
    if coalesce((d ->> 'win')::boolean, false) and not coalesce((h ->> 'win')::boolean, false) then
      update game.player_quests set data = data || jsonb_build_object('kalah' || v_step,
        coalesce((v_data ->> ('kalah' || v_step))::int, 0) + 1), updated_at = now()
       where player_id = v_pid and quest_id = 'mahkota';
      return jsonb_build_object('hasil', h, 'mahkota', game.mk_state(v_pid), 'maju', false,
        'kalah', coalesce((v_data ->> ('kalah' || v_step))::int, 0) + 1);
    end if;
    v_res := 'ok';
  end if;

  -- ---------------- syarat mini game ----------------
  if v_act = 'maju' then
    if d ? 'race' then raise exception 'Turun dulu ke garis start, Kapten.'; end if;
    if d ? 'g' and v_res not in ('ok', 'menang') then raise exception 'Belum berhasil, Kapten. Coba lagi.'; end if;
  end if;

  -- ---------------- efek langkah ----------------
  if coalesce((d ->> 'krisis')::boolean, false) then
    insert into game.mh_player(player_id, krisis) values (v_pid, true)
    on conflict (player_id) do update set krisis = true, updated_at = now();
  end if;
  if jsonb_typeof(d -> 'flags') = 'object' then
    insert into game.mh_player(player_id, krisis) values (v_pid, true) on conflict (player_id) do nothing;
    for k in select jsonb_object_keys(d -> 'flags') loop
      v_f := d -> 'flags' -> k;
      if k = 'tembus' then update game.mh_player set tembus = (v_f)::text::boolean, updated_at = now() where player_id = v_pid;
      elsif k = 'gelap' then update game.mh_player set gelap = (v_f)::text::boolean, updated_at = now() where player_id = v_pid;
      elsif k = 'paksa' then update game.mh_player set paksa = (v_f)::text::boolean, updated_at = now() where player_id = v_pid;
      elsif k = 'aman' then update game.mh_player set aman = (v_f)::text::boolean, updated_at = now() where player_id = v_pid;
      end if;
    end loop;
  end if;
  if d ->> 'g' = 'dadu' and v_res = 'menang' then
    v_oli := greatest(0, game.cfg_num('MkOliDadu', 3))::int;
    if v_oli > 0 and game.cargo_free(v_pid) >= v_oli * coalesce((select size from game.commodities where id = 'oli_hitam'), 1) then
      perform game.adjust_inventory(v_pid, 'oli_hitam', v_oli);
    else v_oli := 0;
    end if;
  end if;
  if d ? 'gold' then
    v_gold := greatest(0, game.cfg_num(d ->> 'gold', 0))::bigint;
    if v_gold > 0 then update game.players set gold = gold + v_gold where player_id = v_pid; end if;
  end if;

  update game.player_quests set step = v_step + 1, updated_at = now(),
    data = data || jsonb_build_object('s' || (v_step + 1), game.now_ms())
   where player_id = v_pid and quest_id = 'mahkota';
  perform game.log(v_pid, 'Mahkota: langkah ' || (v_step + 1) || ' selesai.');

  return jsonb_build_object('mahkota', game.mk_state(v_pid), 'maju', true, 'gold', v_gold, 'oli', v_oli,
    'tanda', d ->> 'tanda', 'hasil', h, 'newGold', (select gold from game.players where player_id = v_pid));
end $$;
select game.expose('api_mahkota');

-- Alat GM ikut menyetel bendera Krisis Monopoli sesuai langkah.
create or replace function game.admin_mahkota(p_username text, p_step int) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid; s int; i int; d jsonb; k text;
begin
  select player_id into v_pid from game.players where lower(username) = lower(p_username);
  if v_pid is null then raise exception 'Pemain % tidak ditemukan.', p_username; end if;
  s := greatest(0, least(game.mk_ada(), coalesce(p_step, 0)));
  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'mahkota', s, '{}'::jsonb)
  on conflict (player_id, quest_id) do update set step = s, updated_at = now(), done_at = null;
  insert into game.mh_player(player_id, krisis) values (v_pid, s >= 2) on conflict (player_id) do update
    set krisis = s >= 2, tembus = false, gelap = false, paksa = false, aman = false,
        zona_tuju = null, gelap_city = null, gelap_cargo = '{}'::jsonb, updated_at = now();
  for i in 0 .. s - 1 loop
    d := game.mk_steps() -> i;
    if jsonb_typeof(d -> 'flags') = 'object' then
      for k in select jsonb_object_keys(d -> 'flags') loop
        if k = 'tembus' then update game.mh_player set tembus = (d -> 'flags' -> k)::text::boolean where player_id = v_pid;
        elsif k = 'gelap' then update game.mh_player set gelap = (d -> 'flags' -> k)::text::boolean where player_id = v_pid;
        elsif k = 'paksa' then update game.mh_player set paksa = (d -> 'flags' -> k)::text::boolean where player_id = v_pid;
        elsif k = 'aman' then update game.mh_player set aman = (d -> 'flags' -> k)::text::boolean where player_id = v_pid;
        end if;
      end loop;
    end if;
  end loop;
  return game.mk_state(v_pid);
end $$;
revoke all on function game.admin_mahkota(text, int) from public, anon, authenticated;

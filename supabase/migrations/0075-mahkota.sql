-- =====================================================================
-- 0075 · Saga 4 batch 3 — QUEST "MAHKOTA" langkah 1-15 (Q15 Stempel Biru, Q16 Turnamen Obor)
--   Konsep: claude/KONSEP-Saga4-Monopoli-dan-Mahkota.md v5.1 (40 langkah; 16-40 menyusul di batch 4-5).
--   Pola sama dengan 0064-peregrin: satu baris game.player_quests (quest_id = 'mahkota'),
--   satu langkah aktif, server menolak aksi untuk langkah lain (anti klik ganda / dua perangkat).
--
--   Pemicu: Saga 3 tamat (ps14 >= 6) + 1 hari game, dan gerbang MahkotaOpen (FiturPenguji ikut).
--   Efek yang dinyalakan quest ini:
--     langkah 2 selesai  -> Krisis Monopoli (game.mh_player.krisis, lihat 0074)
--     langkah 9 selesai  -> Zentul terbuka di peta (game.zentul_open)
--     langkah 12 selesai -> Garasi Yaptob terbuka
--     langkah 15 selesai -> Mesin Jolt Tahap 1: Sirkuit terbuka untuk latihan, waktu tempuh -10%
-- Aman diulang (idempoten).
-- =====================================================================

insert into game.config(key, value) values
  ('MahkotaOpen', '0'), ('MkGoldQ15', '50000'), ('MkGoldQ16', '75000'), ('MkOliDadu', '3')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Tabel langkah. Indeks 0 = langkah 1.
--   c    kota (null = pulau mana pun)         p  tempat/panel         b  kunci tombol (unik)
--   g    mini game (klien yang menilai)       t  'malam'
--   race lawan Trektrek-an                    gold kunci config hadiah bab
--   win  balapan wajib dimenangkan            arr dipicu saat kapal merapat
-- ---------------------------------------------------------------------
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
    {"n":15,"q":16,"c":"zentul","p":"garasi","b":"katup","g":"tempa","jolt":true,"gold":"MkGoldQ16"}
  ]'::jsonb
$$;

-- 40 langkah penuh; 16 ke atas menyusul. Quest tidak pernah ditandai tamat di batch ini.
create or replace function game.mk_last() returns int language sql immutable as $$ select 40 $$;
create or replace function game.mk_ada() returns int language sql immutable as $$ select jsonb_array_length(game.mk_steps()) $$;

create or replace function game.mk_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'mahkota'), 0) $$;

create or replace function game.mk_mulai(p_pid uuid) returns boolean
language sql stable as $$ select exists (select 1 from game.player_quests where player_id = p_pid and quest_id = 'mahkota') $$;

-- Hari game saat Saga 3 ditamatkan (null bila belum)
create or replace function game.mk_hari_saga3(p_pid uuid) returns int
language plpgsql stable as $$
declare v_at timestamptz; v_start bigint; v_len numeric;
begin
  select done_at into v_at from game.player_quests where player_id = p_pid and quest_id = 'ps14';
  if v_at is null then
    if game.ps_step(p_pid, 'ps14') >= 6 then return 0; end if;   -- tamat sebelum kolom done_at terisi
    return null;
  end if;
  v_start := game.cfg_num('WorldStartTimestamp', 0)::bigint;
  v_len := game.cfg_num('GameDayLengthRealMinutes', 60);
  if v_start = 0 or v_len <= 0 then return 0; end if;
  return floor((extract(epoch from v_at) * 1000 - v_start) / (v_len * 60000))::int;
exception when others then return null;
end $$;

-- Saga 3 tamat + 1 hari game + gerbang. Yang sudah mulai tetap boleh lanjut.
create or replace function game.mk_eligible(p_pid uuid) returns boolean
language plpgsql stable as $$
declare h int;
begin
  if p_pid is null or not game.fitur_on(p_pid, 'MahkotaOpen') then return false; end if;
  if game.mk_mulai(p_pid) then return true; end if;
  if game.ps_step(p_pid, 'ps14') < 6 then return false; end if;
  if coalesce(game.pasir_era(p_pid), 'kini') <> 'kini' then return false; end if;
  h := game.mk_hari_saga3(p_pid);
  return h is not null and game.game_day() > h;
exception when others then return false;
end $$;

create or replace function game.mk_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v_step int; v_d jsonb;
begin
  if p_pid is null or not game.mk_eligible(p_pid) then return null; end if;
  select step, data into v_step, v_d from game.player_quests where player_id = p_pid and quest_id = 'mahkota';
  v_step := coalesce(v_step, 0);
  return jsonb_build_object(
    'step', v_step,                                  -- langkah yang sudah selesai (0 = belum mulai)
    'ada', game.mk_ada(),                            -- langkah yang sudah dikoding
    'last', game.mk_last(),
    'd', game.mk_steps() -> v_step,                  -- definisi langkah aktif (null bila belum dikoding)
    'data', coalesce(v_d, '{}'::jsonb),
    'jolt', v_step >= 15,
    'garasi', v_step >= 12,
    'zentul', v_step >= 9);
exception when others then return null;
end $$;

-- ---------------------------------------------------------------------
-- api_mahkota([aksi, langkah, hasil])
--   status                         -> {mahkota}
--   maju   , n, 'ok'|'menang'|...  -> majukan satu langkah
--   balap  , n                     -> mulai Trektrek-an langkah balapan
--   selesai, n, run, log           -> catat hasil balapan, majukan bila syaratnya terpenuhi
-- ---------------------------------------------------------------------
create or replace function public.api_mahkota(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status');
  v_want int := game.arg_int(a, 1);
  v_res text := lower(btrim(coalesce(game.arg(a, 2), '')));
  v_step int; d jsonb; v_city text; v_gold bigint := 0; v_oli int := 0; v_id uuid; h jsonb; t jsonb;
begin
  if v_act = 'status' then return jsonb_build_object('mahkota', game.mk_state(v_pid)); end if;
  if v_act not in ('maju', 'balap', 'selesai') then raise exception 'Aksi tidak dikenal.'; end if;
  if not game.mk_eligible(v_pid) then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;
  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;

  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'mahkota', 0, '{}'::jsonb)
  on conflict (player_id, quest_id) do nothing;
  select step into v_step from game.player_quests where player_id = v_pid and quest_id = 'mahkota' for update;

  if v_step >= game.mk_ada() then raise exception 'Ceritanya berhenti di sini dulu, Kapten. Bersambung.'; end if;
  if v_want is null or v_want <> v_step then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;

  d := game.mk_steps() -> v_step;
  v_city := game.current_city(v_pid);
  if d ? 'c' and v_city is distinct from (d ->> 'c') then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;
  if d ->> 't' = 'malam' and not game.fish_is_night() then raise exception 'Datanglah lagi saat lampu-lampu dinyalakan, Kapten.'; end if;

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
    -- langkah 12: kalah pun ceritanya jalan terus (justru itu alasan ke Yaptob)
    if coalesce((d ->> 'win')::boolean, false) and not coalesce((h ->> 'win')::boolean, false) then
      return jsonb_build_object('hasil', h, 'mahkota', game.mk_state(v_pid), 'maju', false);
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
    'hasil', h, 'newGold', (select gold from game.players where player_id = v_pid));
end $$;
select game.expose('api_mahkota');

-- Alat GM (SQL Editor): select game.admin_mahkota('abuy', 11);
create or replace function game.admin_mahkota(p_username text, p_step int) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid; s int;
begin
  select player_id into v_pid from game.players where lower(username) = lower(p_username);
  if v_pid is null then raise exception 'Pemain % tidak ditemukan.', p_username; end if;
  s := greatest(0, least(game.mk_ada(), coalesce(p_step, 0)));
  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'mahkota', s, '{}'::jsonb)
  on conflict (player_id, quest_id) do update set step = s, updated_at = now(), done_at = null;
  if s >= 2 then
    insert into game.mh_player(player_id, krisis) values (v_pid, true)
    on conflict (player_id) do update set krisis = true, updated_at = now();
  else
    update game.mh_player set krisis = false, zona_tuju = null, gelap_city = null, updated_at = now() where player_id = v_pid;
  end if;
  return game.mk_state(v_pid);
end $$;
revoke all on function game.admin_mahkota(text, int) from public, anon, authenticated;

-- =====================================================================
-- KAIT: Zentul, Sirkuit, kapal Trektrek-an, waktu tempuh
-- =====================================================================

-- Zentul muncul di peta setelah langkah 9 (penguji TrekOpen tetap bisa melihatnya)
create or replace function game.zentul_open(p_pid uuid) returns boolean
language sql stable as $$ select game.fitur_on(p_pid, 'TrekOpen') or game.mk_step(p_pid) >= 9 $$;

-- Sirkuit: penguji dari mana saja selama TrekOpen masih 0; selebihnya wajib merapat di Zentul
-- dan sudah punya Mesin Jolt (langkah 15).
create or replace function game.trek_boleh(p_pid uuid) returns boolean
language sql stable as $$
  select case
    when p_pid is null then false
    when game.fitur_on(p_pid, 'TrekOpen') and lower(coalesce(game.cfg('TrekOpen'), '0')) not in ('1', 'true', 'on', 'ya') then true
    when game.in_transit(p_pid) or game.current_city(p_pid) is distinct from 'zentul' then false
    else game.fitur_on(p_pid, 'TrekOpen') or game.mk_step(p_pid) >= 15
  end
$$;

-- Kapal: sebelum Mesin Jolt dipasang, kapal sendiri (berat, zona sempit).
create or replace function game.trek_kapal(p_pid uuid) returns text
language sql stable as $$
  select case when game.mk_step(p_pid) >= 15 or not game.mk_mulai(p_pid) then 'jolt' else 'tanpa' end
$$;

-- Lawan latihan Sirkuit selama saga: yang sudah pernah ditemui.
create or replace function game.trek_lawan(p_pid uuid) returns text[]
language sql stable as $$
  select case
    when not game.mk_mulai(p_pid) then array['pariopelan', 'kapalmber', 'cangcimen', 'yaptob']
    when game.mk_step(p_pid) >= 15 then array['pariopelan']
    else array[]::text[]
  end
$$;

-- Mesin Jolt pinjaman: waktu tempuh -10% selama saga (bertumpuk dengan buku, batas tercepat tetap).
do $$
begin
  drop function if exists game.ship_json_mk(uuid);
  alter function game.ship_json(uuid) rename to ship_json_mk;
end $$;
revoke all on function game.ship_json_mk(uuid) from public, anon, authenticated;

create or replace function game.ship_json(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare j jsonb; s int;
begin
  j := game.ship_json_mk(p_pid);
  if j is null then return j; end if;
  begin
    s := game.mk_step(p_pid);
    if s >= 15 and s < game.mk_last() then
      j := j || jsonb_build_object('TravelMul', coalesce((j ->> 'TravelMul')::numeric, 1) * 0.9, 'Jolt', true);
    end if;
  exception when others then null;
  end;
  return j;
end $$;

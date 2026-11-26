-- =====================================================================
-- 0107 · S5 Bagian I (Mare, langkah 1-19, Q23-Q25)
--
--   Penyimpanan: game.player_quests quest_id = 's5', step = langkah yang sudah selesai (0..19 di fase ini).
--   Pemicu langkah 1: Saga 4 Bagian II tamat (quest 'mahkota2' done_at) + S5JedaHari (3) hari game,
--     zaman kini, gerbang S5aOpen (FiturPenguji) ATAU mode uji GM (s5_state.data.uji).
--   Klien menerima key 's5' di getGameState HANYA bila pemain berhak (tidak dikirim sebagai null).
--   Mini game lama dinilai klien ('ok'); Dengar Tanah (langkah 3, 19) dinilai server lewat mg_session.
--   Langkah 17 memeriksa Mesin Jolt Warlord (game.wl_has(pid, 'speed')).
--   Hadiah: Q23 di langkah 6, Q24 di langkah 12. Q25 dibayar di langkah 20 (Fase B).
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('S5JedaHari', '3'),
  ('S5GoldQ23', '250000'), ('S5GoldQ24', '300000'), ('S5GoldQ25', '350000'),
  ('S5GoldQ26', '350000'), ('S5GoldQ27', '350000'), ('S5GoldQ28', '350000'), ('S5GoldQ29', '350000'),
  ('S5GoldQ30', '350000'), ('S5GoldQ31', '350000'), ('S5GoldQ32', '400000'), ('S5GoldQ33', '600000')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Tabel langkah. Indeks 0 = langkah 1.
--   c kota (tanpa c = pulau mana pun) · p tempat · g mini game klien · mg preset Dengar Tanah (server)
--   t 'malam' · gold kenop hadiah · pilih daftar pilihan · warlord syarat Mesin Jolt Warlord
-- ---------------------------------------------------------------------
create or replace function game.s5_steps() returns jsonb
language sql immutable as $$
  select '[
    {"n":1, "q":23, "p":"tavern", "b":"bisikan"},
    {"n":2, "q":23, "c":"toogood", "p":"tavern", "b":"dwi", "g":"jejak"},
    {"n":3, "q":23, "c":"bjorneo", "p":"tavern", "b":"getaran", "mg":"cari_lereng"},
    {"n":4, "q":23, "c":"bjorneo", "p":"tavern", "b":"opung", "g":"pantun"},
    {"n":5, "q":23, "c":"joungjava", "p":"market", "b":"etalase", "g":"manifest"},
    {"n":6, "q":23, "c":"joungjava", "p":"market", "b":"tepi", "gold":"S5GoldQ23"},
    {"n":7, "q":24, "c":"bjorneo", "p":"ship", "b":"selam", "g":"selam"},
    {"n":8, "q":24, "c":"bjorneo", "p":"ship", "b":"lambung"},
    {"n":9, "q":24, "c":"bjorneo", "p":"tavern", "b":"cap", "g":"pelikan"},
    {"n":10,"q":24, "c":"karang_garam", "p":"tavern", "b":"lunas", "g":"angin"},
    {"n":11,"q":24, "c":"karang_garam", "p":"tavern", "b":"tetua", "g":"warga"},
    {"n":12,"q":24, "c":"joungjava", "p":"market", "b":"kebenaran", "pilih":["luruskan","biarkan"], "gold":"S5GoldQ24"},
    {"n":13,"q":25, "c":"otoland", "p":"tavern", "b":"kincir", "g":"jejak"},
    {"n":14,"q":25, "c":"otoland", "p":"tavern", "b":"basahi", "g":"tercecer"},
    {"n":15,"q":25, "c":"sowtour", "p":"tavern", "b":"cermin", "g":"sandi", "t":"malam"},
    {"n":16,"q":25, "c":"sowtour", "p":"tavern", "b":"syarat"},
    {"n":17,"q":25, "c":"zentul", "p":"garasi", "b":"lambung", "warlord":true},
    {"n":18,"q":25, "c":"bjorneo", "p":"tavern", "b":"serpihan", "g":"manifest"},
    {"n":19,"q":25, "c":"bjorneo", "p":"tavern", "b":"airterjun", "mg":"lagu_tidur", "t":"malam"}
  ]'::jsonb
$$;
create or replace function game.s5_ada() returns int language sql immutable as $$ select jsonb_array_length(game.s5_steps()) $$;

create or replace function game.s5_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 's5'), 0) $$;
create or replace function game.s5_mulai(p_pid uuid) returns boolean
language sql stable as $$ select exists (select 1 from game.player_quests where player_id = p_pid and quest_id = 's5') $$;

-- Mode uji GM: membuka S5 hanya untuk akun GM yang menyalakannya (tanpa FiturPenguji)
create or replace function game.s5_uji(p_pid uuid) returns boolean
language sql stable as $$
  select coalesce((select (data ->> 'uji')::boolean from game.s5_state where player_id = p_pid), false) and game.is_gm(p_pid)
$$;
create or replace function game.s5_on(p_pid uuid) returns boolean
language sql stable as $$ select game.fitur_on(p_pid, 'S5aOpen') or game.s5_uji(p_pid) $$;

-- Hari game saat Saga 4 Bagian II tamat
create or replace function game.s5_hari_s4(p_pid uuid) returns int
language plpgsql stable as $$
declare v_at timestamptz; v_start bigint; v_len numeric;
begin
  select done_at into v_at from game.player_quests where player_id = p_pid and quest_id = 'mahkota2' and done_at is not null;
  if v_at is null then return null; end if;
  v_start := game.cfg_num('WorldStartTimestamp', 0)::bigint;
  v_len := game.cfg_num('GameDayLengthRealMinutes', 60);
  if v_start = 0 or v_len <= 0 then return 0; end if;
  return floor((extract(epoch from v_at) * 1000 - v_start) / (v_len * 60000))::int;
exception when others then return null;
end $$;

create or replace function game.s5_eligible(p_pid uuid) returns boolean
language plpgsql stable as $$
declare h int;
begin
  if p_pid is null or not game.s5_on(p_pid) then return false; end if;
  if game.s5_mulai(p_pid) then return true; end if;
  if coalesce(game.pasir_era(p_pid), 'kini') <> 'kini' then return false; end if;
  h := game.s5_hari_s4(p_pid);
  return h is not null and game.game_day() >= h + greatest(0, game.cfg_num('S5JedaHari', 3))::int;
exception when others then return false;
end $$;

create or replace function game.s5_malam() returns boolean language sql stable as $$ select game.fish_is_night() $$;

-- Syarat Mesin Jolt Warlord satu per satu (langkah 17)
create or replace function game.s5_warlord(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v_n int := greatest(0, game.cfg_num('WarlordBahan', 6))::int; v_oli int := greatest(0, game.cfg_num('WarlordOli', 10))::int;
  v_gold bigint := greatest(0, game.cfg_num('WarlordGold', 2500000))::bigint; v_bahan text := game.wl_bahan('speed');
begin
  return jsonb_build_object(
    'terpasang', game.wl_has(p_pid, 'speed'),
    'mentok', game.wl_siap(p_pid, 'speed'),
    'gold', v_gold, 'punyaGold', (select gold from game.players where player_id = p_pid),
    'oli', v_oli, 'punyaOli', game.item_qty(p_pid, 'oli_hitam'),
    'bahanN', v_n, 'punyaBahan', game.item_qty(p_pid, v_bahan),
    'bahanNama', coalesce((select name from game.commodities where id = v_bahan), (select name from game.item_catalog where item_id = v_bahan), v_bahan));
exception when others then return jsonb_build_object('terpasang', false);
end $$;

create or replace function game.s5_view(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v int; d jsonb;
begin
  if not game.s5_eligible(p_pid) then return null; end if;
  select step, data into v, d from game.player_quests where player_id = p_pid and quest_id = 's5';
  v := coalesce(v, 0); d := coalesce(d, '{}'::jsonb);
  return jsonb_build_object(
    'step', v, 'ada', game.s5_ada(), 'd', game.s5_steps() -> v, 'data', d,
    'dunia', game.s5_dunia(p_pid),
    'warlord', case when coalesce((game.s5_steps() -> v ->> 'warlord')::boolean, false) then game.s5_warlord(p_pid) end,
    'gerbangB', game.fitur_on(p_pid, 'S5bOpen') or game.s5_uji(p_pid));
exception when others then return null;
end $$;

-- ---------------------------------------------------------------------
-- Mini game Dengar Tanah: izin & efek (mendefinisikan ulang hook 0105)
-- ---------------------------------------------------------------------
create or replace function game.s5_mg_izin(p_pid uuid, p_kind text, p_ctx text, p_preset text, p_step int) returns text
language plpgsql stable as $$
declare v int; d jsonb;
begin
  if p_kind = 'uji' and game.is_gm(p_pid) then return null; end if;
  -- uji coba GM (Panel GM): semua preset mini game S5, tanpa efek ke quest
  if p_kind in ('listen', 'wave') and p_ctx = 'trial' and game.is_gm(p_pid) then return null; end if;
  if p_kind in ('listen', 'wave') and p_ctx = 'quest' and game.s5_eligible(p_pid) then
    if game.in_transit(p_pid) then return 'Merapat dulu di pelabuhan, Kapten.'; end if;
    v := game.s5_step(p_pid); d := game.s5_steps() -> v;
    if d is null or p_step is distinct from (d ->> 'n')::int or d ->> 'mg' is distinct from p_preset
       or coalesce(d ->> 'mgk', 'listen') <> p_kind then
      return 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.';
    end if;
    if d ? 'c' and game.current_city(p_pid) is distinct from (d ->> 'c') then return 'Tanah di sini diam, Kapten.'; end if;
    if d ->> 't' = 'malam' and not game.s5_malam() then return 'Datanglah lagi saat lampu dinyalakan, Kapten.'; end if;
    return null;
  end if;
  return 'Belum ada yang menunggu di sini, Kapten.';
end $$;

create or replace function game.s5_mg_efek(p_pid uuid, p_s game.mg_session, p_won boolean) returns jsonb
language plpgsql as $$
begin
  if p_won and p_s.kind in ('listen', 'wave') and p_s.context = 'quest' and p_s.step_ref is not null then
    update game.player_quests set data = data || jsonb_build_object('mg' || p_s.step_ref, p_s.id::text), updated_at = now()
     where player_id = p_pid and quest_id = 's5';
    return jsonb_build_object('langkah', p_s.step_ref, 'siap', true);
  end if;
  return '{}'::jsonb;
end $$;

-- ---------------------------------------------------------------------
-- Aksi pemain
--   status
--   maju  , n, 'ok'            -> selesaikan langkah aktif n (mini game lama dinilai klien)
--   pilih , n, pilihan         -> langkah berpilihan
-- ---------------------------------------------------------------------
create or replace function game.s5_act(p_pid uuid, a jsonb) returns jsonb
language plpgsql as $$
declare
  v_act text := lower(coalesce(game.arg(a, 0), 'status'));
  v_want int := game.arg_int(a, 1);
  v_res text := lower(btrim(coalesce(game.arg(a, 2), '')));
  v_step int; v_data jsonb; d jsonb; v_gold bigint := 0; v_city text;
begin
  if v_act = 'status' then return jsonb_build_object('s5', game.s5_view(p_pid)); end if;
  if v_act not in ('maju', 'pilih') or not game.s5_eligible(p_pid) then raise exception 'Aksi tidak dikenal.'; end if;
  if game.in_transit(p_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;
  if game.s5_dunia(p_pid) <> 'mare' then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;

  insert into game.player_quests(player_id, quest_id, step, data) values (p_pid, 's5', 0, '{}'::jsonb)
  on conflict (player_id, quest_id) do nothing;
  select step, data into v_step, v_data from game.player_quests where player_id = p_pid and quest_id = 's5' for update;
  v_data := coalesce(v_data, '{}'::jsonb);

  if v_step >= game.s5_ada() then raise exception 'Bersambung, Kapten. Gunung itu tidak akan lari.'; end if;
  d := game.s5_steps() -> v_step;
  if v_want is null or v_want <> (d ->> 'n')::int then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;
  v_city := game.current_city(p_pid);
  if d ? 'c' and v_city is distinct from (d ->> 'c') then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;
  if d ->> 't' = 'malam' and not game.s5_malam() then raise exception 'Datanglah lagi saat lampu dinyalakan, Kapten.'; end if;

  if d ? 'pilih' then
    if v_act <> 'pilih' then raise exception 'Keputusannya ada di tanganmu, Kapten.'; end if;
    if not (d -> 'pilih' @> to_jsonb(v_res)) then raise exception 'Pilihan tidak dikenali.'; end if;
    v_data := v_data || jsonb_build_object('kabar_buku', v_res);
  elsif v_act = 'pilih' then
    raise exception 'Tidak ada yang harus dipilih di sini, Kapten.';
  end if;

  if d ? 'mg' and not (v_data ? ('mg' || (d ->> 'n'))) then raise exception 'Tanah belum menjawab, Kapten. Dengarkan lagi.'; end if;
  if d ? 'g' and v_res <> 'ok' then raise exception 'Belum berhasil, Kapten. Coba lagi.'; end if;
  if coalesce((d ->> 'warlord')::boolean, false) and not game.wl_has(p_pid, 'speed') then
    raise exception 'Lambungmu belum lurus, Kapten. Mesin Jolt Warlord belum terpasang.';
  end if;

  if d ? 'gold' then
    v_gold := greatest(0, game.cfg_num(d ->> 'gold', 0))::bigint;
    if v_gold > 0 then update game.players set gold = gold + v_gold where player_id = p_pid; end if;
  end if;

  update game.player_quests set step = v_step + 1, updated_at = now(),
    data = v_data || jsonb_build_object('s' || (d ->> 'n'), game.now_ms())
   where player_id = p_pid and quest_id = 's5';
  perform game.log(p_pid, case when v_gold > 0 then 'Jejak gunung: bab ' || (d ->> 'q') || ' selesai (+' || v_gold || ' gold).'
                               else 'Jejak gunung: langkah ' || (d ->> 'n') || ' selesai.' end);

  return jsonb_build_object('s5', game.s5_view(p_pid), 'maju', true, 'gold', v_gold, 'q', (d ->> 'q')::int,
    'newGold', (select gold from game.players where player_id = p_pid));
end $$;
revoke all on function game.s5_act(uuid, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Alat uji GM
--   gm_uji, '1'|'0'      mode uji S5 untuk akun GM ini saja
--   gm_langkah, n        langkah aktif = n (1..19); data mini game direset, quest dimulai bila belum
--   gm_dunia / gm_reset_hari / gm_status (0105)
-- ---------------------------------------------------------------------
create or replace function game.s5_gm_status(p_pid uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'dunia', game.s5_dunia(p_pid),
    'hari', game.game_day(),
    'crossDay', (select cross_day from game.s5_state where player_id = p_pid),
    'bisa', game.s5_bisa_seberang(p_pid),
    'gerbang', jsonb_build_object('a', game.cfg('S5aOpen'), 'b', game.cfg('S5bOpen'), 'c', game.cfg('S5cOpen')),
    'penguji', coalesce(game.cfg('FiturPenguji'), ''),
    'uji', game.s5_uji(p_pid),
    'langkah', case when game.s5_mulai(p_pid) then game.s5_step(p_pid) + 1 end,
    'ada', game.s5_ada())
$$;

create or replace function game.s5_gm_act(p_pid uuid, a jsonb) returns jsonb
language plpgsql as $$
declare v_act text := lower(coalesce(game.arg(a, 0), '')); v_ke text := lower(coalesce(game.arg(a, 1), '')); v_n int;
begin
  if not game.is_gm(p_pid) then raise exception 'Aksi tidak dikenal.'; end if;
  perform game.s5_row(p_pid);
  if v_act = 'gm_dunia' then
    if v_ke not in ('mare', 'seberang') then raise exception 'Pilih mare atau seberang.'; end if;
    update game.s5_state set dunia = v_ke, updated_at = now() where player_id = p_pid;
    perform game.mp_touch(p_pid);
  elsif v_act = 'gm_reset_hari' then
    update game.s5_state set cross_day = null, tiket_day = null, updated_at = now() where player_id = p_pid;
  elsif v_act = 'gm_uji' then
    update game.s5_state set data = data || jsonb_build_object('uji', v_ke in ('1', 'true', 'on')), updated_at = now() where player_id = p_pid;
  elsif v_act = 'gm_langkah' then
    v_n := nullif(v_ke, '')::int;
    if v_n is null or v_n < 1 or v_n > game.s5_ada() + 1 then raise exception 'Langkah 1 sampai %.', game.s5_ada() + 1; end if;
    insert into game.player_quests(player_id, quest_id, step, data) values (p_pid, 's5', v_n - 1, '{}'::jsonb)
    on conflict (player_id, quest_id) do update set step = v_n - 1, updated_at = now(),
      data = (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from jsonb_each(game.player_quests.data) where key not like 'mg%');
    perform game.log(p_pid, '[GM] Uji jejak gunung: lompat ke langkah ' || v_n || '.');
  elsif v_act <> 'gm_status' then
    raise exception 'Aksi tidak dikenal.';
  end if;
  return jsonb_build_object('ok', true, 'gm', game.s5_gm_status(p_pid), 's5', game.s5_view(p_pid));
end $$;

create or replace function public.api_s5(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); v_act text := lower(coalesce(game.arg(a, 0), 'status'));
begin
  if v_pid is null then raise exception 'Aksi tidak dikenal.'; end if;
  if v_act like 'gm\_%' then return game.s5_gm_act(v_pid, a); end if;
  if not game.s5_eligible(v_pid) then raise exception 'Aksi tidak dikenal.'; end if;
  return game.s5_act(v_pid, a);
end $$;
select game.expose('api_s5');

-- Alat SQL GM (pola admin_mahkota)
create or replace function game.admin_s5(p_username text, p_langkah int) returns jsonb
language plpgsql as $$
declare v_pid uuid;
begin
  select player_id into v_pid from game.players where lower(username) = lower(p_username);
  if v_pid is null then raise exception 'Pemain tidak ditemukan.'; end if;
  if p_langkah < 1 or p_langkah > game.s5_ada() + 1 then raise exception 'Langkah 1 sampai %.', game.s5_ada() + 1; end if;
  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 's5', p_langkah - 1, '{}'::jsonb)
  on conflict (player_id, quest_id) do update set step = p_langkah - 1, updated_at = now();
  return game.s5_view(v_pid);
end $$;
revoke all on function game.admin_s5(text, int) from public, anon, authenticated;

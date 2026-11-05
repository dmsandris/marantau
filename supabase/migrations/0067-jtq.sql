-- =====================================================================
-- Marantau (Supabase) - 0067 QUEST RAHASIA "BUNGA YANG TAK PERNAH DIPETIK" (Rekening J.T.)
-- ---------------------------------------------------------------------
-- Konsep: claude/KONSEP-Quest-Rekening-JT.md (v3.1).
-- Side quest di luar Saga 3. Terbuka setelah Saga 2 selesai (duatangan step >= 5), saat panel Bank
-- Marie Regal dibuka, dan HANYA bila tidak ada side quest lain yang sedang berjalan (game.side_quest_active, 0064).
-- Rahasia sepenuhnya: tanpa Tanda Jasa khusus, jurnal, log pemain, chat dunia khusus quest, atau Realtime.
-- Dibekukan selama Saga 3 aktif untuk pemain itu.
--
-- Langkah (game.player_quests, quest_id = 'jtq'); step = langkah BERIKUTNYA yang dijalankan.
--   0 Marie Regal  · Bank   : Meja Kas B (l0)          5 TooGood (malam) · Bank : Meja Kas A (l5)
--   1 em pe'er de pe'er · Bank : cerita                6 Rantai Lama · Balai Kongsi : cerita (jalur dikunci di sini)
--   2 FreeYork · Bank       : Meja Kas A (l2)          7 IKN (malam) · Bank : Olah Jejak (mini game lama)
--   3 Otoland · Koperasi    : Meja Kas B (l3)          8 IKN · Bank : Meja Kas B final (l8)
--   4 Sunda · Bank          : Buku Besar (manifest)    9 IKN · Bank : pilihan -> 10 selesai (satu transaksi)
-- Aksi:
--   api_jtq(['status'])
--   api_jtq(['level', step])                definisi level Meja Kas / Buku Besar langkah itu
--   api_jtq(['maju', step, hasil])          hasil: Meja Kas A {w:[{l,r}],pick} / Meja Kas B [[{kind:n}...]...] /
--                                           Buku Besar [id slip...] / 'ok' (cerita & Olah Jejak)
--   api_jtq(['pilih', 9, 'setuju'|'tolak'])
-- Jalur setuju: sumbangan BERTINGKAT (config JtqTiers) ke Kolam Restorasi IKN, masuk total pribadi.
--   Urutan sendiri (game.jtq_rank, terpisah dari TheDuneks), hanya pemain biasa yang memilih setuju.
--   Tanpa chat "menyumbang N gold"; pengumuman tahap kolam tetap seperti biasa (game.gr_pool_add, 0032).
--   Kolam sudah penuh -> jalur Kamp Pemulung (cerita saja, tanpa urutan).
-- Jalur tolak: JtqUpah gold.
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('JtqTiers', '5000000,4000000,3000000,2000000,500000'),
  ('JtqUpah', '250000')
on conflict (key) do nothing;
-- daftar side quest (aturan satu per satu, 0064)
insert into game.config(key, value) values ('SideQuestIds', 'peregrin,duneks,jtq')
on conflict (key) do update set value = case
  when string_to_array(replace(game.config.value, ' ', ''), ',') @> array['jtq'] then game.config.value
  else nullif(btrim(game.config.value, ', '), '') || ',jtq' end;
update game.config set value = 'peregrin,duneks,jtq' where key = 'SideQuestIds' and coalesce(value, '') = '';

-- jejak audit GM: porsi sumbangan dari quest ini (ikut kolom total)
alter table game.gr_donations add column if not exists jtq bigint not null default 0;

-- urutan penyumbang quest ini (hanya pemain biasa). rank null = tolak / Kamp Pemulung.
create table if not exists game.jtq_rank (
  player_id uuid primary key references game.players(player_id) on update cascade on delete cascade,
  rank      int unique,
  choice    text not null,
  amount    bigint not null default 0,
  at        timestamptz not null default now()
);
alter table game.jtq_rank enable row level security;

-- ---------------------------------------------------------------------
-- Data langkah & level
-- p = panel tempat langkah berjalan (bank | kongsi). t = 'malam'. g = mini game. lv = kunci level.
-- ---------------------------------------------------------------------
create or replace function game.jt_steps() returns jsonb
language sql immutable as $$
  select '[
    {"c":"marie_regal","p":"bank","g":"kas","lv":"l0"},
    {"c":"empeer_depeer","p":"bank"},
    {"c":"freeyork","p":"bank","g":"timbang","lv":"l2"},
    {"c":"otoland","p":"bank","g":"kas","lv":"l3"},
    {"c":"sunda_empire","p":"bank","g":"manifest","lv":"bukubesar"},
    {"c":"toogood","p":"bank","t":"malam","g":"timbang","lv":"l5"},
    {"c":"rantai_lama","p":"kongsi"},
    {"c":"ikn","p":"bank","t":"malam","g":"jejak"},
    {"c":"ikn","p":"bank","g":"kas","lv":"l8"},
    {"c":"ikn","p":"bank","pilih":true}
  ]'::jsonb
$$;
create or replace function game.jt_last() returns int language sql immutable as $$ select 10 $$;

-- Level Meja Kas & Buku Besar. Nilai koin dalam kepeng.
--   kas    : kinds [{id,val}], rounds [{ask, trays:[jumlah...], stock:{kind:n baik}, cracked:{kind:n retak}, min: n|null}]
--   timbang: n koin (c1..cn), odd = koin yang lebih berat, max = batas timbang (lilin)
--   manifest (Buku Besar): sama dengan dn_check_manifest (0065): slip tidak cocok bila jumlah/cap/berat beda.
-- Semua level dijamin bisa diselesaikan (solver di test/jtq-solver.js).
create or replace function game.jt_levels() returns jsonb
language sql immutable as $LV$ select '{
  "l0":{"mode":"kas","theme":"regal","kinds":[{"id":"kepeng","val":1},{"id":"kuantum","val":20}],
    "rounds":[
      {"ask":"Cadangan laci pertama","trays":[47],"stock":{"kepeng":12,"kuantum":3},"cracked":{},"min":null},
      {"ask":"Cadangan laci kedua","trays":[63],"stock":{"kepeng":9,"kuantum":4},"cracked":{},"min":null},
      {"ask":"Cadangan laci ketiga","trays":[85],"stock":{"kepeng":10,"kuantum":5},"cracked":{},"min":null}]},
  "l2":{"mode":"timbang","theme":"rantai","n":8,"odd":["c6"],"max":3},
  "l3":{"mode":"kas","theme":"koperasi","kinds":[{"id":"kepeng","val":1},{"id":"rantai","val":5},{"id":"gulden","val":10}],
    "rounds":[
      {"ask":"Santunan untuk Mak Sarni","trays":[37],"stock":{"kepeng":8,"rantai":4,"gulden":3},"cracked":{"gulden":1},"min":null},
      {"ask":"Santunan untuk Mak Ijem","trays":[54],"stock":{"kepeng":6,"rantai":5,"gulden":4},"cracked":{"rantai":2},"min":null},
      {"ask":"Santunan untuk Mak Romlah","trays":[68],"stock":{"kepeng":9,"rantai":6,"gulden":5},"cracked":{"gulden":2,"kepeng":1},"min":11}]},
  "l5":{"mode":"timbang","theme":"rentenir","n":12,"odd":["c4","c9"],"max":4},
  "l8":{"mode":"kas","theme":"brankas","kinds":[{"id":"kepeng","val":1},{"id":"rantai","val":5},{"id":"gulden","val":10},{"id":"giok","val":30}],
    "rounds":[
      {"ask":"Emas yang sungguh ada: laci kas kota","trays":[96],"stock":{"kepeng":8,"rantai":5,"gulden":6,"giok":2},"cracked":{"giok":1},"min":null},
      {"ask":"Emas yang sungguh ada: laci santunan","trays":[143],"stock":{"kepeng":7,"rantai":4,"gulden":6,"giok":4},"cracked":{"gulden":2},"min":9},
      {"ask":"Emas yang sungguh ada: tiga baki untuk tiga kas","trays":[45,72,38],"stock":{"kepeng":9,"rantai":6,"gulden":8,"giok":3},"cracked":{"giok":1,"rantai":1},"min":null}]},
  "bukubesar":{"mode":"manifest","theme":"bank","numerals":true,
    "rows":[
      {"id":"r1","label":"Setoran gaji, bulan 1","qty":1,"cap":"syahbandar","berat":"1 keping"},
      {"id":"r2","label":"Setoran gaji, bulan 2","qty":1,"cap":"syahbandar","berat":"1 keping"},
      {"id":"r3","label":"Setoran gaji, bulan 3","qty":2,"cap":"syahbandar","berat":"2 keping"},
      {"id":"r4","label":"Setoran gaji, bulan 4","qty":2,"cap":"syahbandar","berat":"2 keping"},
      {"id":"r5","label":"Setoran gaji, bulan 5","qty":2,"cap":"syahbandar","berat":"2 keping"},
      {"id":"r6","label":"Setoran gaji, bulan 6","qty":3,"cap":"syahbandar","berat":"3 keping"},
      {"id":"r7","label":"Setoran gaji, bulan 7","qty":3,"cap":"syahbandar","berat":"3 keping"},
      {"id":"r8","label":"Setoran gaji, bulan 8","qty":3,"cap":"syahbandar","berat":"3 keping"},
      {"id":"r9","label":"Setoran gaji, bulan 9","qty":4,"cap":"syahbandar","berat":"4 keping"},
      {"id":"r10","label":"Setoran gaji, bulan 10","qty":4,"cap":"syahbandar","berat":"4 keping"},
      {"id":"r11","label":"Setoran gaji, bulan 11","qty":4,"cap":"syahbandar","berat":"4 keping"},
      {"id":"r12","label":"Setoran gaji, bulan 12","qty":5,"cap":"syahbandar","berat":"5 keping"}],
    "crates":[
      {"id":"b7","row":"r7","label":"Setoran gaji, bulan 7","qty":3,"cap":"syahbandar","berat":"3 keping"},
      {"id":"b2","row":"r2","label":"Setoran gaji, bulan 2","qty":1,"cap":"syahbandar","berat":"1 keping"},
      {"id":"b10","row":"r10","label":"Setoran gaji, bulan 10","qty":2,"cap":"syahbandar","berat":"4 keping","jt":true,"note":"sisihan gaji, untuk kas kota"},
      {"id":"b5","row":"r5","label":"Setoran gaji, bulan 5","qty":2,"cap":"syahbandar","berat":"2 keping"},
      {"id":"b12","row":"r12","label":"Setoran gaji, bulan 12","qty":5,"cap":"syahbandar","berat":"5 keping"},
      {"id":"b4","row":"r4","label":"Setoran gaji, bulan 4","qty":1,"cap":"syahbandar","berat":"2 keping","jt":true,"note":"beras anak dermaga"},
      {"id":"b9","row":"r9","label":"Setoran gaji, bulan 9","qty":4,"cap":"syahbandar","berat":"4 keping"},
      {"id":"b1","row":"r1","label":"Setoran gaji, bulan 1","qty":1,"cap":"syahbandar","berat":"1 keping"},
      {"id":"b11","row":"r11","label":"Setoran gaji, bulan 11","qty":4,"cap":"syahbandar","berat":"4 keping"},
      {"id":"b6","row":"r6","label":"Setoran gaji, bulan 6","qty":3,"cap":"syahbandar","berat":"3 keping"},
      {"id":"b8","row":"r8","label":"Setoran gaji, bulan 8","qty":3,"cap":"balai","berat":"3 keping","jt":true,"note":"untuk janda nelayan"},
      {"id":"b3","row":"r3","label":"Setoran gaji, bulan 3","qty":2,"cap":"syahbandar","berat":"2 keping"}]}
}'::jsonb $LV$;

create or replace function game.jt_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'jtq'), 0) $$;

-- Saga 2 selesai, dan (sudah pernah dimulai, atau tidak ada side quest lain yang sedang berjalan)
create or replace function game.jt_eligible(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  if p_pid is null or game.dt_step(p_pid) < 5 then return false; end if;
  if exists (select 1 from game.player_quests where player_id = p_pid and quest_id = 'jtq') then return true; end if;
  return game.side_quest_active(p_pid, 'jtq') is null;
exception when others then return false;
end $$;

-- Dibekukan selama Saga 3 aktif (sama dengan aturan TheDuneks)
create or replace function game.jt_frozen(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  if not game.pasir_aktif(p_pid) then return false; end if;
  if game.ps_step(p_pid, 'ps14') >= 6 then return false; end if;
  if game.is_gm(p_pid) and not exists (select 1 from game.pasir_state where player_id = p_pid) then return false; end if;
  return true;
exception when others then return false;
end $$;

-- Saga 3 sudah tamat untuk pemain ini (gema kecil, §10 konsep)
create or replace function game.jt_saga3(p_pid uuid) returns boolean
language plpgsql stable as $$
begin return game.ps_step(p_pid, 'ps14') >= 6;
exception when others then return false;
end $$;

-- Jalur pembawa kabar "Tedsky lupa": dikunci di langkah 6 (data.jalur), sebelum itu dari nasib Tedsky (Quest 9).
create or replace function game.jt_jalur(p_pid uuid) returns text
language plpgsql stable as $$
declare v text;
begin
  select data ->> 'jalur' into v from game.player_quests where player_id = p_pid and quest_id = 'jtq';
  if v in ('ikn', 'dewan') then return v; end if;
  return case when game.dt_data(p_pid) ->> 'fate' = 'ikn' then 'ikn' else 'dewan' end;
exception when others then return 'dewan';
end $$;

-- Status (kunci 'jtq' di api_getGameState). null = belum terbuka. Tidak memuat angka, urutan, atau hadiah.
-- 'pilihan' hanya ada setelah tamat (baris bankir & gosip sesudahnya).
create or replace function game.jt_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare v_step int; v_ch text; r jsonb;
begin
  if p_pid is null or not game.jt_eligible(p_pid) then return null; end if;
  v_step := game.jt_step(p_pid);
  r := jsonb_build_object('step', v_step, 'done', v_step >= game.jt_last(), 'frozen', game.jt_frozen(p_pid),
    'jalur', game.jt_jalur(p_pid), 'saga3', game.jt_saga3(p_pid));
  if v_step >= game.jt_last() then
    select data ->> 'choice' into v_ch from game.player_quests where player_id = p_pid and quest_id = 'jtq';
    r := r || jsonb_build_object('pilihan', case when v_ch = 'tolak' then 'tolak' when v_ch = 'kamp' then 'kamp' else 'setuju' end);
  end if;
  return r;
exception when others then
  raise warning '[jtq] state: %', sqlerrm;
  return null;
end $$;

-- ---------------------------------------------------------------------
-- Pemeriksa Meja Kas (server = penentu). null = benar, atau alasan singkat.
-- ---------------------------------------------------------------------
-- Mode B (Hitung Kas): p_res = [ronde][baki] = {kind: n}. Hanya koin baik (stock) yang boleh dipakai.
create or replace function game.jt_check_kas(p_lv jsonb, p_res jsonb) returns text
language plpgsql immutable as $$
declare
  rd jsonb; tr jsonb; kv record; i int; j int; v_val jsonb := '{}'::jsonb; v_sum bigint; v_n bigint; v_used jsonb; v_coins bigint;
begin
  if p_res is null or jsonb_typeof(p_res) <> 'array' or jsonb_array_length(p_res) <> jsonb_array_length(p_lv -> 'rounds') then
    return 'Bayarannya belum lengkap.'; end if;
  select coalesce(jsonb_object_agg(k ->> 'id', (k ->> 'val')::int), '{}'::jsonb) into v_val from jsonb_array_elements(p_lv -> 'kinds') k;
  for i in 0 .. jsonb_array_length(p_lv -> 'rounds') - 1 loop
    rd := p_lv -> 'rounds' -> i;
    if jsonb_typeof(p_res -> i) <> 'array' or jsonb_array_length(p_res -> i) <> jsonb_array_length(rd -> 'trays') then
      return 'Bakinya belum lengkap.'; end if;
    v_used := '{}'::jsonb; v_coins := 0;
    for j in 0 .. jsonb_array_length(rd -> 'trays') - 1 loop
      tr := p_res -> i -> j;
      if jsonb_typeof(tr) <> 'object' then return 'Bakinya belum lengkap.'; end if;
      v_sum := 0;
      for kv in select key, value from jsonb_each(tr) loop
        if not (v_val ? kv.key) or jsonb_typeof(kv.value) <> 'number' then return 'Ada koin yang tidak dikenal.'; end if;
        v_n := (kv.value #>> '{}')::numeric;
        if v_n < 0 or v_n <> trunc(v_n) then return 'Ada koin yang tidak dikenal.'; end if;
        v_sum := v_sum + v_n * (v_val ->> kv.key)::int;
        v_coins := v_coins + v_n;
        v_used := v_used || jsonb_build_object(kv.key, coalesce((v_used ->> kv.key)::bigint, 0) + v_n);
      end loop;
      if v_sum <> (rd -> 'trays' ->> j)::bigint then return 'Jumlahnya belum pas.'; end if;
    end loop;
    for kv in select key, value from jsonb_each(v_used) loop
      if (kv.value #>> '{}')::bigint > coalesce((rd -> 'stock' ->> kv.key)::bigint, 0) then return 'Koin di laci tidak sebanyak itu.'; end if;
    end loop;
    if rd ->> 'min' is not null and v_coins > (rd ->> 'min')::bigint then return 'Bisa dengan koin lebih sedikit.'; end if;
  end loop;
  return null;
exception when others then return 'Bayarannya tidak terbaca.';
end $$;

-- Mode A (Timbang Koin): p_res = {w:[{l:[id],r:[id]}], pick:[id]}. Benar bila: timbangan sah (piring sama banyak,
-- tidak bertumpang), tidak melebihi batas, tunjukan = koin berat, dan hasil timbangan HANYA cocok dengan tunjukan itu
-- (bukan tebakan beruntung).
create or replace function game.jt_check_timbang(p_lv jsonb, p_res jsonb) returns text
language plpgsql immutable as $$
declare
  n int := (p_lv ->> 'n')::int; k int := jsonb_array_length(p_lv -> 'odd'); mx int := (p_lv ->> 'max')::int;
  w jsonb; L int[]; R int[]; truth int[]; pick int[]; hyp int[]; outs int[] := '{}'; o int; a int; b int;
  i int; j int; nw int; v_ok int := 0; good boolean;
begin
  if p_res is null or jsonb_typeof(p_res) <> 'object' or jsonb_typeof(p_res -> 'w') <> 'array' or jsonb_typeof(p_res -> 'pick') <> 'array' then
    return 'Timbangannya tidak terbaca.'; end if;
  nw := jsonb_array_length(p_res -> 'w');
  if nw > mx then return 'Lilinnya sudah habis.'; end if;
  select coalesce(array_agg(substr(x, 2)::int order by substr(x, 2)::int), '{}') into truth from jsonb_array_elements_text(p_lv -> 'odd') x;
  select coalesce(array_agg(distinct substr(x, 2)::int order by substr(x, 2)::int), '{}') into pick from jsonb_array_elements_text(p_res -> 'pick') x where x ~ '^c[0-9]+$';
  if jsonb_array_length(p_res -> 'pick') <> k or pick is distinct from truth then return 'Bukan koin itu.'; end if;
  -- hasil sebenarnya tiap timbangan
  for i in 0 .. nw - 1 loop
    w := p_res -> 'w' -> i;
    select coalesce(array_agg(substr(x, 2)::int), '{}') into L from jsonb_array_elements_text(w -> 'l') x where x ~ '^c[0-9]+$';
    select coalesce(array_agg(substr(x, 2)::int), '{}') into R from jsonb_array_elements_text(w -> 'r') x where x ~ '^c[0-9]+$';
    if cardinality(L) = 0 or cardinality(L) <> cardinality(R) or cardinality(L) <> jsonb_array_length(w -> 'l') or cardinality(R) <> jsonb_array_length(w -> 'r') then
      return 'Piringnya harus sama banyak.'; end if;
    if L && R or (select count(distinct x) from unnest(L) x) <> cardinality(L) or (select count(distinct x) from unnest(R) x) <> cardinality(R) then
      return 'Satu koin hanya bisa di satu piring.'; end if;
    if exists (select 1 from unnest(L || R) x where x < 1 or x > n) then return 'Ada koin yang tidak dikenal.'; end if;
    a := (select count(*) from unnest(truth) x where x = any(L)); b := (select count(*) from unnest(truth) x where x = any(R));
    outs := outs || sign(a - b)::int;
  end loop;
  -- berapa kemungkinan yang masih cocok dengan semua hasil timbangan?
  for hyp in
    select array[x] from generate_series(1, n) x where k = 1
    union all
    select array[x, y] from generate_series(1, n) x, generate_series(1, n) y where k = 2 and x < y
  loop
    good := true;
    for i in 0 .. nw - 1 loop
      w := p_res -> 'w' -> i;
      select coalesce(array_agg(substr(x, 2)::int), '{}') into L from jsonb_array_elements_text(w -> 'l') x;
      select coalesce(array_agg(substr(x, 2)::int), '{}') into R from jsonb_array_elements_text(w -> 'r') x;
      a := (select count(*) from unnest(hyp) x where x = any(L)); b := (select count(*) from unnest(hyp) x where x = any(R));
      if sign(a - b)::int <> outs[i + 1] then good := false; exit; end if;
    end loop;
    if good then v_ok := v_ok + 1; end if;
    if v_ok > 1 then return 'Tebakan beruntung. Bankir tidak menebak.'; end if;
  end loop;
  return null;
exception when others then return 'Timbangannya tidak terbaca.';
end $$;

-- ---------------------------------------------------------------------
-- Aksi
-- ---------------------------------------------------------------------
create or replace function public.api_jtq(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status');
  v_want int := game.arg_int(a, 1);
  v_res jsonb := case when jsonb_typeof(a) = 'array' then a -> 2 end;
  v_step int; d jsonb; v_err text; v_choice text; v_amount bigint := 0; v_gold bigint := 0; v_extra jsonb := '{}'::jsonb;
  v_rank int; v_tiers bigint[]; g game.gr_projects; v_name text; dn game.gr_donations; v_uji boolean := false;
begin
  if v_act = 'status' then return jsonb_build_object('jtq', game.jt_state(v_pid)); end if;
  if v_act not in ('level', 'maju', 'pilih') then raise exception 'Aksi tidak dikenal.'; end if;
  if not game.jt_eligible(v_pid) or game.jt_frozen(v_pid) then raise exception 'Loket sedang sibuk, Kapten.'; end if;

  if v_act = 'level' then
    v_step := game.jt_step(v_pid);
    if v_want is distinct from v_step or v_step >= game.jt_last() then raise exception 'Loket sedang sibuk, Kapten.'; end if;
    d := game.jt_steps() -> v_step;
    if not (d ? 'lv') then raise exception 'Loket sedang sibuk, Kapten.'; end if;
    return jsonb_build_object('level', game.jt_levels() -> (d ->> 'lv'));
  end if;

  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;
  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'jtq', 0, '{}'::jsonb)
  on conflict (player_id, quest_id) do nothing;
  select step into v_step from game.player_quests where player_id = v_pid and quest_id = 'jtq' for update;
  if v_step >= game.jt_last() then raise exception 'Loket sedang sibuk, Kapten.'; end if;
  if v_want is null or v_want <> v_step then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;

  d := game.jt_steps() -> v_step;
  if game.current_city(v_pid) is distinct from (d ->> 'c') then raise exception 'Loket sedang sibuk, Kapten.'; end if;
  if d ->> 't' = 'malam' and not game.fish_is_night() then raise exception 'Datanglah lagi saat lampu-lampu dinyalakan, Kapten.'; end if;

  if v_act = 'maju' then
    if coalesce((d ->> 'pilih')::boolean, false) then raise exception 'Kartu itu menunggu keputusanmu, Kapten.'; end if;
    if d ->> 'g' = 'kas' then
      v_err := game.jt_check_kas(game.jt_levels() -> (d ->> 'lv'), v_res);
      if v_err is not null then raise exception 'Belum pas, Kapten. %', v_err; end if;
    elsif d ->> 'g' = 'timbang' then
      v_err := game.jt_check_timbang(game.jt_levels() -> (d ->> 'lv'), v_res);
      if v_err is not null then raise exception 'Belum pasti, Kapten. %', v_err; end if;
    elsif d ->> 'g' = 'manifest' then
      v_err := game.dn_check_manifest(game.jt_levels() -> (d ->> 'lv'), v_res);
      if v_err is not null then raise exception 'Belum cocok, Kapten. Masih ada slip yang belum cocok dengan buku besar.'; end if;
    elsif d ? 'g' and coalesce(v_res #>> '{}', '') <> 'ok' then
      raise exception 'Belum berhasil, Kapten. Coba lagi.';
    end if;
    -- langkah 6: kunci jalur pembawa kabar "Tedsky lupa" (tidak berubah lagi di tengah quest)
    if d ->> 'p' = 'kongsi' then v_extra := jsonb_build_object('jalur', game.jt_jalur(v_pid), 'lupa', true); end if;
    if d ->> 'c' = 'ikn' and d ->> 'g' = 'jejak' and game.jt_jalur(v_pid) = 'ikn' then v_extra := jsonb_build_object('lupa', true); end if;
    update game.player_quests set step = v_step + 1, updated_at = now(),
      data = data || v_extra || jsonb_build_object('s' || v_step, game.now_ms())
     where player_id = v_pid and quest_id = 'jtq';
    return jsonb_build_object('jtq', game.jt_state(v_pid));
  end if;

  -- ------------------------------------------------------------- pilih (langkah terakhir, satu transaksi)
  if not coalesce((d ->> 'pilih')::boolean, false) then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;
  v_choice := lower(btrim(coalesce(v_res #>> '{}', '')));
  if v_choice not in ('setuju', 'tolak') then raise exception 'Kartu itu menunggu keputusanmu, Kapten.'; end if;
  -- kunci kolam dulu: urutan penyumbang harus unik walau dua kapten memilih bersamaan
  select * into g from game.gr_projects where id = 'ikn' for update;
  v_name := coalesce(nullif(v_me.character_name, ''), 'Seorang kapten');

  if v_choice = 'tolak' then
    v_gold := greatest(0, game.cfg_num('JtqUpah', 250000))::bigint;
    update game.players set gold = gold + v_gold where player_id = v_pid;
  elsif g.done_at is not null or not found then
    v_choice := 'kamp';
  elsif game.is_gm(v_pid) then
    -- GM: uji tanpa memakai urutan dan tanpa menyentuh kolam
    v_uji := true;
    v_tiers := string_to_array(replace(coalesce(game.cfg('JtqTiers'), '500000'), ' ', ''), ',')::bigint[];
    v_rank := coalesce((select max(rank) from game.jtq_rank), 0) + 1;
    v_amount := v_tiers[least(v_rank, array_length(v_tiers, 1))];
  else
    v_tiers := string_to_array(replace(coalesce(game.cfg('JtqTiers'), '500000'), ' ', ''), ',')::bigint[];
    v_rank := coalesce((select max(rank) from game.jtq_rank), 0) + 1;
    v_amount := greatest(0, coalesce(v_tiers[least(v_rank, array_length(v_tiers, 1))], 0));
    insert into game.gr_donations as x (project_id, player_id, jtq, total, n, last_at)
    values ('ikn', v_pid, v_amount, v_amount, 0, now())
    on conflict (project_id, player_id) do update set jtq = x.jtq + excluded.jtq, total = x.total + excluded.total, last_at = now()
    returning * into dn;
    perform game.gr_grant_kategori(v_pid, dn.total);
    perform game.gr_pool_add(v_amount, 'Kapten ' || v_name, v_pid);
  end if;

  if not v_uji then
    insert into game.jtq_rank(player_id, rank, choice, amount)
    values (v_pid, case when v_choice = 'setuju' then v_rank end, v_choice, case when v_choice = 'tolak' then v_gold else v_amount end)
    on conflict (player_id) do nothing;
  end if;

  update game.player_quests set step = game.jt_last(), updated_at = now(), done_at = now(),
    data = data || jsonb_build_object('s' || v_step, game.now_ms(), 'choice', v_choice)
   where player_id = v_pid and quest_id = 'jtq';

  return jsonb_build_object('jtq', game.jt_state(v_pid), 'choice', v_choice, 'amount', v_amount, 'gold', v_gold, 'uji', v_uji,
    'newGold', (select gold from game.players where player_id = v_pid), 'gotong', game.gotong_state(v_pid));
end $$;
select game.expose('api_jtq');

-- ---------------------------------------------------------------------
-- Alat uji GM (SQL Editor): select game.admin_jtq('abuy', 8);
-- Menyetel langkah (0..10). Tidak menyentuh urutan penyumbang atau kolam.
-- ---------------------------------------------------------------------
create or replace function game.admin_jtq(p_username text, p_step int) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid; s int;
begin
  select player_id into v_pid from game.players where lower(username) = lower(p_username);
  if v_pid is null then raise exception 'Pemain % tidak ditemukan.', p_username; end if;
  s := greatest(0, least(game.jt_last(), coalesce(p_step, 0)));
  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'jtq', s, '{}'::jsonb)
  on conflict (player_id, quest_id) do update set step = s, updated_at = now(),
    done_at = case when s >= game.jt_last() then now() else null end,
    data = case when s >= game.jt_last() then game.player_quests.data
                when s <= 6 then game.player_quests.data - 'choice' - 'jalur' - 'lupa'
                else game.player_quests.data - 'choice' end;
  return game.jt_state(v_pid);
end $$;
revoke all on function game.admin_jtq(text, int) from public;

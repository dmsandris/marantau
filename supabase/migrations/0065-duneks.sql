-- =====================================================================
-- Marantau (Supabase) - 0065 QUEST RAHASIA "KNOCK-KNOCK GUDANG DOOR" (TheDuneks)
-- ---------------------------------------------------------------------
-- Konsep: claude/KONSEP-Quest-TheDuneks.md (v3).
-- Side quest di luar Saga 3. Terbuka setelah Saga 2 selesai (duatangan step >= 5), saat panel Gudang
-- Sunda Empire dibuka, dan HANYA bila tidak ada side quest lain yang sedang berjalan (game.side_quest_active, 0064).
-- Rahasia sepenuhnya: tanpa Tanda Jasa khusus, jurnal, log pemain, chat dunia khusus quest, atau Realtime.
-- Dibekukan selama Saga 3 aktif untuk pemain itu.
--
-- Langkah (game.player_quests, quest_id = 'duneks'); step = langkah BERIKUTNYA yang dijalankan.
--   0 Sunda Empire  : Tata Gudang (susun)            4 Skitraw       : Tata Gudang (manifest)
--   1 Joungjava     : Syahbandar                      5 Gading Island : Tata Gudang (susun)
--   2 Bjorneo       : Tata Gudang (susun)             6 IKN (malam)   : Tata Gudang (manifest, final)
--   3 TooGood (malam): Mata Pesta (Pasar Gelap)       7 IKN           : pilihan -> 8 selesai (satu transaksi)
-- Aksi:
--   api_duneks(['status'])
--   api_duneks(['level', step])                 definisi level Tata Gudang langkah itu
--   api_duneks(['maju', step, hasil])           hasil: susunan {id:{x,y,r}} / daftar id peti / 'ok' (mini game lama)
--   api_duneks(['pilih', 7, 'setuju'|'tolak'])
-- Jalur setuju: sumbangan BERTINGKAT (config DuneksTiers) ke Kolam Restorasi IKN, masuk total pribadi.
--   Urutan hanya dihitung dari pemain biasa yang memilih setuju (GM tidak ikut). Tanpa chat "menyumbang N gold";
--   pengumuman tahap kolam & Penjaga Garuda tetap seperti biasa (game.gr_pool_add / gr_grant_kategori, 0032).
--   Kolam sudah penuh -> jalur Kamp Pemulung (cerita saja, tanpa urutan).
-- Jalur tolak: DuneksUpah gold.
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('DuneksTiers', '10000000,8000000,6000000,4000000,3000000,2000000'),
  ('DuneksUpah', '25000')
on conflict (key) do nothing;
-- daftar side quest (aturan satu per satu, 0064)
insert into game.config(key, value) values ('SideQuestIds', 'peregrin,duneks')
on conflict (key) do update set value = case
  when string_to_array(replace(game.config.value, ' ', ''), ',') @> array['duneks'] then game.config.value
  else nullif(btrim(game.config.value, ', '), '') || ',duneks' end;
update game.config set value = 'peregrin,duneks' where key = 'SideQuestIds' and coalesce(value, '') = '';

-- jejak audit GM: porsi sumbangan dari quest ini (ikut kolom total)
alter table game.gr_donations add column if not exists duneks bigint not null default 0;

-- urutan penyumbang (hanya pemain biasa). rank null = tolak / Kamp Pemulung.
create table if not exists game.dn_rank (
  player_id uuid primary key references game.players(player_id) on update cascade on delete cascade,
  rank      int unique,
  choice    text not null,
  amount    bigint not null default 0,
  at        timestamptz not null default now()
);
alter table game.dn_rank enable row level security;

-- ---------------------------------------------------------------------
-- Data langkah & level
-- ---------------------------------------------------------------------
create or replace function game.dn_steps() returns jsonb
language sql immutable as $$
  select '[
    {"c":"sunda_empire","g":"susun","lv":"sunda"},
    {"c":"joungjava","g":"syahbandar"},
    {"c":"bjorneo","g":"susun","lv":"bjorneo"},
    {"c":"toogood","t":"malam","g":"pesta"},
    {"c":"skitraw","g":"manifest","lv":"skitraw"},
    {"c":"gading_island","g":"susun","lv":"gading"},
    {"c":"ikn","t":"malam","g":"manifest","lv":"ikn"},
    {"c":"ikn","pilih":true}
  ]'::jsonb
$$;
create or replace function game.dn_last() returns int language sql immutable as $$ select 8 $$;

-- Level Tata Gudang. susun: y = 0 baris bawah, x = w-1 kolom dekat pintu. manifest: peti cocok bila qty/cap/berat sama dengan barisnya.
-- Semua level susun dijamin bisa diselesaikan (solver di test/0065-duneks.test.js).
create or replace function game.dn_levels() returns jsonb
language sql immutable as $LV$ select '{"sunda":{"w":6,"h":3,"rules":["berat","basah"],"items":[{"id":"s1","k":"perkakas","shape":[[0,0],[1,0]],"tags":["berat"]},{"id":"s2","k":"perkakas","shape":[[0,0],[1,0]],"tags":["berat"]},{"id":"s3","k":"garam","shape":[[0,0]],"tags":["berat"]},{"id":"s4","k":"garam","shape":[[0,0]],"tags":["berat"]},{"id":"s5","k":"batik","shape":[[0,0],[1,0]],"tags":["kain"]},{"id":"s6","k":"batik","shape":[[0,0],[1,0]],"tags":["kain"]},{"id":"s7","k":"tuak","shape":[[0,0]],"tags":["basah"]},{"id":"s8","k":"tuak","shape":[[0,0]],"tags":["basah"]},{"id":"s9","k":"ikanasin","shape":[[0,0],[0,1]],"tags":["basah"]},{"id":"s10","k":"jt","shape":[[0,0],[1,0],[0,1],[1,1]],"tags":[]}],"mode":"susun","par":12,"theme":"sunda"},"bjorneo":{"w":6,"h":4,"rules":["berat","basah","rapuh"],"items":[{"id":"b1","k":"ulin","shape":[[0,0],[1,0],[2,0]],"tags":["berat"]},{"id":"b2","k":"ulin","shape":[[0,0],[1,0],[2,0]],"tags":["berat"]},{"id":"b3","k":"lada","shape":[[0,0]],"tags":[]},{"id":"b4","k":"rotan","shape":[[0,0],[0,1]],"tags":[]},{"id":"b5","k":"walet","shape":[[0,0]],"tags":["rapuh"]},{"id":"b6","k":"walet","shape":[[0,0]],"tags":["rapuh"]},{"id":"b7","k":"walet","shape":[[0,0]],"tags":["rapuh"]},{"id":"b8","k":"tuak","shape":[[0,0]],"tags":["basah"]},{"id":"b9","k":"tuak","shape":[[0,0]],"tags":["basah"]},{"id":"b10","k":"tuak","shape":[[0,0]],"tags":["basah"]},{"id":"b11","k":"tikar","shape":[[0,0],[1,0]],"tags":["kain"]},{"id":"b12","k":"tikar","shape":[[0,0],[1,0]],"tags":["kain"]},{"id":"b13","k":"jt","shape":[[0,0],[1,0],[0,1],[1,1]],"tags":[]}],"mode":"susun","par":15,"theme":"bjorneo"},"gading":{"w":6,"h":4,"rules":["berat","basah","rapuh","besok"],"items":[{"id":"g1","k":"tehbesar","shape":[[0,0],[1,0]],"tags":["berat"]},{"id":"g2","k":"tehbesar","shape":[[0,0],[1,0]],"tags":["berat"]},{"id":"g3","k":"gucibesar","shape":[[0,0]],"tags":["berat"]},{"id":"g4","k":"sutra","shape":[[0,0],[1,0]],"tags":["kain"]},{"id":"g5","k":"sutra","shape":[[0,0],[1,0]],"tags":["kain"]},{"id":"g6","k":"kecap","shape":[[0,0]],"tags":["basah"]},{"id":"g7","k":"kecap","shape":[[0,0]],"tags":["basah"]},{"id":"g8","k":"porselen","shape":[[0,0]],"tags":["rapuh"]},{"id":"g9","k":"porselen","shape":[[0,0]],"tags":["rapuh"]},{"id":"g10","k":"lampion","shape":[[0,0]],"tags":["rapuh","besok"]},{"id":"g11","k":"pesanan","shape":[[0,0],[1,0],[1,1]],"tags":["besok"]},{"id":"g12","k":"keranjang","shape":[[0,0],[0,1]],"tags":["besok"]},{"id":"g13","k":"jt","shape":[[0,0],[1,0],[0,1],[1,1]],"tags":[]}],"mode":"susun","par":16,"theme":"gading"},"skitraw":{"mode":"manifest","theme":"skitraw","rows":[{"id":"r1","label":"Kain songket","qty":7,"cap":"syahbandar","berat":"2 pikul"},{"id":"r2","label":"Rendang kering","qty":5,"cap":"syahbandar","berat":"1 pikul"},{"id":"r3","label":"Kayu manis","qty":9,"cap":"balai","berat":"3 pikul"},{"id":"r4","label":"Ikan asin","qty":6,"cap":"syahbandar","berat":"2 pikul"},{"id":"r5","label":"Lampu minyak","qty":4,"cap":"balai","berat":"1 pikul"},{"id":"r6","label":"Arak","qty":8,"cap":"syahbandar","berat":"3 pikul"},{"id":"r7","label":"Garam","qty":10,"cap":"balai","berat":"4 pikul"},{"id":"r8","label":"Gendang","qty":3,"cap":"balai","berat":"1 pikul"},{"id":"r9","label":"Kertas minyak","qty":6,"cap":"syahbandar","berat":"1 pikul"},{"id":"r10","label":"Bendera festival","qty":12,"cap":"balai","berat":"1 pikul"},{"id":"r11","label":"Restorasi IKN: paku","qty":8,"cap":"restorasi","berat":"2 pikul"},{"id":"r12","label":"Restorasi IKN: tali","qty":5,"cap":"restorasi","berat":"1 pikul"}],"crates":[{"id":"sc5","row":"r5","label":"Lampu minyak","qty":4,"cap":"balai","berat":"1 pikul"},{"id":"sc12","row":"r12","label":"Restorasi IKN: tali","qty":5,"cap":"restorasi","berat":"1 pikul"},{"id":"sc3","row":"r3","label":"Kayu manis","qty":9,"cap":"balai","berat":"3 pikul"},{"id":"sc1","row":"r1","label":"Kain songket","qty":7,"cap":"syahbandar","berat":"2 pikul"},{"id":"sc10","row":"r10","label":"Bendera festival","qty":12,"cap":"balai","berat":"1 pikul"},{"id":"sc6","row":"r6","label":"Arak","qty":8,"cap":"syahbandar","berat":"3 pikul"},{"id":"sc11","row":"r11","label":"Restorasi IKN: paku","qty":8,"cap":"jt","berat":"2 pikul","jt":true},{"id":"sc7","row":"r7","label":"Garam","qty":10,"cap":"balai","berat":"6 pikul","jt":true},{"id":"sc4","row":"r4","label":"Ikan asin","qty":9,"cap":"syahbandar","berat":"2 pikul","jt":true},{"id":"sc9","row":"r9","label":"Kertas minyak","qty":6,"cap":"syahbandar","berat":"1 pikul"},{"id":"sc8","row":"r8","label":"Gendang","qty":3,"cap":"balai","berat":"1 pikul"},{"id":"sc2","row":"r2","label":"Rendang kering","qty":5,"cap":"syahbandar","berat":"1 pikul"}]},"ikn":{"mode":"manifest","theme":"ikn","rows":[{"id":"r1","label":"Restorasi IKN: semen","qty":14,"cap":"restorasi","berat":"6 pikul"},{"id":"r2","label":"Restorasi IKN: besi","qty":11,"cap":"restorasi","berat":"8 pikul"},{"id":"r3","label":"Restorasi IKN: kayu ulin","qty":9,"cap":"restorasi","berat":"7 pikul"},{"id":"r4","label":"Restorasi IKN: kaca","qty":6,"cap":"restorasi","berat":"2 pikul"},{"id":"r5","label":"Restorasi IKN: cat perunggu","qty":8,"cap":"restorasi","berat":"2 pikul"},{"id":"r6","label":"Restorasi IKN: paku","qty":13,"cap":"restorasi","berat":"3 pikul"},{"id":"r7","label":"Restorasi IKN: tali","qty":7,"cap":"restorasi","berat":"1 pikul"},{"id":"r8","label":"Restorasi IKN: lampu jalan","qty":12,"cap":"restorasi","berat":"4 pikul"},{"id":"r9","label":"Restorasi IKN: papan nama","qty":4,"cap":"restorasi","berat":"2 pikul"},{"id":"r10","label":"Beras","qty":15,"cap":"syahbandar","berat":"5 pikul"},{"id":"r11","label":"Garam","qty":10,"cap":"syahbandar","berat":"4 pikul"},{"id":"r12","label":"Besi tua","qty":9,"cap":"syahbandar","berat":"6 pikul"},{"id":"r13","label":"Obat-obatan","qty":5,"cap":"syahbandar","berat":"1 pikul"},{"id":"r14","label":"Selimut","qty":8,"cap":"syahbandar","berat":"2 pikul"},{"id":"r15","label":"Restorasi IKN: genteng","qty":11,"cap":"restorasi","berat":"5 pikul"},{"id":"r16","label":"Restorasi IKN: batu bata","qty":16,"cap":"restorasi","berat":"9 pikul"}],"crates":[{"id":"ic15","row":"r15","label":"Restorasi IKN: genteng","qty":11,"cap":"restorasi","berat":"5 pikul"},{"id":"ic4","row":"r4","label":"Restorasi IKN: kaca","qty":6,"cap":"restorasi","berat":"2 pikul"},{"id":"ic5","row":"r5","label":"Restorasi IKN: cat perunggu","qty":8,"cap":"jt","berat":"2 pikul","jt":true},{"id":"ic12","row":"r12","label":"Besi tua","qty":9,"cap":"syahbandar","berat":"6 pikul"},{"id":"ic16","row":"r16","label":"Restorasi IKN: batu bata","qty":16,"cap":"restorasi","berat":"5 pikul","jt":true},{"id":"ic14","row":"r14","label":"Selimut","qty":8,"cap":"syahbandar","berat":"2 pikul"},{"id":"ic9","row":"r9","label":"Restorasi IKN: papan nama","qty":4,"cap":"restorasi","berat":"2 pikul"},{"id":"ic13","row":"r13","label":"Obat-obatan","qty":5,"cap":"syahbandar","berat":"1 pikul"},{"id":"ic8","row":"r8","label":"Restorasi IKN: lampu jalan","qty":12,"cap":"restorasi","berat":"4 pikul"},{"id":"ic7","row":"r7","label":"Restorasi IKN: tali","qty":7,"cap":"restorasi","berat":"1 pikul"},{"id":"ic11","row":"r11","label":"Garam","qty":10,"cap":"syahbandar","berat":"4 pikul"},{"id":"ic1","row":"r1","label":"Restorasi IKN: semen","qty":11,"cap":"restorasi","berat":"6 pikul","jt":true},{"id":"ic2","row":"r2","label":"Restorasi IKN: besi","qty":11,"cap":"restorasi","berat":"8 pikul"},{"id":"ic3","row":"r3","label":"Restorasi IKN: kayu ulin","qty":9,"cap":"restorasi","berat":"7 pikul"},{"id":"ic10","row":"r10","label":"Beras","qty":15,"cap":"syahbandar","berat":"5 pikul"},{"id":"ic6","row":"r6","label":"Restorasi IKN: paku","qty":13,"cap":"restorasi","berat":"3 pikul"}]}}'::jsonb $LV$;

create or replace function game.dn_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'duneks'), 0) $$;

-- Saga 2 selesai, dan (sudah pernah dimulai, atau tidak ada side quest lain yang sedang berjalan)
create or replace function game.dn_eligible(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  if p_pid is null or game.dt_step(p_pid) < 5 then return false; end if;
  if exists (select 1 from game.player_quests where player_id = p_pid and quest_id = 'duneks') then return true; end if;
  return game.side_quest_active(p_pid, 'duneks') is null;
exception when others then return false;
end $$;

-- Dibekukan selama Saga 3 aktif (sama dengan aturan Mesin yang Hanyut)
create or replace function game.dn_frozen(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  if not game.pasir_aktif(p_pid) then return false; end if;
  if game.ps_step(p_pid, 'ps14') >= 6 then return false; end if;
  if game.is_gm(p_pid) and not exists (select 1 from game.pasir_state where player_id = p_pid) then return false; end if;
  return true;
exception when others then return false;
end $$;

-- Status (kunci 'duneks' di api_getGameState). null = belum terbuka. Tidak memuat teks, petunjuk, angka, atau urutan.
-- 'jalur' hanya ada setelah tamat (untuk baris dialog penjaga gudang sesudahnya).
create or replace function game.dn_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare v_step int; v_ch text;
begin
  if p_pid is null or not game.dn_eligible(p_pid) then return null; end if;
  v_step := game.dn_step(p_pid);
  if v_step >= game.dn_last() then
    select data ->> 'choice' into v_ch from game.player_quests where player_id = p_pid and quest_id = 'duneks';
    return jsonb_build_object('step', v_step, 'done', true, 'frozen', game.dn_frozen(p_pid), 'jalur', case when v_ch = 'tolak' then 'tolak' else 'setuju' end);
  end if;
  return jsonb_build_object('step', v_step, 'done', false, 'frozen', game.dn_frozen(p_pid));
exception when others then
  raise warning '[duneks] state: %', sqlerrm;
  return null;
end $$;

-- ---------------------------------------------------------------------
-- Pemeriksa Tata Gudang (server = penentu). Mengembalikan null bila rapi, atau alasan singkat.
-- ---------------------------------------------------------------------
create or replace function game.dn_check_susun(p_lv jsonb, p_pl jsonb) returns text
language plpgsql immutable as $$
declare
  w int := (p_lv ->> 'w')::int; h int := (p_lv ->> 'h')::int; rules jsonb := p_lv -> 'rules';
  grid text[] := array_fill(null::text, array[w * h]); it jsonb; p jsonb; c jsonb;
  r int; px int; py int; cx int; cy int; mx int; my int; i int; x int; y int;
  id text; below text; above text; tags jsonb := '{}'::jsonb; near boolean;
  xs int[]; ys int[];
begin
  if p_pl is null or jsonb_typeof(p_pl) <> 'object' then return 'Susunan tidak terbaca.'; end if;
  for it in select * from jsonb_array_elements(p_lv -> 'items') loop
    id := it ->> 'id'; tags := tags || jsonb_build_object(id, coalesce(it -> 'tags', '[]'::jsonb));
    p := p_pl -> id;
    if p is null or jsonb_typeof(p) <> 'object' then return 'Masih ada peti di lantai.'; end if;
    r := ((coalesce((p ->> 'r')::int, 0) % 4) + 4) % 4; px := (p ->> 'x')::int; py := (p ->> 'y')::int;
    if px is null or py is null then return 'Susunan tidak terbaca.'; end if;
    xs := '{}'; ys := '{}';
    for c in select * from jsonb_array_elements(it -> 'shape') loop
      cx := (c ->> 0)::int; cy := (c ->> 1)::int;
      -- putar r x 90 derajat: (x,y) -> (y,-x)
      for i in 1 .. r loop x := cy; y := -cx; cx := x; cy := y; end loop;
      xs := xs || cx; ys := ys || cy;
    end loop;
    select min(v) into mx from unnest(xs) v; select min(v) into my from unnest(ys) v;
    near := false;
    for i in 1 .. coalesce(array_length(xs, 1), 0) loop
      x := px + xs[i] - mx; y := py + ys[i] - my;
      if x < 0 or y < 0 or x >= w or y >= h then return 'Ada peti yang keluar dari rak.'; end if;
      if grid[y * w + x + 1] is not null then return 'Ada peti yang bertumpuk di tempat yang sama.'; end if;
      grid[y * w + x + 1] := id;
      if x = w - 1 then near := true; end if;
    end loop;
    if rules ? 'besok' and (it -> 'tags') ? 'besok' and not near then return 'Barang "keluar besok" harus di dekat pintu.'; end if;
  end loop;
  for y in 0 .. h - 1 loop
    for x in 0 .. w - 1 loop
      id := grid[y * w + x + 1];
      continue when id is null;
      below := case when y > 0 then grid[(y - 1) * w + x + 1] end;
      above := case when y < h - 1 then grid[(y + 1) * w + x + 1] end;
      if rules ? 'berat' and (tags -> id) ? 'berat' and y > 0 then return 'Barang berat harus di baris paling bawah.'; end if;
      if y > 0 and below is null then return 'Ada peti yang melayang.'; end if;
      if rules ? 'basah' and (tags -> id) ? 'basah' and below is not null and below <> id and (tags -> below) ? 'kain' then
        return 'Barang basah tidak boleh di atas kain.'; end if;
      if rules ? 'rapuh' and (tags -> id) ? 'rapuh' and above is not null and above <> id then return 'Barang rapuh tidak boleh ditindih.'; end if;
    end loop;
  end loop;
  return null;
exception when others then return 'Susunan tidak terbaca.';
end $$;

create or replace function game.dn_check_manifest(p_lv jsonb, p_pl jsonb) returns text
language plpgsql immutable as $$
declare v_bad text[]; v_pick text[];
begin
  if p_pl is null or jsonb_typeof(p_pl) <> 'array' then return 'Tandai peti yang tidak cocok.'; end if;
  select coalesce(array_agg(c ->> 'id' order by c ->> 'id'), '{}') into v_bad
    from jsonb_array_elements(p_lv -> 'crates') c
    join jsonb_array_elements(p_lv -> 'rows') rw on rw ->> 'id' = c ->> 'row'
   where (c ->> 'qty') is distinct from (rw ->> 'qty') or (c ->> 'cap') is distinct from (rw ->> 'cap')
      or (c ->> 'berat') is distinct from (rw ->> 'berat');
  select coalesce(array_agg(distinct x order by x), '{}') into v_pick from jsonb_array_elements_text(p_pl) x;
  if v_pick is distinct from v_bad then return 'Masih ada peti yang belum cocok dengan buku.'; end if;
  return null;
exception when others then return 'Tandai peti yang tidak cocok.';
end $$;

-- ---------------------------------------------------------------------
-- Aksi
-- ---------------------------------------------------------------------
create or replace function public.api_duneks(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status');
  v_want int := game.arg_int(a, 1);
  v_res jsonb := case when jsonb_typeof(a) = 'array' then a -> 2 end;
  v_step int; d jsonb; lv jsonb; v_err text; v_choice text; v_amount bigint := 0; v_gold bigint := 0;
  v_rank int; v_tiers bigint[]; g game.gr_projects; v_name text; dn game.gr_donations; v_uji boolean := false;
begin
  if v_act = 'status' then return jsonb_build_object('duneks', game.dn_state(v_pid)); end if;
  if v_act not in ('level', 'maju', 'pilih') then raise exception 'Aksi tidak dikenal.'; end if;
  if not game.dn_eligible(v_pid) or game.dn_frozen(v_pid) then raise exception 'Gudang sedang sibuk, Kapten.'; end if;

  if v_act = 'level' then
    v_step := game.dn_step(v_pid);
    if v_want is distinct from v_step or v_step >= game.dn_last() then raise exception 'Gudang sedang sibuk, Kapten.'; end if;
    d := game.dn_steps() -> v_step;
    if not (d ? 'lv') then raise exception 'Gudang sedang sibuk, Kapten.'; end if;
    return jsonb_build_object('level', game.dn_levels() -> (d ->> 'lv'));
  end if;

  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;
  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'duneks', 0, '{}'::jsonb)
  on conflict (player_id, quest_id) do nothing;
  select step into v_step from game.player_quests where player_id = v_pid and quest_id = 'duneks' for update;
  if v_step >= game.dn_last() then raise exception 'Gudang sedang sibuk, Kapten.'; end if;
  if v_want is null or v_want <> v_step then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;

  d := game.dn_steps() -> v_step;
  if game.current_city(v_pid) is distinct from (d ->> 'c') then raise exception 'Gudang sedang sibuk, Kapten.'; end if;
  if d ->> 't' = 'malam' and not game.fish_is_night() then raise exception 'Datanglah lagi saat lampu-lampu dinyalakan, Kapten.'; end if;

  if v_act = 'maju' then
    if coalesce((d ->> 'pilih')::boolean, false) then raise exception 'Bibi menunggu jawabanmu, Kapten.'; end if;
    if d ->> 'g' = 'susun' then
      v_err := game.dn_check_susun(game.dn_levels() -> (d ->> 'lv'), v_res);
      if v_err is not null then raise exception 'Belum rapi, Kapten. %', v_err; end if;
    elsif d ->> 'g' = 'manifest' then
      v_err := game.dn_check_manifest(game.dn_levels() -> (d ->> 'lv'), v_res);
      if v_err is not null then raise exception 'Belum rapi, Kapten. %', v_err; end if;
    elsif d ? 'g' and coalesce(v_res #>> '{}', '') <> 'ok' then
      raise exception 'Belum berhasil, Kapten. Coba lagi.';
    end if;
    update game.player_quests set step = v_step + 1, updated_at = now(),
      data = data || jsonb_build_object('s' || v_step, game.now_ms())
     where player_id = v_pid and quest_id = 'duneks';
    return jsonb_build_object('duneks', game.dn_state(v_pid));
  end if;

  -- ------------------------------------------------------------- pilih (langkah terakhir, satu transaksi)
  if not coalesce((d ->> 'pilih')::boolean, false) then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;
  v_choice := lower(btrim(coalesce(v_res #>> '{}', '')));
  if v_choice not in ('setuju', 'tolak') then raise exception 'Bibi menunggu jawabanmu, Kapten.'; end if;
  -- kunci kolam dulu: urutan penyumbang harus unik walau dua kapten memilih bersamaan
  select * into g from game.gr_projects where id = 'ikn' for update;
  v_name := coalesce(nullif(v_me.character_name, ''), 'Seorang kapten');

  if v_choice = 'tolak' then
    v_gold := greatest(0, game.cfg_num('DuneksUpah', 25000))::bigint;
    update game.players set gold = gold + v_gold where player_id = v_pid;
  elsif g.done_at is not null or not found then
    v_choice := 'kamp';
  elsif game.is_gm(v_pid) then
    -- GM: uji tanpa memakai urutan dan tanpa menyentuh kolam
    v_uji := true;
    v_tiers := string_to_array(replace(coalesce(game.cfg('DuneksTiers'), '2000000'), ' ', ''), ',')::bigint[];
    v_rank := coalesce((select max(rank) from game.dn_rank), 0) + 1;
    v_amount := v_tiers[least(v_rank, array_length(v_tiers, 1))];
  else
    v_tiers := string_to_array(replace(coalesce(game.cfg('DuneksTiers'), '2000000'), ' ', ''), ',')::bigint[];
    v_rank := coalesce((select max(rank) from game.dn_rank), 0) + 1;
    v_amount := greatest(0, coalesce(v_tiers[least(v_rank, array_length(v_tiers, 1))], 0));
    insert into game.gr_donations as x (project_id, player_id, duneks, total, n, last_at)
    values ('ikn', v_pid, v_amount, v_amount, 0, now())
    on conflict (project_id, player_id) do update set duneks = x.duneks + excluded.duneks, total = x.total + excluded.total, last_at = now()
    returning * into dn;
    perform game.gr_grant_kategori(v_pid, dn.total);
    perform game.gr_pool_add(v_amount, 'Kapten ' || v_name, v_pid);
  end if;

  if not v_uji then
    insert into game.dn_rank(player_id, rank, choice, amount)
    values (v_pid, case when v_choice = 'setuju' then v_rank end, v_choice, case when v_choice = 'tolak' then v_gold else v_amount end)
    on conflict (player_id) do nothing;
  end if;

  update game.player_quests set step = game.dn_last(), updated_at = now(), done_at = now(),
    data = data || jsonb_build_object('s' || v_step, game.now_ms(), 'choice', v_choice)
   where player_id = v_pid and quest_id = 'duneks';

  return jsonb_build_object('duneks', game.dn_state(v_pid), 'choice', v_choice, 'amount', v_amount, 'gold', v_gold, 'uji', v_uji,
    'newGold', (select gold from game.players where player_id = v_pid), 'gotong', game.gotong_state(v_pid));
end $$;
select game.expose('api_duneks');

-- ---------------------------------------------------------------------
-- Alat uji GM (SQL Editor): select game.admin_duneks('abuy', 6);
-- Menyetel langkah (0..8). Tidak menyentuh urutan penyumbang atau kolam.
-- ---------------------------------------------------------------------
create or replace function game.admin_duneks(p_username text, p_step int) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid; s int;
begin
  select player_id into v_pid from game.players where lower(username) = lower(p_username);
  if v_pid is null then raise exception 'Pemain % tidak ditemukan.', p_username; end if;
  s := greatest(0, least(game.dn_last(), coalesce(p_step, 0)));
  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'duneks', s, '{}'::jsonb)
  on conflict (player_id, quest_id) do update set step = s, updated_at = now(),
    done_at = case when s >= game.dn_last() then now() else null end,
    data = case when s >= game.dn_last() then game.player_quests.data else game.player_quests.data - 'choice' end;
  return game.dn_state(v_pid);
end $$;
revoke all on function game.admin_duneks(text, int) from public;

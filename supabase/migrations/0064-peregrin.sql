-- =====================================================================
-- Marantau (Supabase) - 0064 QUEST RAHASIA "MESIN YANG HANYUT" (Lorang Peregrin)
-- ---------------------------------------------------------------------
-- Konsep: claude/KONSEP-Quest-Mesin-Sangrai-felyx.md (final).
-- Di luar Saga 3. Terbuka setelah Saga 2 selesai (Quest 9 'duatangan' step >= 5),
-- dimulai di Kedai Stumpy (Gading Island). Rahasia sepenuhnya:
--   * tanpa Tanda Jasa, tanpa jurnal, tanpa log pemain, tanpa chat dunia / Realtime.
--   * satu-satunya jejak: dialog penjaga lapau (klien: web/src/Peregrin.html).
-- Dibekukan selama Saga 3 aktif untuk pemain itu (pencurian harta Saga 3 mengosongkan palka;
-- bagian mesin kembali bersama potret harta, lalu quest lanjut).
--
-- Langkah (game.player_quests, quest_id = 'peregrin'); step = langkah BERIKUTNYA yang dijalankan.
-- Semua aksi: api_peregrin(['maju', <step yang diharapkan>, <hasil mini game 'ok'>]).
--   0 Stumpy (gading_island)          15 Bjorneo: 3 Tuak -> burner
--   1 Marie Regal                     16 Skitraw: pantun -> nampan pendingin
--   2 FreeYork                        17 IKN
--   3 Karang Garam                    18 IKN: 3 Besi -> rangka
--   4 Karang Garam: selam -> hopper   19 Paradiso
--   5 FreeYork: tempa (pengait)       20 Joungjava
--   6 FreeYork: selam -> drum         21 Joungjava -> buku manual
--   7 Sowtour                         22 Sunda Empire
--   8 em pe'er de pe'er               23 Marie Regal (butuh manual)
--   9 em pe'er de pe'er (malam)       24 FreeYork (butuh 7 bagian)
--  10 Otoland                         25 Sowtour: mercusuar -> kaca intip
--  11 Otoland: gasing -> panel        26 FreeYork: rakit -> mesin utuh (7 bagian + kaca diambil)
--  12 TooGood                         27 Gading (Rumah Mahjong)
--  13 TooGood (malam): jejak -> cerobong  28 Gading (fajar, butuh mesin)
--  14 Bjorneo                         29 Gading Stumpy: mesin & manual diambil, +25.000 gold -> 30 selesai
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values ('PeregrinReward', '25000') on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Item quest (type 'quest': tidak bisa dijual, dibuang, dititip, atau dirampas).
-- Nama & deskripsi sengaja netral: tidak menunjuk ke mana pun.
-- ---------------------------------------------------------------------
insert into game.item_catalog(item_id, name, type, effects, value, price, source, sort) values
  ('qi_pg_hopper',   'Corong Besi',          'quest', '{"cargoSize": 2, "desc": "Corong besi berukir aksara asing. Bersih setelah dicuci air laut."}', 0, null, 'quest', 140),
  ('qi_pg_drum',     'Drum Besi Berukir',    'quest', '{"cargoSize": 8, "desc": "Tabung besi besar yang bisa berputar. Teritipnya sudah dikerok."}', 0, null, 'quest', 141),
  ('qi_pg_panel',    'Kotak Bertombol',      'quest', '{"cargoSize": 1, "desc": "Kotak kecil dengan tombol-tombol kuningan dan kaca bundar."}', 0, null, 'quest', 142),
  ('qi_pg_cerobong', 'Cerobong Logam',       'quest', '{"cargoSize": 2, "desc": "Cerobong pendek berlapis jelaga dan sedikit cat."}', 0, null, 'quest', 143),
  ('qi_pg_burner',   'Tungku Api Biru',      'quest', '{"cargoSize": 1, "desc": "Tungku kecil. Masih hangat, baunya seperti tuak."}', 0, null, 'quest', 144),
  ('qi_pg_nampan',   'Nampan Berputar',      'quest', '{"cargoSize": 2, "desc": "Nampan bundar berlubang-lubang dengan lengan pengaduk. Wangi rendang."}', 0, null, 'quest', 145),
  ('qi_pg_rangka',   'Rangka Besi',          'quest', '{"cargoSize": 6, "desc": "Rangka besi berkaki empat. Ada bekas roda gerobak di kakinya."}', 0, null, 'quest', 146),
  ('qi_pg_manual',   'Buku Manual Bersampul Kaca', 'quest', '{"cargoSize": 0, "desc": "Ditulis dalam aksara Moramora. Di sampulnya: Lorang Peregrin."}', 0, null, 'quest', 147),
  ('qi_pg_kaca',     'Kaca Intip Bundar',    'quest', '{"cargoSize": 0, "desc": "Kaca bening tebal dari Gudang Cermin, dipotong bundar."}', 0, null, 'quest', 148),
  ('qi_pg_mesin',    'Lorang Peregrin',      'quest', '{"cargoSize": 15, "desc": "Mesin sangrai kopi, tujuh puluh kilogram biji sekali putar. Utuh kembali."}', 0, null, 'quest', 149)
on conflict (item_id) do update set name = excluded.name, type = excluded.type, effects = excluded.effects,
  value = excluded.value, price = excluded.price, source = excluded.source, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Aturan langkah (data, bukan kode): kota, syarat waktu, mini game, barter, item diberi/diambil.
-- ---------------------------------------------------------------------
create or replace function game.pg_steps() returns jsonb
language sql immutable as $$
  select '[
    {"c":"gading_island"},
    {"c":"marie_regal"},
    {"c":"freeyork"},
    {"c":"karang_garam"},
    {"c":"karang_garam","g":"selam","give":"qi_pg_hopper"},
    {"c":"freeyork","g":"tempa"},
    {"c":"freeyork","g":"selam","give":"qi_pg_drum"},
    {"c":"sowtour"},
    {"c":"empeer_depeer"},
    {"c":"empeer_depeer","t":"malam"},
    {"c":"otoland"},
    {"c":"otoland","g":"gasing","give":"qi_pg_panel"},
    {"c":"toogood"},
    {"c":"toogood","t":"malam","g":"jejak","give":"qi_pg_cerobong"},
    {"c":"bjorneo"},
    {"c":"bjorneo","barter":["tuak",3],"give":"qi_pg_burner"},
    {"c":"skitraw","g":"pantun","give":"qi_pg_nampan"},
    {"c":"ikn"},
    {"c":"ikn","barter":["besi",3],"give":"qi_pg_rangka"},
    {"c":"paradiso"},
    {"c":"joungjava"},
    {"c":"joungjava","give":"qi_pg_manual"},
    {"c":"sunda_empire"},
    {"c":"marie_regal","need":["qi_pg_manual"]},
    {"c":"freeyork","need":["qi_pg_drum","qi_pg_hopper","qi_pg_panel","qi_pg_cerobong","qi_pg_burner","qi_pg_nampan","qi_pg_rangka"]},
    {"c":"sowtour","g":"mercusuar","give":"qi_pg_kaca"},
    {"c":"freeyork","need":["qi_pg_drum","qi_pg_hopper","qi_pg_panel","qi_pg_cerobong","qi_pg_burner","qi_pg_nampan","qi_pg_rangka","qi_pg_kaca"],
     "take":["qi_pg_drum","qi_pg_hopper","qi_pg_panel","qi_pg_cerobong","qi_pg_burner","qi_pg_nampan","qi_pg_rangka","qi_pg_kaca"],"give":"qi_pg_mesin"},
    {"c":"gading_island"},
    {"c":"gading_island","t":"fajar","need":["qi_pg_mesin"]},
    {"c":"gading_island","need":["qi_pg_mesin","qi_pg_manual"],"take":["qi_pg_mesin","qi_pg_manual"],"gold":true}
  ]'::jsonb
$$;

create or replace function game.pg_last() returns int language sql immutable as $$ select 30 $$;

create or replace function game.pg_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'peregrin'), 0) $$;

-- Saga 2 selesai?
create or replace function game.pg_eligible(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  return game.dt_step(p_pid) >= 5;
exception when others then return false;
end $$;

-- Dibekukan selama Saga 3 aktif (sejak terbuka sampai Quest 14 tamat).
-- GM selalu "aktif" untuk uji Saga 3, jadi GM hanya dibekukan bila benar-benar sedang memainkannya.
create or replace function game.pg_frozen(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  if not game.pasir_aktif(p_pid) then return false; end if;
  if game.ps_step(p_pid, 'ps14') >= 6 then return false; end if;
  if game.is_gm(p_pid) and not exists (select 1 from game.pasir_state where player_id = p_pid) then return false; end if;
  return true;
exception when others then return false;
end $$;

-- ---------------------------------------------------------------------
-- Status (kunci 'peregrin' di api_getGameState). null = belum terbuka untuk pemain ini.
-- Tidak memuat apa pun selain langkah: tidak ada teks, petunjuk, atau tujuan.
-- ---------------------------------------------------------------------
create or replace function game.pg_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare v_step int;
begin
  if p_pid is null or not game.pg_eligible(p_pid) then return null; end if;
  v_step := game.pg_step(p_pid);
  return jsonb_build_object('step', v_step, 'done', v_step >= game.pg_last(), 'frozen', game.pg_frozen(p_pid));
exception when others then
  raise warning '[peregrin] state: %', sqlerrm;
  return null;
end $$;

-- ---------------------------------------------------------------------
-- Aksi
--   status
--   maju <step> [ok]   jalankan langkah <step> (harus sama dengan langkah sekarang)
-- ---------------------------------------------------------------------
create or replace function public.api_peregrin(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status');
  v_want int := game.arg_int(a, 1);
  v_res text := lower(btrim(coalesce(game.arg(a, 2), '')));
  v_step int; d jsonb; v_city text; it text; v_need numeric := 0; v_free numeric; v_size numeric;
  v_gold bigint := 0; v_comm text; v_qty int;
begin
  if v_act = 'status' then return jsonb_build_object('peregrin', game.pg_state(v_pid)); end if;
  if v_act <> 'maju' then raise exception 'Aksi tidak dikenal.'; end if;
  if not game.pg_eligible(v_pid) then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;
  if game.pg_frozen(v_pid) then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;
  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;

  -- kunci baris quest (atau buat untuk langkah 0)
  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'peregrin', 0, '{}'::jsonb)
  on conflict (player_id, quest_id) do nothing;
  select step into v_step from game.player_quests where player_id = v_pid and quest_id = 'peregrin' for update;

  if v_step >= game.pg_last() then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;
  -- idempoten: klik ganda / dua perangkat
  if v_want is null or v_want <> v_step then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;

  d := game.pg_steps() -> v_step;
  v_city := game.current_city(v_pid);
  if v_city is distinct from (d ->> 'c') then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;

  -- waktu (jam dunia, bukan jam perangkat)
  if d ->> 't' = 'malam' and not game.fish_is_night() then raise exception 'Datanglah lagi saat lampu-lampu dinyalakan, Kapten.'; end if;
  if d ->> 't' = 'fajar' and not game.cb_is_dawn() then raise exception 'Belum fajar, Kapten.'; end if;

  -- mini game
  if d ? 'g' and v_res <> 'ok' then raise exception 'Belum berhasil, Kapten. Coba lagi.'; end if;

  -- barang yang harus dibawa
  if d ? 'need' then
    for it in select jsonb_array_elements_text(d -> 'need') loop
      if game.item_qty(v_pid, it) < 1 then raise exception 'Ada yang belum kau bawa, Kapten.'; end if;
    end loop;
  end if;

  -- barter (barang dagangan di palka, bukan di gudang)
  if d ? 'barter' then
    v_comm := d -> 'barter' ->> 0; v_qty := (d -> 'barter' ->> 1)::int;
    if game.item_qty(v_pid, v_comm) < v_qty then
      raise exception 'Bawa % % di palkamu dulu, Kapten.', v_qty, (select name from game.commodities where id = v_comm);
    end if;
  end if;

  -- ruang palka untuk barang yang diberikan (barang yang diambil di langkah yang sama ikut dihitung)
  if d ? 'give' and game.item_qty(v_pid, d ->> 'give') < 1 then
    select coalesce((effects ->> 'cargoSize')::numeric, 0) into v_size from game.item_catalog where item_id = d ->> 'give';
    v_need := coalesce(v_size, 0);
    if d ? 'take' then
      select v_need - coalesce(sum((c.effects ->> 'cargoSize')::numeric), 0) into v_need
        from jsonb_array_elements_text(d -> 'take') t(x) join game.item_catalog c on c.item_id = t.x
       where game.item_qty(v_pid, t.x) > 0;
    end if;
    if d ? 'barter' then
      v_need := v_need - v_qty * coalesce((select size from game.commodities where id = v_comm), 1);
    end if;
    v_free := game.cargo_free(v_pid);
    if v_need > 0 and v_free < v_need then raise exception 'Kosongkan dulu palkamu, Kapten. Butuh % ruang.', ceil(v_need)::int; end if;
  end if;

  -- jalankan
  if d ? 'barter' then perform game.adjust_inventory(v_pid, v_comm, -v_qty); end if;
  if d ? 'take' then
    for it in select jsonb_array_elements_text(d -> 'take') loop
      if game.item_qty(v_pid, it) > 0 then perform game.item_adjust(v_pid, it, -game.item_qty(v_pid, it)); end if;
    end loop;
  end if;
  if d ? 'give' and game.item_qty(v_pid, d ->> 'give') < 1 then perform game.item_adjust(v_pid, d ->> 'give', 1); end if;
  if coalesce((d ->> 'gold')::boolean, false) then
    v_gold := greatest(0, game.cfg_num('PeregrinReward', 25000))::bigint;
    update game.players set gold = gold + v_gold where player_id = v_pid;
  end if;

  update game.player_quests set step = v_step + 1, updated_at = now(),
    data = data || jsonb_build_object('s' || v_step, game.now_ms()),
    done_at = case when v_step + 1 >= game.pg_last() then now() else done_at end
   where player_id = v_pid and quest_id = 'peregrin';

  return jsonb_build_object('peregrin', game.pg_state(v_pid), 'gold', v_gold,
    'newGold', (select gold from game.players where player_id = v_pid));
end $$;
select game.expose('api_peregrin');

-- ---------------------------------------------------------------------
-- Alat uji GM (SQL Editor): select game.admin_peregrin('abuy', 12);
-- Menyetel langkah dan mengisi bagian mesin yang seharusnya sudah dimiliki di langkah itu.
-- ---------------------------------------------------------------------
create or replace function game.admin_peregrin(p_username text, p_step int) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid; s int; d jsonb; it text;
begin
  select player_id into v_pid from game.players where lower(username) = lower(p_username);
  if v_pid is null then raise exception 'Pemain % tidak ditemukan.', p_username; end if;
  s := greatest(0, least(game.pg_last(), coalesce(p_step, 0)));
  for it in select item_id from game.item_catalog where item_id like 'qi\_pg\_%' loop
    if game.item_qty(v_pid, it) > 0 then perform game.item_adjust(v_pid, it, -game.item_qty(v_pid, it)); end if;
  end loop;
  for i in 0 .. s - 1 loop
    d := game.pg_steps() -> i;
    if d ? 'take' then
      for it in select jsonb_array_elements_text(d -> 'take') loop
        if game.item_qty(v_pid, it) > 0 then perform game.item_adjust(v_pid, it, -1); end if;
      end loop;
    end if;
    if d ? 'give' and game.item_qty(v_pid, d ->> 'give') < 1 then perform game.item_adjust(v_pid, d ->> 'give', 1); end if;
  end loop;
  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'peregrin', s, '{}'::jsonb)
  on conflict (player_id, quest_id) do update set step = s, updated_at = now(),
    done_at = case when s >= game.pg_last() then now() else null end;
  return game.pg_state(v_pid);
end $$;
revoke all on function game.admin_peregrin(text, int) from public;

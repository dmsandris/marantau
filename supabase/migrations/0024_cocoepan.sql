-- =====================================================================
-- Marantau (Supabase) - 0024 SAGA 2 · QUEST 6 "BUNGA YANG TAK PERNAH LAYU"
-- Prasyarat: Quest 5 (kompas) selesai + 2 hari game. Saldo bank >= 1.000.000 saat bicara
-- dengan Coco Epan. Pinjaman ditahan 10 hari game, dikembalikan 2x lipat (bunga 10%/hari sederhana).
-- Pulau baru Gading Island (tersembunyi, terbuka setelah bunga melati diterima), kopi baru.
--
-- Langkah (game.player_quests, quest_id = 'cocoepan'):
--   0  belum mulai (ready = 2 hari game sejak Quest 5 selesai)
--   1  Babak 1  Javasche Bank - 'talk' (saldo >= 1 juta). 'loan' jumlah | 'decline'
--   2  Babak 2  pinjaman diberikan; Peti Bantuan (qi_peti_bantuan) -> 'deliver' di IKN
--   3           Mata Syahbandar 'syahbandar' di Joungjava (data.syah)
--   4  Babak 3  'flower' di Joungjava (bunga melati) -> Gading Island terbuka (peta meluas)
--   5           'stumpy' di Gading Island (felyx)
--   6           'grave' di Gading Island: bunga dipersembahkan, Buku Pancing Maudy diterima
--   7           ikan legenda Gading Island tertangkap (kait fish_quest_catch, otomatis)
--   8  Babak 4  'mural' di Gading Island - Sandi Pelikan selesai
--  9  Babak 5  'return' di Joungjava pada hari ke-10 pinjaman: pengembalian 2x lipat (dibayar)
--  10           'gasing' won|lost (Coco Epan) - adu gasing setelah pelunasan
--  12           'surat' di Marie Regal - surat Coco Epan dikirim ke Marlya; selesai
-- Aman diulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Item quest
-- ---------------------------------------------------------------------
insert into game.item_catalog(item_id, name, type, effects, value, price, source, sort) values
  ('qi_peti_bantuan', 'Peti Bantuan', 'quest',
   '{"cargoSize": 10, "desc": "Peti beras dan garam dari gudang Javasche Bank. Untuk Kamp Pemulung IKN."}',
   0, null, 'quest', 93),
  ('qi_bunga_melati', 'Seikat Bunga Melati Kering', 'quest',
   '{"cargoSize": 1, "desc": "Bunga melati kering dari Coco Epan. Untuk diletakkan di makam di Gading Island."}',
   0, null, 'quest', 94),
  ('qi_buku_pancing_maudy', 'Buku Pancing Legenda', 'quest',
   '{"cargoSize": 1, "desc": "Buku memancing milik Nyonya Maudy. 21 ikan legenda, satu terisi tanda bintang."}',
   0, null, 'quest', 95)
on conflict (item_id) do update set name = excluded.name, type = excluded.type, effects = excluded.effects,
  value = excluded.value, price = excluded.price, source = excluded.source, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Pulau Gading Island (tersembunyi) + kopi baru
-- ---------------------------------------------------------------------
insert into game.cities(city_id, name, type, repair_cost_rate, image_url, map_x, map_y, sort, hidden)
values ('gading_island', 'Gading Island', 'Gading', 1.2, '', 135, 40, 9, true)
on conflict (city_id) do update set name = excluded.name, type = excluded.type, map_x = excluded.map_x,
  map_y = excluded.map_y, hidden = true;

insert into game.commodities(id, name, flavor, sort, grp, tier, base, size, spread, elast, ref, active) values
  ('kopi_bourbon_chiroso', 'Bourbon Chiroso', 'Kopi paling langka dari bukit Gading Island. Stok kecil, harganya sepadan.', 40, 'kopi', 'rare',     420, 1, 0.12, 0.55, 150, true),
  ('kopi_flores_bajawa',   'Flores Bajawa',   'Kopi menengah beraroma rempah dan cokelat gelap.',                          41, 'kopi', 'uncommon', 230, 1, 0.12, 0.55, 150, true),
  ('kopi_sumatera_gayo',   'Sumatera Gayo',   'Kopi paling umum dari ketiganya, pahit yang jujur.',                        42, 'kopi', 'common',   160, 1, 0.12, 0.55, 150, true)
on conflict (id) do update set name = excluded.name, flavor = excluded.flavor, sort = excluded.sort, grp = excluded.grp,
  tier = excluded.tier, base = excluded.base, size = excluded.size, active = true;

-- Pasar kopi: hanya di Gading Island (produsen) - kopi baru dijual di Stumpy & pasar Gading Island.
-- Permintaan kopi di kota lain ditunda ke tahap berikutnya (tidak mengubah pasar kota lama).
insert into game.market(city_id, commodity_id, base_price, current_price, role)
select 'gading_island', k.id, k.base, k.base, 'produce'
  from game.commodities k
 where k.grp = 'kopi'
on conflict (city_id, commodity_id) do nothing;

-- ---------------------------------------------------------------------
-- Konstanta & helper
-- ---------------------------------------------------------------------
create or replace function game.cb_loan_min() returns bigint language sql immutable as $$ select 1000000::bigint $$;
create or replace function game.cb_hold_days() returns int language sql immutable as $$ select 10 $$;
create or replace function game.cb_ready_days() returns numeric language sql immutable as $$ select 2::numeric $$;
create or replace function game.cb_rate() returns numeric language sql immutable as $$ select 0.10::numeric $$;

create or replace function game.cb_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'cocoepan'), 0) $$;

create or replace function game.cb_day_ms() returns bigint
language sql stable as $$ select (game.cfg_num('GameDayLengthRealMinutes', 60) * 60000)::bigint $$;

-- Kapan Quest 5 selesai (ms) - null bila belum
create or replace function game.cb_kp_done_ms(p_pid uuid) returns bigint
language sql stable as $$
  select (extract(epoch from coalesce(done_at, updated_at, now())) * 1000)::bigint
    from game.player_quests where player_id = p_pid and quest_id = 'kompas' and step >= 8
$$;

-- Pengembalian pinjaman (2x) = pokok + bunga sederhana selama masa tahan
create or replace function game.cb_repay_amount(p_loan bigint) returns bigint
language sql immutable as $$
  select round(p_loan * (1 + game.cb_rate() * game.cb_hold_days()))::bigint
$$;

-- Ikan legenda Gading Island: hanya tertangkap saat langkah 6 (berdasarkan kait fish_quest_weight)
insert into game.mp_fish_types(id, name, v, w, zone, sp, rarity, kg_min, kg_max, stam, pow, agi, depth, tod, cities, kind, hint, sort)
values ('legenda_gading', 'Ikan Legenda Gading', 900, 0.4, 0.3, 1.2, 4, 0.6, 2.0, 2.6, 0.8, 0.7, 2, 'any',
        array['gading_island'], 'fish', 'Ikan yang tercatat di Buku Pancing Maudy. Konon hanya muncul untuk yang sabar.', 99)
on conflict (id) do update set name = excluded.name, v = excluded.v, w = excluded.w, zone = excluded.zone,
  sp = excluded.sp, rarity = excluded.rarity, kg_min = excluded.kg_min, kg_max = excluded.kg_max, stam = excluded.stam,
  pow = excluded.pow, agi = excluded.agi, depth = excluded.depth, tod = excluded.tod, cities = excluded.cities,
  kind = excluded.kind, hint = excluded.hint, sort = excluded.sort;

-- Bobot ikan legenda hanya aktif saat langkah 6 (di Gading Island); selain itu nyaris mustahil
create or replace function game.fish_quest_weight(p_pid uuid, p_fish text, p_city text) returns numeric
language plpgsql stable as $$
begin
  if p_fish = 'legenda_gading' then return case when game.cb_step(p_pid) = 6 then 1 else 0.0001 end; end if;
  return game.bx_fish_quest_weight(p_pid, p_fish, p_city);  -- Peti Karam Bjorneo (0022)
end $$;

-- Menangkap ikan legenda di langkah 6 -> langkah 7 (halaman pertama Buku Pancing terisi)
create or replace function game.fish_quest_catch(p_pid uuid, p_fish text) returns jsonb
language plpgsql as $$
begin
  if p_fish = 'legenda_gading' then
    if game.cb_step(p_pid) = 6 and game.current_city(p_pid) = 'gading_island' then
      update game.player_quests set step = 7, data = data || '{"legend": true}'::jsonb, updated_at = now()
       where player_id = p_pid and quest_id = 'cocoepan';
      perform game.log(p_pid, 'Ikan legenda Gading Island tertangkap. Halaman pertama Buku Pancing Legenda kini terisi.');
    end if;
    return null;
  end if;
  return game.bx_fish_quest_catch(p_pid, p_fish);  -- Peti Karam Bjorneo (0022)
end $$;

-- Pulau terbuka untuk pemain yang sudah memasuki Babak 3 (lihat city_open)
create or replace function game.city_open(p_pid uuid, p_city text) returns boolean
language sql stable as $$
  select coalesce((select not hidden from game.cities where city_id = p_city), false)
      or (p_city = 'paradiso' and game.gala_step(p_pid) >= 6)
      or (p_city = 'marie_regal' and game.ww_step(p_pid) >= 1)
      or (p_city = 'titik_buta' and game.bx_step(p_pid) = 4 and game.fish_is_night())
      or (p_city = 'pusaran' and game.bx_step(p_pid) between 7 and 15)
      or (p_city = 'gading_island' and game.cb_step(p_pid) >= 4)
$$;

-- ---------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------
create or replace function game.cb_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare q game.player_quests; v_kp bigint := game.cb_kp_done_ms(p_pid); v_step int; v_ready bigint;
  v_bank bigint; v_loan bigint; v_loan_day int; v_day int; v_left int;
begin
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'cocoepan';
  if not found and v_kp is null then return null; end if;
  v_step := coalesce(q.step, 0);
  v_ready := coalesce(v_kp, 0) + (game.cb_ready_days() * game.cb_day_ms())::bigint;
  select coalesce(bank_balance, 0) into v_bank from game.players where player_id = p_pid;
  v_loan := coalesce((q.data ->> 'loan')::bigint, 0);
  v_loan_day := coalesce((q.data ->> 'loanDay')::int, 0);
  v_day := game.game_day();
  v_left := case when v_loan > 0 then greatest(0, v_loan_day + game.cb_hold_days() - v_day) end;
  return jsonb_build_object(
    'step', v_step,
    'eligible', v_kp is not null,
    'readyInMs', case when v_step = 0 then greatest(0, v_ready - game.now_ms()) end,
    'timeOk', v_kp is not null and game.now_ms() >= v_ready,
    'bankNeed', game.cb_loan_min(),
    'bankBalance', v_bank,
    'bankOk', v_bank >= game.cb_loan_min(),
    'declined', coalesce((q.data ->> 'declined')::boolean, false),
    'loan', case when v_loan > 0 then v_loan end,
    'repay', case when v_loan > 0 then game.cb_repay_amount(v_loan) end,
    'holdDaysLeft', v_left,
    'repayReady', v_step = 8 and coalesce(v_left, 1) = 0,
    'syah', coalesce((q.data ->> 'syah')::boolean, false),
    'gasing', q.data ->> 'gasing',
    'mural', coalesce((q.data ->> 'mural')::boolean, false),
    'legend', coalesce((q.data ->> 'legend')::boolean, false),
    'flowerGiven', coalesce((q.data ->> 'flower')::boolean, false),
    'hasCrate', game.item_qty(p_pid, 'qi_peti_bantuan') > 0,
    'hasFlower', game.item_qty(p_pid, 'qi_bunga_melati') > 0,
    'bookGiven', coalesce((q.data ->> 'book')::boolean, false),
    'done', v_step >= 12);
end $$;

-- ---------------------------------------------------------------------
-- Aksi quest. a = [action, arg]
--   status | talk | loan [jumlah] | decline | deliver | syahbandar | flower | stumpy
--   | grave | mural | return | gasing [won|lost] | surat
-- ---------------------------------------------------------------------
create or replace function game.cb_set(p_pid uuid, p_step int, p_data jsonb) returns void
language sql as $$
  update game.player_quests set step = p_step, data = data || coalesce(p_data, '{}'::jsonb), updated_at = now(),
    done_at = case when p_step >= 12 then now() else done_at end
   where player_id = p_pid and quest_id = 'cocoepan'
$$;

create or replace function public.api_cocoEpan(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status'); v_arg text := lower(btrim(coalesce(game.arg(a, 1), '')));
  q game.player_quests; v_step int; v_city text := game.current_city(v_pid); st jsonb;
  v_amt bigint; v_bank bigint; v_day int; v_repay bigint;
begin
  st := game.cb_state(v_pid);
  if v_act = 'status' then return jsonb_build_object('cocoepan', st); end if;
  if st is null then raise exception 'Pintu bank itu belum terbuka untukmu, Kapten.'; end if;
  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;

  select * into q from game.player_quests where player_id = v_pid and quest_id = 'cocoepan' for update;
  v_step := coalesce(q.step, 0);
  if v_step = 0 and v_act <> 'talk' then raise exception 'Coco Epan belum memanggilmu.'; end if;

  -- Babak 1: Javasche Bank, Joungjava
  if v_act = 'talk' then
    if v_step > 1 then return jsonb_build_object('cocoepan', st); end if;
    if v_step = 0 then
      if not coalesce((st ->> 'timeOk')::boolean, false) then raise exception 'Coco Epan belum punya waktu untukmu, Kapten.'; end if;
    end if;
    if v_city <> 'joungjava' then raise exception 'Pak Tua Karto menunggu di Joungjava.'; end if;
    if v_step = 0 and not coalesce((st ->> 'bankOk')::boolean, false) then
      raise exception 'Kembalilah saat bankmu lebih berat dari sakumu.';
    end if;
    if v_step = 0 then
      insert into game.player_quests(player_id, quest_id, step, data)
      values (v_pid, 'cocoepan', 1, '{}'::jsonb)
      on conflict (player_id, quest_id) do update set step = 1, started_at = now(), updated_at = now();
      perform game.log(v_pid, 'Pak Tua Karto: "Ada orang tua bertopi bulat yang menanyakan namamu." Javasche Bank sepi, brankas setengah kosong.');
    end if;
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  if v_act = 'decline' then
    if v_step <> 1 then raise exception 'Tidak ada pinjaman yang ditawarkan.'; end if;
    if v_city <> 'joungjava' then raise exception 'Coco Epan menunggu di Joungjava.'; end if;
    perform game.cb_set(v_pid, 1, jsonb_build_object('declined', true));
    perform game.log(v_pid, 'Coco Epan: "Saya mengerti. Pintu ini tidak pernah dikunci untukmu."');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  if v_act = 'loan' then
    if v_step <> 1 then raise exception 'Pinjaman ini sudah diberikan atau belum waktunya.'; end if;
    if v_city <> 'joungjava' then raise exception 'Coco Epan menunggu di Joungjava.'; end if;
    v_amt := game.arg_int(a, 1);
    if v_amt is null or v_amt < game.cb_loan_min() then
      raise exception 'Pinjaman minimal 1.000.000 gold, Kapten.';
    end if;
    select coalesce(bank_balance, 0) into v_bank from game.players where player_id = v_pid for update;
    if v_amt > v_bank then raise exception 'Saldo Bank tidak cukup untuk pinjaman itu.'; end if;
    v_day := game.game_day();
    update game.players set bank_balance = bank_balance - v_amt where player_id = v_pid;
    perform game.cb_set(v_pid, 2, jsonb_build_object('loan', v_amt, 'loanDay', v_day, 'declined', false));
    if game.item_qty(v_pid, 'qi_peti_bantuan') < 1 then perform game.item_adjust(v_pid, 'qi_peti_bantuan', 1); end if;
    perform game.log(v_pid, 'Meminjamkan ' || v_amt || ' gold kepada Coco Epan. Ditahan 10 hari game, kembali 2x lipat.');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid), 'crate', 'qi_peti_bantuan',
      'newGold', v_me.gold);
  end if;

  -- Babak 2: Peti Bantuan ke Kamp Pemulung IKN, Mata Syahbandar
  if v_act = 'deliver' then
    if v_step <> 2 then raise exception 'Peti Bantuan belum waktunya diantar.'; end if;
    if v_city <> 'ikn' then raise exception 'Kamp Pemulung ada di IKN.'; end if;
    if game.item_qty(v_pid, 'qi_peti_bantuan') < 1 then raise exception 'Peti Bantuan tidak ada di palkamu.'; end if;
    perform game.item_adjust(v_pid, 'qi_peti_bantuan', -1);
    perform game.cb_set(v_pid, 3, null);
    perform game.log(v_pid, 'Peti Bantuan dibagikan di Kamp Pemulung IKN. Seorang anak bertanya: "Kenapa orang kaya itu membagi beras?"');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  if v_act = 'syahbandar' then
    if v_step <> 3 then raise exception 'Mata Syahbandar belum perlu diperiksa.'; end if;
    if v_city <> 'joungjava' then raise exception 'Syahbandar Joungjava menunggumu.'; end if;
    if v_arg not in ('ok', 'gagal') then raise exception 'Hasil pemeriksaan tidak dikenal.'; end if;
    if v_arg = 'ok' then
      perform game.cb_set(v_pid, 3, jsonb_build_object('syah', true));
      perform game.log(v_pid, 'Kapal penimbun yang menyamar sebagai kapal bantuan bank berhasil ditemukan.');
    end if;
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  -- Babak 3: bunga melati, Gading Island
  if v_act = 'flower' then
    if v_step <> 3 or not coalesce((q.data ->> 'syah')::boolean, false) then
      raise exception 'Coco Epan belum punya bunga untukmu.';
    end if;
    if v_city <> 'joungjava' then raise exception 'Coco Epan menunggu di Joungjava.'; end if;
    perform game.cb_set(v_pid, 4, jsonb_build_object('flower', true));
    if game.item_qty(v_pid, 'qi_bunga_melati') < 1 then perform game.item_adjust(v_pid, 'qi_bunga_melati', 1); end if;
    perform game.log(v_pid, 'Coco Epan menyerahkan seikat bunga melati kering: "Ada pulau di timur, jauh melewati menara kaca."');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  if v_act = 'stumpy' then
    if v_step <> 4 then raise exception 'Kedai itu belum terbuka untukmu.'; end if;
    if v_city <> 'gading_island' then raise exception 'Stumpy ada di Gading Island.'; end if;
    perform game.cb_set(v_pid, 5, null);
    perform game.log(v_pid, 'felyx menyeduh kopi tanpa gula: "Kalau terasa manis, itu bijinya yang jujur."');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  if v_act = 'grave' then
    if v_step <> 5 then raise exception 'Makam itu belum perlu kau kunjungi.'; end if;
    if v_city <> 'gading_island' then raise exception 'Makam ada di bukit belakang klenteng Gading Island.'; end if;
    if game.item_qty(v_pid, 'qi_bunga_melati') < 1 then raise exception 'Kau belum membawa bunga.'; end if;
    perform game.item_adjust(v_pid, 'qi_bunga_melati', -1);
    if game.item_qty(v_pid, 'qi_buku_pancing_maudy') < 1 then perform game.item_adjust(v_pid, 'qi_buku_pancing_maudy', 1); end if;
    perform game.cb_set(v_pid, 6, jsonb_build_object('book', true));
    perform game.log(v_pid, 'Bunga melati diletakkan di makam Nyonya Maudy. felyx menyerahkan Buku Pancing Legenda.');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid),
      'item', jsonb_build_object('itemId', 'qi_buku_pancing_maudy', 'name', 'Buku Pancing Legenda'));
  end if;

  -- Babak 4: mural dua nakhoda (Sandi Pelikan dimainkan di klien)
  if v_act = 'mural' then
    if v_step <> 7 then raise exception 'Dinding di gudang belakang belum terbuka.'; end if;
    if v_city <> 'gading_island' then raise exception 'Gudang di balik Stumpy ada di Gading Island.'; end if;
    perform game.cb_set(v_pid, 8, jsonb_build_object('mural', true));
    perform game.log(v_pid, 'Sandi Pelikan terbaca: dua pendiri Moramora, Kumis Hitam, dan dinding yang dikerok.');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  -- Babak 5: hari kesepuluh, pengembalian 2x lipat
  if v_act = 'return' then
    if v_step <> 8 and v_step <> 9 then raise exception 'Coco Epan belum memanggilmu kembali.'; end if;
    if v_city <> 'joungjava' then raise exception 'Coco Epan menunggu di Joungjava.'; end if;
    if v_step = 8 then
      if game.cb_state(v_pid) ->> 'holdDaysLeft' <> '0' then
        raise exception 'Belum waktunya, Kapten. Saya menepati janji, bukan mempercepatnya.';
      end if;
      v_repay := game.cb_repay_amount(coalesce((q.data ->> 'loan')::bigint, 0));
      update game.players set gold = gold + v_repay where player_id = v_pid;
      perform game.cb_set(v_pid, 9, jsonb_build_object('repaid', v_repay));
      perform game.log(v_pid, 'Coco Epan melunasi pinjaman 2x lipat: ' || v_repay || ' gold. "Utang emas memang yang paling mudah dibayar."');
    end if;
    return jsonb_build_object('cocoepan', game.cb_state(v_pid), 'newGold', (select gold from game.players where player_id = v_pid));
  end if;

  if v_act = 'gasing' then
    if v_step <> 9 then raise exception 'Coco Epan belum mengeluarkan gasing tuanya.'; end if;
    if v_city <> 'joungjava' then raise exception 'Coco Epan menunggu di Joungjava.'; end if;
    if v_arg not in ('won', 'lost') then raise exception 'Hasil adu gasing tidak dikenal.'; end if;
    perform game.cb_set(v_pid, 10, jsonb_build_object('gasing', v_arg));
    perform game.log(v_pid, case when v_arg = 'won' then 'Adu gasing melawan Coco Epan: menang. "Ia akan menyukaimu."'
      else 'Adu gasing melawan Coco Epan: kalah. "Kau mengalah? Ia juga tak pernah mengalah."' end);
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  -- Epilog: surat Coco Epan ke Marlya
  if v_act = 'surat' then
    if v_step <> 10 then raise exception 'Surat itu belum disegel.'; end if;
    if v_city <> 'marie_regal' then raise exception 'Marlya membaca surat di Istana Hening, Marie Regal.'; end if;
    perform game.cb_set(v_pid, 12, null);
    perform game.log(v_pid, 'Surat Coco Epan sampai ke tangan Marlya. Ia melipatnya tanpa sepatah kata. Pelikannya tidak terbang membawa balasan.');
    return jsonb_build_object('cocoepan', game.cb_state(v_pid));
  end if;

  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_cocoepan');

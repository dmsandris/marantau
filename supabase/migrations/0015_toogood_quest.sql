-- =====================================================================
-- Marantau (Supabase) - 0015 MISI "PEMBEBASAN TOOGOOD" (Tide v12)
-- Terbuka setelah misi Uda Gala selesai. Penjaga Arsip Gelap TooGood, zafachmie,
-- meminta bantuan membebaskan pulaunya:
--   1 kumpulkan 3 surat pengusiran dari gubernur (tiap gubernur memberi tugas kecil)
--   2 bawa surat ke pemerintah dunia di IKN -> Jendral Tedsky ternyata dalangnya;
--     pemain diusir dari IKN & diburu bajak laut di SETIAP pelayaran
--   3 lapor zafachmie   4 minta kode sandi ke Teh Euis (menolak)
--   5 temui dwi de'clown di Black's Alley (malam)   6 lengkapi Buku Ikan 14/14
--   7 masukkan kode sandi di dok -> kapal legenda Black Pearl (dipinjam)
--   8 kabarkan kejahatan Tedsky ke 5 gubernur -> Tedsky ditangkap
--   9 kembali ke zafachmie -> TooGood merdeka, Black Pearl dikembalikan, 100.000 gold
--  10 selesai (TooGood jadi pulau damai & memulihkan kapal +1 tiap 5 detik)
-- Aman diulang.
-- =====================================================================

create or replace function game.tg_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'toogood'), 0) $$;

create or replace function game.toogood_freed(p_pid uuid) returns boolean
language sql stable as $$ select game.tg_step(p_pid) >= 10 $$;

-- Tugas kecil tiap gubernur (pilih minimal 3)
create or replace function game.tg_govs() returns jsonb
language sql immutable as $$
  select '{
    "sunda_empire": {"kind": "deliver", "item": "tools",  "qty": 12},
    "joungjava":    {"kind": "deliver", "item": "silk",   "qty": 8},
    "bjorneo":      {"kind": "wins",                      "qty": 2},
    "skitraw":      {"kind": "gold",                      "qty": 5000},
    "paradiso":     {"kind": "deliver", "item": "spices", "qty": 10}
  }'::jsonb
$$;

-- Pulau yang harus dikabari soal kejahatan Tedsky
create or replace function game.tg_inform_targets() returns text[]
language sql immutable as $$ select array['sunda_empire', 'joungjava', 'bjorneo', 'skitraw', 'paradiso'] $$;

create or replace function game.tg_book(p_pid uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'found', (select count(*)::int from game.mp_fish_book b join game.mp_fish_types t on t.id = b.fish_id where b.player_id = p_pid),
    'total', (select count(*)::int from game.mp_fish_types))
$$;

create or replace function game.toogood_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare q game.player_quests; v_step int; v_govs jsonb := game.tg_govs(); v_tasks jsonb; k text; inv int; v_prog jsonb := '{}'::jsonb;
begin
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'toogood';
  v_step := coalesce(q.step, 0);
  if v_step = 0 and game.gala_step(p_pid) < 6 then return null; end if;
  v_tasks := coalesce(q.data -> 'tasks', '{}'::jsonb);
  if v_step = 1 then
    for k in select jsonb_object_keys(v_govs) loop
      if v_govs -> k ->> 'kind' = 'deliver' then
        select coalesce(sum(qty), 0) into inv from game.inventory where player_id = p_pid and item_id = v_govs -> k ->> 'item';
        v_prog := v_prog || jsonb_build_object(k, inv);
      elsif v_govs -> k ->> 'kind' = 'wins' then
        v_prog := v_prog || jsonb_build_object(k, coalesce((v_tasks -> k ->> 'wins')::int, 0));
      else
        v_prog := v_prog || jsonb_build_object(k, (select gold from game.players where player_id = p_pid));
      end if;
    end loop;
  end if;
  return jsonb_build_object(
    'step', v_step,
    'letters', coalesce(q.data -> 'letters', '[]'::jsonb),
    'tasks', v_tasks,
    'progress', v_prog,
    'govs', v_govs,
    'need', 3,
    'informed', coalesce(q.data -> 'informed', '[]'::jsonb),
    'informTargets', to_jsonb(game.tg_inform_targets()),
    'hunted', v_step between 3 and 8,
    'pearl', v_step between 8 and 9,
    'night', game.fish_is_night(),
    'book', game.tg_book(p_pid),
    'freed', v_step >= 10);
end $$;

-- ---------------------------------------------------------------------
-- Pemburu bayaran Tedsky: mencegat SETIAP pelayaran selama langkah 3..8
-- ---------------------------------------------------------------------
create or replace function game.tg_hunter_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql volatile as $$
declare v_step int := game.tg_step(p_pid); ship jsonb; lvl int; max_hp numeric; ammo numeric; names text[];
begin
  if v_step not between 3 and 8 then return null; end if;
  ship := coalesce(game.ship_json(p_pid), '{}'::jsonb);
  lvl := case when v_step = 8 then 4 + floor(random() * 3)::int else 3 + floor(random() * 3)::int end;
  names := array['sekoci penyamun bayaran', 'brigantin berbendera merah', 'fregat pemburu hadiah', 'kapal perompak sewaan', 'armada pembunuh bayaran'];
  max_hp := game.cfg_num('CombatEnemyBaseHp', 40) + lvl * game.cfg_num('CombatEnemyHpPerLevel', 25);
  ammo := coalesce(nullif(game.voy_num(ship -> 'MaxCannonAmmo'), 0), game.cfg_num('CombatBaseAmmo', 3));
  return jsonb_build_object(
    'enemyLevel', lvl,
    'enemyName', 'Pemburu Tedsky: ' || names[1 + floor(random() * array_length(names, 1))::int],
    'hunter', true,
    'rolledAt', game.iso(now()),
    'enemyMaxHp', max_hp, 'enemyHp', max_hp,
    'maxAmmo', ammo, 'ammoRemaining', ammo, 'round', 1);
end $$;

create or replace function game.quest_boss_encounter(p_pid uuid, p_dest text) returns jsonb
language sql as $$ select coalesce(game.gala_boss_encounter(p_pid, p_dest), game.tg_hunter_encounter(p_pid, p_dest)) $$;

-- Tugas gubernur Bjorneo: hitung kemenangan setelah tugas diterima
create or replace function game.quest_combat_won(p_pid uuid) returns void
language plpgsql as $$
declare k text;
begin
  if game.tg_step(p_pid) <> 1 then return; end if;
  for k in select key from jsonb_each(game.tg_govs()) where value ->> 'kind' = 'wins' loop
    update game.player_quests
       set data = jsonb_set(data, array['tasks', k, 'wins'], to_jsonb(coalesce((data #>> array['tasks', k, 'wins'])::int, 0) + 1)),
           updated_at = now()
     where player_id = p_pid and quest_id = 'toogood'
       and data #> array['tasks', k] is not null
       and not coalesce(data -> 'letters', '[]'::jsonb) ? k;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Black Pearl (dipinjam selama langkah 8..9)
-- ---------------------------------------------------------------------
create or replace function game.ship_legend(p_pid uuid) returns text
language sql stable as $$ select case when game.tg_step(p_pid) between 8 and 9 then 'pearl' end $$;

create or replace function game.ship_locked(p_pid uuid) returns text
language sql stable as $$
  select case when game.tg_step(p_pid) between 8 and 9
    then 'Black Pearl adalah kapal legenda TooGood - tidak bisa dicat ulang atau diganti nama.' end
$$;

create or replace function game.tg_pearl_on(p_pid uuid) returns void
language plpgsql as $$
declare s game.ships; up jsonb; eff jsonb;
begin
  select * into s from game.ships where player_id = p_pid for update;
  select coalesce(ship_upgrades, '{}'::jsonb) into up from game.players where player_id = p_pid;
  if jsonb_typeof(up) <> 'object' then up := '{}'::jsonb; end if;
  update game.player_quests set data = data || jsonb_build_object('own', jsonb_build_object('ship', to_jsonb(s), 'upgrades', up))
   where player_id = p_pid and quest_id = 'toogood';
  update game.players set ship_upgrades = up || jsonb_build_object(
      'speed', jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 0),
      'condition', jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 200),
      'cannons', jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 0))
   where player_id = p_pid;
  update game.ships set ship_name = 'Black Pearl', tier = 'V', speed = s.speed + 25, combat = s.combat + 40,
      armor = s.armor + 40, navigation = s.navigation + 20, condition = 300
   where player_id = p_pid;
end $$;

create or replace function game.tg_pearl_off(p_pid uuid) returns void
language plpgsql as $$
declare own jsonb; cur jsonb; eff numeric;
begin
  select data -> 'own' into own from game.player_quests where player_id = p_pid and quest_id = 'toogood';
  if own is null then return; end if;
  select coalesce(ship_upgrades, '{}'::jsonb) into cur from game.players where player_id = p_pid;
  -- upgrade cargo yang dibeli selama memakai Black Pearl tetap jadi milik pemain
  update game.players set ship_upgrades = coalesce(own -> 'upgrades', '{}'::jsonb)
      || case when cur ? 'cargo' then jsonb_build_object('cargo', cur -> 'cargo') else '{}'::jsonb end
   where player_id = p_pid;
  update game.ships set ship_name = own -> 'ship' ->> 'ship_name', tier = own -> 'ship' ->> 'tier',
      speed = (own -> 'ship' ->> 'speed')::int, combat = (own -> 'ship' ->> 'combat')::int,
      armor = (own -> 'ship' ->> 'armor')::int, navigation = (own -> 'ship' ->> 'navigation')::int
   where player_id = p_pid;
  -- kapal sendiri dikembalikan dalam kondisi prima (dirawat kru zafachmie)
  eff := game.voy_num(game.ship_json(p_pid) -> 'EffectiveMaxCondition');
  update game.ships set condition = eff where player_id = p_pid;
  update game.player_quests set data = data - 'own' where player_id = p_pid and quest_id = 'toogood';
end $$;

-- TooGood yang merdeka ikut memulihkan kapal
create or replace function game.heal_city(p_pid uuid, p_city text) returns boolean
language sql stable as $$ select p_city = 'paradiso' or (p_city = 'toogood' and game.toogood_freed(p_pid)) $$;

-- ---------------------------------------------------------------------
-- Aksi misi. a = [action, arg]
--   status | accept | gov | ikn | zafa | euis | dwi | unlock [kode] | inform
-- ---------------------------------------------------------------------
create or replace function public.api_toogoodQuest(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status'); v_arg text := coalesce(game.arg(a, 1), '');
  q game.player_quests; v_step int; v_city text := game.current_city(v_pid);
  v_govs jsonb := game.tg_govs(); g jsonb; v_letters jsonb; v_task jsonb; have bigint; v_code text;
  v_book jsonb; v_informed jsonb; v_sail jsonb; v_gold bigint;
begin
  if v_act = 'status' then return jsonb_build_object('toogood', game.toogood_state(v_pid)); end if;
  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;
  select * into q from game.player_quests where player_id = v_pid and quest_id = 'toogood' for update;
  v_step := coalesce(q.step, 0);
  v_letters := coalesce(q.data -> 'letters', '[]'::jsonb);

  -- 0 -> 1: zafachmie meminta tolong
  if v_act = 'accept' then
    if v_step > 0 then raise exception 'Kamu sudah berjanji membantu zafachmie.'; end if;
    if game.gala_step(v_pid) < 6 then raise exception 'zafachmie belum mengenalmu.'; end if;
    if v_city <> 'toogood' then raise exception 'zafachmie hanya ada di Arsip Gelap, TooGood.'; end if;
    insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'toogood', 1, '{"letters": [], "tasks": {}}');
    perform game.log(v_pid, 'Berjanji kepada zafachmie untuk membebaskan TooGood dari para penyamun.');
    return jsonb_build_object('toogood', game.toogood_state(v_pid));
  end if;

  -- 1: gubernur - terima tugas / selesaikan tugas / dapat surat
  if v_act = 'gov' then
    if v_step <> 1 then raise exception 'Gubernur tidak punya urusan denganmu saat ini.'; end if;
    g := v_govs -> v_city;
    if g is null then raise exception 'Tidak ada gubernur yang bisa mengesahkan surat di pelabuhan ini.'; end if;
    if v_letters ? v_city then raise exception 'Gubernur di sini sudah menandatangani suratmu.'; end if;
    v_task := q.data -> 'tasks' -> v_city;
    if v_task is null then
      update game.player_quests set data = jsonb_set(data, array['tasks', v_city], jsonb_build_object('wins', 0)), updated_at = now()
       where player_id = v_pid and quest_id = 'toogood';
      return jsonb_build_object('taskAccepted', v_city, 'toogood', game.toogood_state(v_pid));
    end if;
    if g ->> 'kind' = 'deliver' then
      select coalesce(sum(qty), 0) into have from game.inventory where player_id = v_pid and item_id = g ->> 'item';
      if have < (g ->> 'qty')::int then
        raise exception 'Gubernur menunggu % %. Di palkamu baru ada %.', g ->> 'qty', game.commodity_name(g ->> 'item'), have;
      end if;
      perform game.adjust_inventory(v_pid, g ->> 'item', -((g ->> 'qty')::int));
    elsif g ->> 'kind' = 'gold' then
      if v_me.gold < (g ->> 'qty')::bigint then raise exception 'Gold-mu belum cukup untuk sumbangan % gold.', g ->> 'qty'; end if;
      update game.players set gold = gold - (g ->> 'qty')::bigint where player_id = v_pid;
    elsif g ->> 'kind' = 'wins' then
      if coalesce((v_task ->> 'wins')::int, 0) < (g ->> 'qty')::int then
        raise exception 'Kalahkan dulu % kapal bajak laut (baru %).', g ->> 'qty', coalesce((v_task ->> 'wins')::int, 0);
      end if;
    end if;
    v_letters := v_letters || to_jsonb(v_city);
    update game.player_quests set data = jsonb_set(data, '{letters}', v_letters),
        step = case when jsonb_array_length(v_letters) >= 3 then 2 else 1 end, updated_at = now()
     where player_id = v_pid and quest_id = 'toogood';
    perform game.log(v_pid, 'Gubernur ' || game.city_name(v_city) || ' menandatangani surat pengusiran penyamun TooGood (' || jsonb_array_length(v_letters) || '/3).');
    return jsonb_build_object('letter', v_city, 'count', jsonb_array_length(v_letters), 'toogood', game.toogood_state(v_pid),
      'newGold', (select gold from game.players where player_id = v_pid));
  end if;

  -- 2 -> 3: IKN, plot twist Tedsky, diusir & diburu
  if v_act = 'ikn' then
    if v_step <> 2 then raise exception 'Belum waktunya menghadap pemerintah dunia.'; end if;
    if v_city <> 'ikn' then raise exception 'Pemerintah dunia berkantor di IKN.'; end if;
    update game.player_quests set step = 3, data = data || '{"proof": true}', updated_at = now()
     where player_id = v_pid and quest_id = 'toogood';
    perform game.log(v_pid, 'IKN: Jendral Tedsky ternyata dalang kekacauan TooGood! Membawa bukti, diusir dari IKN dan diburu bajak laut bayarannya.');
    v_sail := public.api_setSail(jsonb_build_array('toogood'));
    return jsonb_build_object('expelled', true, 'sail', v_sail, 'toogood', game.toogood_state(v_pid));
  end if;

  -- 3 -> 4: lapor zafachmie | 9 -> 10: TooGood merdeka
  if v_act = 'zafa' then
    if v_city <> 'toogood' then raise exception 'zafachmie ada di TooGood.'; end if;
    if v_step = 3 then
      update game.player_quests set step = 4, updated_at = now() where player_id = v_pid and quest_id = 'toogood';
      perform game.log(v_pid, 'zafachmie membuka rahasia: sebuah kapal perang legenda tersembunyi di TooGood.');
      return jsonb_build_object('toogood', game.toogood_state(v_pid));
    end if;
    if v_step = 9 then
      perform game.tg_pearl_off(v_pid);
      update game.players set gold = gold + 100000 where player_id = v_pid;
      update game.player_quests set step = 10, done_at = now(), updated_at = now() where player_id = v_pid and quest_id = 'toogood';
      perform game.log(v_pid, 'TooGood merdeka! zafachmie kini gubernur, Black Pearl menjaga pulau, dan kapten menerima 100.000 gold.');
      return jsonb_build_object('freed', true, 'reward', 100000, 'toogood', game.toogood_state(v_pid),
        'ship', game.ship_json(v_pid), 'visual', game.ship_visual(v_pid),
        'newGold', (select gold from game.players where player_id = v_pid));
    end if;
    raise exception 'zafachmie mengangguk padamu, tapi belum ada yang perlu dibicarakan.';
  end if;

  -- 4 -> 5: Teh Euis menolak
  if v_act = 'euis' then
    if v_step <> 4 then raise exception 'Teh Euis sedang sibuk.'; end if;
    if v_city <> 'toogood' then raise exception 'Teh Euis ada di Benteng Kapten, TooGood.'; end if;
    update game.player_quests set step = 5, updated_at = now() where player_id = v_pid and quest_id = 'toogood';
    perform game.log(v_pid, 'Teh Euis menolak memberi kode sandi - tapi menyebut kencannya dengan dwi de''clown di Black''s Alley.');
    return jsonb_build_object('toogood', game.toogood_state(v_pid));
  end if;

  -- 5 -> 6 -> 7: dwi de'clown (hanya malam)
  if v_act = 'dwi' then
    if v_step not in (5, 6) then raise exception 'dwi de''clown hanya menuang minuman untukmu.'; end if;
    if v_city <> 'toogood' then raise exception 'dwi de''clown bekerja di Black''s Alley, TooGood.'; end if;
    if not game.fish_is_night() then raise exception 'Siang hari yang berjaga Daeng Sore. dwi de''clown baru datang saat malam.'; end if;
    v_book := game.tg_book(v_pid);
    if v_step = 5 then
      update game.player_quests set step = 6, updated_at = now() where player_id = v_pid and quest_id = 'toogood';
      perform game.log(v_pid, 'dwi de''clown mau memberi kode sandi - asal Buku Ikan sudah lengkap.');
      return jsonb_build_object('story', true, 'book', v_book, 'toogood', game.toogood_state(v_pid));
    end if;
    if (v_book ->> 'found')::int < (v_book ->> 'total')::int then
      return jsonb_build_object('needBook', true, 'book', v_book, 'toogood', game.toogood_state(v_pid));
    end if;
    update game.player_quests set step = 7, updated_at = now() where player_id = v_pid and quest_id = 'toogood';
    perform game.log(v_pid, 'dwi de''clown membisikkan kode sandi dan letak kapal perang legenda "Black Pearl".');
    return jsonb_build_object('code', 'thepowerofdreams', 'toogood', game.toogood_state(v_pid));
  end if;

  -- 7 -> 8: kode sandi di dok TooGood -> Black Pearl
  if v_act = 'unlock' then
    if v_step <> 7 then raise exception 'Pintu gua itu terkunci rapat.'; end if;
    if v_city <> 'toogood' then raise exception 'Kapal itu tersembunyi di TooGood.'; end if;
    v_code := lower(regexp_replace(v_arg, '[^a-zA-Z]', '', 'g'));
    if v_code <> 'thepowerofdreams' then return jsonb_build_object('wrong', true); end if;
    perform game.tg_pearl_on(v_pid);
    update game.player_quests set step = 8, data = data || '{"informed": []}', updated_at = now()
     where player_id = v_pid and quest_id = 'toogood';
    perform game.log(v_pid, 'Membuka gua rahasia TooGood: kapal perang legenda Black Pearl kini di bawah komandomu!');
    return jsonb_build_object('pearl', true, 'toogood', game.toogood_state(v_pid),
      'ship', game.ship_json(v_pid), 'visual', game.ship_visual(v_pid));
  end if;

  -- 8 -> 9: kabarkan kejahatan Tedsky ke tiap gubernur
  if v_act = 'inform' then
    if v_step <> 8 then raise exception 'Tidak ada kabar yang perlu disampaikan.'; end if;
    if not (v_city = any (game.tg_inform_targets())) then raise exception 'Kabar ini harus disampaikan ke gubernur pulau lain.'; end if;
    v_informed := coalesce(q.data -> 'informed', '[]'::jsonb);
    if v_informed ? v_city then raise exception 'Gubernur di sini sudah mendengar kabarnya.'; end if;
    v_informed := v_informed || to_jsonb(v_city);
    update game.player_quests set data = jsonb_set(data, '{informed}', v_informed),
        step = case when jsonb_array_length(v_informed) >= array_length(game.tg_inform_targets(), 1) then 9 else 8 end,
        updated_at = now()
     where player_id = v_pid and quest_id = 'toogood';
    perform game.log(v_pid, 'Gubernur ' || game.city_name(v_city) || ' kini tahu kejahatan Jendral Tedsky.');
    if jsonb_array_length(v_informed) >= array_length(game.tg_inform_targets(), 1) then
      perform game.log(v_pid, 'Armada lima pulau mengepung IKN. Jendral Tedsky ditangkap!');
      return jsonb_build_object('arrest', true, 'toogood', game.toogood_state(v_pid));
    end if;
    return jsonb_build_object('informed', v_city, 'toogood', game.toogood_state(v_pid));
  end if;

  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_toogoodquest');

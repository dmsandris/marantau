-- =====================================================================
-- 0040 — Pasir · Batch 1: potret harta, pengosongan & pengembalian (Tide v41)
-- Rencana: claude/PLAN-Coding-Saga3-Dark.md (project docs).
--
--   game.pv_snap            potret harta per pemain (TERTUTUP: tidak pernah dibaca endpoint klien)
--   game.pv_ambil(pid)      satu transaksi: potret -> kosongkan -> Wandering Gull polos, 5.000 gold,
--                           di Sunda Empire, era 'keadilan'.
--   game.pv_pulih(pid)      satu transaksi: potret + semua yang didapat selama Pasir + bunga 10%
--                           (gold & saldo bank potret), era 'kini'.
--
-- Yang DIAMBIL : gold, bank, utang, kapal (baris ships, ship_upgrades, ship_look, artifact terpasang),
--                palka (inventory: barang, item, peta, artifact), gudang semua kota, buku (+ stat dari buku),
--                misi aktif (muatan terkunci dikembalikan ke potret, misi dibatalkan tanpa denda),
--                order Bursa terbuka (barang ditarik ke potret), rupa Kedai yang TERPASANG,
--                skor Pacu Dagang pekan berjalan.
-- Yang TETAP   : Keping Rantau, rupa Kedai yang dimiliki (Lemari), jasa Kedai, Pesanan Harian, Standing,
--                Tanda Jasa (players.meta; disembunyikan klien di batch berikutnya), Buku Ikan, nama/rupa kapten.
-- Peta         : TIDAK disimpan di potret. Selama era bukan 'kini', city_open/player_unlocks hanya
--                membuka pulau awal + pulau yang dibuka Pasir (pasir_state.data.buka). Kembali ke 'kini'
--                = peta lama otomatis kembali (dihitung dari langkah quest lama).
-- Selama era bukan 'kini': tidak ikut Pacu Dagang (skor tidak dicatat), tidak bisa masuk Serbuan Bersama.
--
-- ⚠️ city_open, player_unlocks, dt_join_block, hr_hook di sini adalah SALINAN versi terakhir (0030/0035)
--    + penjaga Pasir. Bila salah satunya diubah di migrasi lain, ubah juga di sini.
-- Aman diulang.
-- =====================================================================

create table if not exists game.pv_snap (
  player_id   uuid primary key references game.players(player_id) on update cascade on delete cascade,
  taken_at    timestamptz not null default now(),
  data        jsonb not null,
  restored_at timestamptz,
  result      jsonb
);
alter table game.pv_snap enable row level security;

-- Era cepat: pemain tanpa baris pasir_state langsung 'kini' (tanpa memeriksa gerbang)
create or replace function game.pasir_era(p_pid uuid) returns text
language plpgsql stable as $$
declare v text;
begin
  select era into v from game.pasir_state where player_id = p_pid;
  if v is null or v = 'kini' then return 'kini'; end if;
  if not game.pasir_aktif(p_pid) then return 'kini'; end if;
  return v;
exception when others then return 'kini';
end $$;

-- Pulau yang dibuka khusus oleh Pasir (dipakai selama era bukan 'kini')
create or replace function game.pasir_buka(p_pid uuid) returns jsonb
language sql stable as $$
  select coalesce((select case when jsonb_typeof(data -> 'buka') = 'array' then data -> 'buka' end
    from game.pasir_state where player_id = p_pid), '[]'::jsonb)
$$;

-- ---------------------------------------------------------------------
-- Peta per era (salinan 0030 + penjaga Pasir)
-- ---------------------------------------------------------------------
create or replace function game.city_open(p_pid uuid, p_city text) returns boolean
language plpgsql stable as $$
begin
  if game.pasir_era(p_pid) <> 'kini' then
    return coalesce((select not hidden from game.cities where city_id = p_city), false)
        or game.pasir_buka(p_pid) ? p_city;
  end if;
  return coalesce((select not hidden from game.cities where city_id = p_city), false)
      or (p_city = 'paradiso' and game.gala_step(p_pid) >= 6)
      or (p_city = 'marie_regal' and game.ww_step(p_pid) >= 1)
      or (p_city = 'titik_buta' and game.fish_is_night() and (game.bx_step(p_pid) = 4 or game.ts_step(p_pid) = 7))
      or (p_city = 'pusaran' and game.bx_step(p_pid) between 7 and 15)
      or (p_city = 'gading_island' and game.cb_step(p_pid) >= 4)
      or (p_city = 'otoland' and game.ts_step(p_pid) >= 3)
      or (p_city = 'empeer_depeer' and game.ts_step(p_pid) >= 4)
      or (p_city = 'freeyork' and game.ts_step(p_pid) >= 5)
      or (p_city = 'karang_garam' and game.lt_step(p_pid) >= 4)
      or (p_city = 'rantai_lama' and game.lt_step(p_pid) >= 5)
      or (p_city = 'sowtour' and game.lt_step(p_pid) >= 6)
      or (p_city = 'teluk_dua_tangan' and game.dt_step(p_pid) >= 5);
end $$;

create or replace function game.player_unlocks(p_pid uuid) returns jsonb
language plpgsql stable as $$
begin
  if game.pasir_era(p_pid) <> 'kini' then
    return coalesce((select jsonb_agg(c.city_id order by c.sort) from game.cities c
      where c.hidden and game.pasir_buka(p_pid) ? c.city_id), '[]'::jsonb);
  end if;
  return (case when game.gala_step(p_pid) >= 6 then '["paradiso"]'::jsonb else '[]'::jsonb end)
      || (case when game.ww_step(p_pid) >= 1 then '["marie_regal"]'::jsonb else '[]'::jsonb end)
      || (case when game.fish_is_night() and (game.bx_step(p_pid) = 4 or game.ts_step(p_pid) = 7) then '["titik_buta"]'::jsonb else '[]'::jsonb end)
      || (case when game.bx_step(p_pid) between 7 and 15 then '["pusaran"]'::jsonb else '[]'::jsonb end)
      || (case when game.cb_step(p_pid) >= 4 then '["gading_island"]'::jsonb else '[]'::jsonb end)
      || (case when game.ts_step(p_pid) >= 3 then '["otoland"]'::jsonb else '[]'::jsonb end)
      || (case when game.ts_step(p_pid) >= 4 then '["empeer_depeer"]'::jsonb else '[]'::jsonb end)
      || (case when game.ts_step(p_pid) >= 5 then '["freeyork"]'::jsonb else '[]'::jsonb end)
      || (case when game.lt_step(p_pid) >= 4 then '["karang_garam"]'::jsonb else '[]'::jsonb end)
      || (case when game.lt_step(p_pid) >= 5 then '["rantai_lama"]'::jsonb else '[]'::jsonb end)
      || (case when game.lt_step(p_pid) >= 6 then '["sowtour"]'::jsonb else '[]'::jsonb end)
      || (case when game.dt_step(p_pid) >= 5 then '["teluk_dua_tangan"]'::jsonb else '[]'::jsonb end);
end $$;

-- ---------------------------------------------------------------------
-- Serbuan Bersama: tertutup selama era bukan 'kini' (salinan 0030 + penjaga)
-- ---------------------------------------------------------------------
create or replace function game.dt_join_block(p_pid uuid) returns text
language plpgsql as $$
declare v_slot text;
begin
  if game.pasir_era(p_pid) <> 'kini' then return 'Tak ada yang mengenal benderamu di teluk ini, Kapten.'; end if;
  if game.lt_step(p_pid) < 10 then return 'Hanya kapten yang sudah menjemput Lima Tangan yang mendengar genderang ini.'; end if;
  if game.dt_step(p_pid) < 1 then return 'Surat Teh Euis belum sampai padamu, Kapten.'; end if;
  if game.dt_step(p_pid) between 3 and 4 then return 'Sayap Patah sudah kandas, Kapten. Teluk Dua Tangan menunggu tanganmu di batu.'; end if;
  if game.in_transit(p_pid) then return 'Merapat dulu di Kota Sowtour, Kapten.'; end if;
  if game.current_city(p_pid) is distinct from 'sowtour' then return 'Papan Armada ada di dermaga Kota Sowtour.'; end if;
  v_slot := game.mp_slot(p_pid);
  if v_slot is not null then
    perform game.mp_duel_refresh(v_slot);
    if game.mp_slot(p_pid) is not null then return 'Selesaikan duelmu dulu.'; end if;
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------------
-- Kejadian: Pesanan Harian + Pacu Dagang + Kisah Lapau (salinan 0035 + penjaga Pacu)
-- ---------------------------------------------------------------------
create or replace function game.hr_hook(p_pid uuid, p_kind text, p_amount numeric, p_ctx jsonb) returns void
language plpgsql as $$
begin
  if p_pid is null then return; end if;
  if game.fitur_on(p_pid, 'HarianOpen') then
    begin
      perform game.hr_event(p_pid, p_kind, p_amount, coalesce(p_ctx, '{}'::jsonb));
    exception when others then raise warning '[harian] % %: %', p_kind, p_pid, sqlerrm;
    end;
  end if;
  if p_kind = 'sell' and game.fitur_on(p_pid, 'PacuOpen') and game.pasir_era(p_pid) = 'kini' then
    begin
      perform game.pd_on_sell(p_pid, p_amount, coalesce(p_ctx, '{}'::jsonb));
    exception when others then raise warning '[pacu] %: %', p_pid, sqlerrm;
    end;
  end if;
  if p_kind = 'arrive' then
    begin
      perform game.ks_on_event(p_pid, p_kind, coalesce(p_ctx, '{}'::jsonb));
    exception when others then raise warning '[kisah] %: %', p_pid, sqlerrm;
    end;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Stat dasar archetype (sama dengan api_createCharacter)
-- ---------------------------------------------------------------------
create or replace function game.pv_base_stats(p_arch text) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'trading', 35 + coalesce((a.bonuses ->> 'Trading')::int, 0), 'negotiation', 35 + coalesce((a.bonuses ->> 'Negotiation')::int, 0),
    'navigation', 35 + coalesce((a.bonuses ->> 'Navigation')::int, 0), 'sailing', 35 + coalesce((a.bonuses ->> 'Sailing')::int, 0),
    'combat', 35 + coalesce((a.bonuses ->> 'Combat')::int, 0), 'luck', 15 + coalesce((a.bonuses ->> 'Luck')::int, 0),
    'knowledge', 5 + coalesce((a.bonuses ->> 'Knowledge')::int, 0))
  from game.archetypes a where a.id = p_arch
$$;

-- Kedua grup upgrade: pilih yang langkahnya lebih tinggi (seri: akumulasi lebih besar)
create or replace function game.pv_merge_upgrades(p_a jsonb, p_b jsonb) returns jsonb
language plpgsql immutable as $$
declare g text; out jsonb := '{}'::jsonb; x jsonb; y jsonb; ks text[];
begin
  p_a := case when jsonb_typeof(p_a) = 'object' then p_a else '{}'::jsonb end;
  p_b := case when jsonb_typeof(p_b) = 'object' then p_b else '{}'::jsonb end;
  select array_agg(distinct k) into ks from (select jsonb_object_keys(p_a) k union select jsonb_object_keys(p_b)) z;
  if ks is null then return '{}'::jsonb; end if;
  foreach g in array ks loop
    x := game.voy_normalize_group(g, p_a -> g); y := game.voy_normalize_group(g, p_b -> g);
    if not (p_b ? g) then out := out || jsonb_build_object(g, p_a -> g);
    elsif not (p_a ? g) then out := out || jsonb_build_object(g, p_b -> g);
    elsif game.voy_abs_step(y) > game.voy_abs_step(x)
       or (game.voy_abs_step(y) = game.voy_abs_step(x) and game.voy_num(y -> 'accumulated') > game.voy_num(x -> 'accumulated')) then
      out := out || jsonb_build_object(g, p_b -> g);
    else out := out || jsonb_build_object(g, p_a -> g);
    end if;
  end loop;
  return out;
end $$;

-- ---------------------------------------------------------------------
-- AMBIL
-- ---------------------------------------------------------------------
create or replace function game.pv_ambil(p_pid uuid, p_city text default 'sunda_empire') returns jsonb
language plpgsql as $$
declare p game.players; v jsonb; v_inv jsonb; v_extra jsonb := '[]'::jsonb; m record; o record; v_ev text; v_base jsonb; x record;
begin
  select * into p from game.players where player_id = p_pid for update;
  if not found or coalesce(p.archetype, '') = '' then raise exception 'Pemain tidak ditemukan.'; end if;
  if exists (select 1 from game.pv_snap where player_id = p_pid and restored_at is null) then
    raise exception 'Potret harta pemain ini masih tersimpan.';
  end if;
  if game.in_transit(p_pid) then raise exception 'Pemain sedang berlayar.'; end if;
  perform game.mp_sail_guard(p_pid);   -- menolak bila sedang duel / di armada Serbuan
  if game.ship_legend(p_pid) is not null then raise exception 'Pemain sedang menakhodai kapal pinjaman.'; end if;

  -- Misi aktif: muatan terkunci masuk potret palka, misi dibatalkan tanpa denda
  for m in select * from game.player_missions where player_id = p_pid and status = 'active' loop
    if coalesce(m.loaded_qty, 0) > 0 then
      v_extra := v_extra || jsonb_build_array(jsonb_build_object('item_id', m.commodity_id, 'qty', m.loaded_qty, 'cost', null));
    end if;
  end loop;
  -- Order Bursa terbuka: barang ditarik ke potret palka
  for o in select * from game.mp_orders where seller_id = p_pid and status = 'open' and qty > 0 loop
    v_extra := v_extra || jsonb_build_array(jsonb_build_object('item_id', o.commodity_id, 'qty', o.qty, 'cost', null));
  end loop;

  select coalesce(jsonb_agg(to_jsonb(i) - 'player_id'), '[]'::jsonb) into v_inv from game.inventory i where i.player_id = p_pid and i.qty > 0;
  select id into v_ev from game.pd_events where sat = game.pd_cur_sat();

  v := jsonb_build_object(
    'gold', p.gold, 'bank', p.bank_balance, 'bankDay', p.bank_last_interest_day,
    'debt', p.debt_balance, 'debtDay', p.debt_last_interest_day,
    'upgrades', p.ship_upgrades, 'look', p.ship_look,
    'ship', (select to_jsonb(s) - 'player_id' from game.ships s where s.player_id = p_pid),
    'equip', coalesce((select jsonb_agg(to_jsonb(e) - 'player_id') from game.ship_equipment e where e.player_id = p_pid), '[]'::jsonb),
    'inv', v_inv || v_extra,
    'wh', coalesce((select jsonb_agg(to_jsonb(w) - 'player_id') from game.warehouse w where w.player_id = p_pid and w.qty > 0), '[]'::jsonb),
    'books', coalesce((select jsonb_agg(to_jsonb(b) - 'player_id') from game.player_books b where b.player_id = p_pid), '[]'::jsonb),
    'stats', (select to_jsonb(c) - 'player_id' from game.character_stats c where c.player_id = p_pid),
    'missions', coalesce((select jsonb_agg(to_jsonb(pm) - 'player_id') from game.player_missions pm where pm.player_id = p_pid and pm.status = 'active'), '[]'::jsonb),
    'orders', coalesce((select jsonb_agg(to_jsonb(mo) - 'seller_id') from game.mp_orders mo where mo.seller_id = p_pid and mo.status = 'open' and mo.qty > 0), '[]'::jsonb),
    'kd', (select l.equipped from game.kd_loadout l where l.player_id = p_pid),
    'pacu', (select to_jsonb(ps) - 'player_id' from game.pd_scores ps where ps.player_id = p_pid and ps.event_id = v_ev),
    'loc', (select to_jsonb(l) - 'player_id' from game.player_location l where l.player_id = p_pid),
    'arch', p.archetype
  );
  insert into game.pv_snap(player_id, data) values (p_pid, v)
  on conflict (player_id) do update set data = excluded.data, taken_at = now(), restored_at = null, result = null;

  -- Kosongkan
  update game.player_missions set status = 'abandoned', loaded_qty = 0 where player_id = p_pid and status = 'active';
  update game.mp_orders set status = 'cancelled', qty = 0 where seller_id = p_pid and status = 'open';
  delete from game.inventory where player_id = p_pid;
  delete from game.warehouse where player_id = p_pid;
  delete from game.player_books where player_id = p_pid;
  delete from game.ship_equipment where player_id = p_pid;
  if v_ev is not null then delete from game.pd_scores where player_id = p_pid and event_id = v_ev; end if;
  update game.kd_loadout set equipped = '{}'::jsonb where player_id = p_pid;
  delete from game.ships where player_id = p_pid;
  insert into game.ships(player_id) values (p_pid);
  v_base := game.pv_base_stats(p.archetype);
  update game.character_stats set trading = (v_base ->> 'trading')::int, negotiation = (v_base ->> 'negotiation')::int,
    navigation = (v_base ->> 'navigation')::int, sailing = (v_base ->> 'sailing')::int, combat = (v_base ->> 'combat')::int,
    luck = (v_base ->> 'luck')::int, knowledge = (v_base ->> 'knowledge')::int
   where player_id = p_pid;
  update game.players set gold = 5000, bank_balance = 0, bank_last_interest_day = null, debt_balance = 0, debt_last_interest_day = null,
    ship_upgrades = '{}'::jsonb, ship_look = null
   where player_id = p_pid;
  update game.player_location set city_id = coalesce(p_city, 'sunda_empire'), arrived_game_day = game.game_day(),
    destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null
   where player_id = p_pid;

  perform game.pasir_ensure(p_pid);
  update game.pasir_state set era = 'keadilan', updated_at = now() where player_id = p_pid;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- PULIH
-- ---------------------------------------------------------------------
create or replace function game.pv_pulih(p_pid uuid) returns jsonb
language plpgsql as $$
declare s game.pv_snap; d jsonb; p game.players; v_bonus bigint; e jsonb; it jsonb; v_base jsonb; v_cur game.character_stats;
  v_slot text; k text; v_res jsonb; v_q int;
begin
  select * into s from game.pv_snap where player_id = p_pid for update;
  if not found or s.restored_at is not null then raise exception 'Tidak ada potret harta yang menunggu.'; end if;
  if game.in_transit(p_pid) then raise exception 'Pemain sedang berlayar.'; end if;
  select * into p from game.players where player_id = p_pid for update;
  d := s.data;

  -- Gold, bank, utang (+ bunga 10% dari gold & saldo bank potret)
  v_bonus := floor((coalesce((d ->> 'gold')::numeric, 0) + coalesce((d ->> 'bank')::numeric, 0)) * 0.10)::bigint;
  update game.players set
    gold = gold + coalesce((d ->> 'gold')::bigint, 0) + v_bonus,
    bank_balance = bank_balance + coalesce((d ->> 'bank')::bigint, 0),
    bank_last_interest_day = coalesce(bank_last_interest_day, (d ->> 'bankDay')::int),
    debt_balance = debt_balance + coalesce((d ->> 'debt')::bigint, 0),
    debt_last_interest_day = coalesce(debt_last_interest_day, (d ->> 'debtDay')::int),
    ship_upgrades = game.pv_merge_upgrades(d -> 'upgrades', ship_upgrades),
    ship_look = coalesce(d -> 'look', ship_look)
   where player_id = p_pid;

  -- Kapal: baris kapal asli kembali (nama, kondisi, statistik dasar)
  if jsonb_typeof(d -> 'ship') = 'object' then
    delete from game.ships where player_id = p_pid;
    insert into game.ships select * from jsonb_populate_record(null::game.ships, (d -> 'ship') || jsonb_build_object('player_id', p_pid));
  end if;

  -- Artifact terpasang: potret menang; artifact selama Pasir yang bentrok slot masuk palka
  for e in select * from jsonb_array_elements(coalesce(d -> 'equip', '[]'::jsonb)) loop
    v_slot := e ->> 'slot_type';
    select item_id into k from game.ship_equipment where player_id = p_pid and slot_type = v_slot;
    if k is not null and k <> coalesce(e ->> 'item_id', '') and k <> '' then
      perform game.item_adjust(p_pid, k, 1);
    end if;
    insert into game.ship_equipment(player_id, slot_type, item_id) values (p_pid, v_slot, e ->> 'item_id')
    on conflict (player_id, slot_type) do update set item_id = excluded.item_id;
  end loop;

  -- Palka & gudang: dijumlahkan (modal ikut dijumlahkan; tidak diketahui = tetap tidak diketahui)
  for it in select * from jsonb_array_elements(coalesce(d -> 'inv', '[]'::jsonb)) loop
    v_q := coalesce((it ->> 'qty')::int, 0);
    continue when v_q <= 0;
    insert into game.inventory(player_id, item_id, qty, cost, src_city)
      values (p_pid, it ->> 'item_id', v_q, (it ->> 'cost')::numeric, it ->> 'src_city')
    on conflict (player_id, item_id) do update set qty = game.inventory.qty + excluded.qty,
      cost = case when game.inventory.cost is null or excluded.cost is null then null else game.inventory.cost + excluded.cost end;
  end loop;
  for it in select * from jsonb_array_elements(coalesce(d -> 'wh', '[]'::jsonb)) loop
    v_q := coalesce((it ->> 'qty')::int, 0);
    continue when v_q <= 0;
    insert into game.warehouse(player_id, city_id, commodity_id, qty, cost)
      values (p_pid, it ->> 'city_id', it ->> 'commodity_id', v_q, (it ->> 'cost')::numeric)
    on conflict (player_id, city_id, commodity_id) do update set qty = game.warehouse.qty + excluded.qty,
      cost = case when game.warehouse.cost is null or excluded.cost is null then null else game.warehouse.cost + excluded.cost end;
  end loop;

  -- Buku: gabungan
  insert into game.player_books(player_id, book_id, date_acquired)
    select p_pid, b ->> 'book_id', (b ->> 'date_acquired')::int from jsonb_array_elements(coalesce(d -> 'books', '[]'::jsonb)) b
  on conflict (player_id, book_id) do nothing;

  -- Stat: potret + (stat sekarang - stat dasar) = semua kenaikan selama Pasir ikut
  v_base := game.pv_base_stats(coalesce(d ->> 'arch', p.archetype));
  select * into v_cur from game.character_stats where player_id = p_pid;
  if jsonb_typeof(d -> 'stats') = 'object' and v_cur.player_id is not null then
    update game.character_stats set
      trading = (d -> 'stats' ->> 'trading')::int + greatest(0, v_cur.trading - (v_base ->> 'trading')::int),
      negotiation = (d -> 'stats' ->> 'negotiation')::int + greatest(0, v_cur.negotiation - (v_base ->> 'negotiation')::int),
      navigation = (d -> 'stats' ->> 'navigation')::int + greatest(0, v_cur.navigation - (v_base ->> 'navigation')::int),
      sailing = (d -> 'stats' ->> 'sailing')::int + greatest(0, v_cur.sailing - (v_base ->> 'sailing')::int),
      combat = (d -> 'stats' ->> 'combat')::int + greatest(0, v_cur.combat - (v_base ->> 'combat')::int),
      luck = (d -> 'stats' ->> 'luck')::int + greatest(0, v_cur.luck - (v_base ->> 'luck')::int),
      knowledge = (d -> 'stats' ->> 'knowledge')::int + greatest(0, v_cur.knowledge - (v_base ->> 'knowledge')::int)
     where player_id = p_pid;
  end if;

  -- Rupa Kedai yang dulu terpasang (hanya yang masih dimiliki)
  if jsonb_typeof(d -> 'kd') = 'object' then
    insert into game.kd_loadout(player_id, equipped) values (p_pid, '{}'::jsonb) on conflict (player_id) do nothing;
    update game.kd_loadout set equipped = coalesce((select jsonb_object_agg(x.key, x.value) from jsonb_each(d -> 'kd') x
        where exists (select 1 from game.kd_owned o where o.player_id = p_pid and o.item_id = x.value #>> '{}')), '{}'::jsonb)
     where player_id = p_pid;
  end if;

  update game.pasir_state set era = 'kini', updated_at = now() where player_id = p_pid;
  v_res := jsonb_build_object('bonus', v_bonus, 'gold', (select gold from game.players where player_id = p_pid));
  update game.pv_snap set restored_at = now(), result = v_res where player_id = p_pid;
  return v_res;
end $$;

-- ---------------------------------------------------------------------
-- Alat GM: tambah 'ambil' & 'pulih'; 'reset' ditolak selama potret belum dikembalikan
-- ---------------------------------------------------------------------
create or replace function game.pasir_admin(p_pid uuid, p_aksi text, p_arg text default null, p_arg2 text default null) returns jsonb
language plpgsql as $$
declare v_act text := lower(coalesce(p_aksi, 'lihat')); v_n int; r game.pasir_state; v_extra jsonb := '{}'::jsonb;
begin
  if p_pid is null then raise exception 'Pemain tidak ditemukan.'; end if;
  if v_act = 'era' then
    if not (lower(coalesce(p_arg, '')) = any (game.pasir_eras())) then
      raise exception 'Era harus salah satu: %', array_to_string(game.pasir_eras(), ', ');
    end if;
    perform game.pasir_ensure(p_pid);
    update game.pasir_state set era = lower(p_arg), updated_at = now() where player_id = p_pid;
  elsif v_act in ('retak', 'kaca') then
    v_n := nullif(trim(coalesce(p_arg, '')), '')::int;
    if v_n is null then raise exception 'Angka tidak valid.'; end if;
    perform game.pasir_ensure(p_pid);
    if v_act = 'retak' then
      update game.pasir_state set retak = least(100, greatest(0, v_n)), updated_at = now() where player_id = p_pid;
    else
      update game.pasir_state set kaca = least(game.cfg_num('PasirKaca', 7)::int, greatest(0, v_n)), updated_at = now() where player_id = p_pid;
    end if;
  elsif v_act = 'langkah' then
    if coalesce(p_arg, '') !~ '^ps1[0-4]$' then raise exception 'Quest harus ps10..ps14.'; end if;
    v_n := nullif(trim(coalesce(p_arg2, '')), '')::int;
    if v_n is null or v_n < 0 then raise exception 'Langkah tidak valid.'; end if;
    perform game.pasir_ensure(p_pid);
    if v_n = 0 then delete from game.player_quests where player_id = p_pid and quest_id = p_arg;
    else perform game.ps_set(p_pid, p_arg, v_n); end if;
  elsif v_act = 'ambil' then
    v_extra := game.pv_ambil(p_pid);
  elsif v_act = 'pulih' then
    v_extra := game.pv_pulih(p_pid);
  elsif v_act = 'reset' then
    if exists (select 1 from game.pv_snap where player_id = p_pid and restored_at is null) then
      raise exception 'Harta pemain ini masih di potret. Jalankan pulih dulu sebelum reset.';
    end if;
    delete from game.player_quests where player_id = p_pid and quest_id in ('ps10', 'ps11', 'ps12', 'ps13', 'ps14');
    delete from game.pasir_state where player_id = p_pid;
    delete from game.pv_snap where player_id = p_pid;
  elsif v_act <> 'lihat' then
    raise exception 'Aksi GM tidak dikenal.';
  end if;
  select * into r from game.pasir_state where player_id = p_pid;
  return jsonb_build_object('row', case when r.player_id is null then null else to_jsonb(r) - 'player_id' end,
    'quests', coalesce((select jsonb_object_agg(quest_id, jsonb_build_object('step', step, 'data', data, 'done', done_at is not null))
      from game.player_quests where player_id = p_pid and quest_id in ('ps10', 'ps11', 'ps12', 'ps13', 'ps14')), '{}'::jsonb),
    'potret', (select case when ps.player_id is null then null else jsonb_build_object('taken', ps.taken_at, 'restored', ps.restored_at,
      'gold', ps.data -> 'gold', 'bank', ps.data -> 'bank', 'result', ps.result) end from game.pv_snap ps where ps.player_id = p_pid),
    'hasil', v_extra);
end $$;

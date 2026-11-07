-- =====================================================================
-- Tide v54 · Bank di Darat
-- Bank (setor/tarik) dan Moneylender (pinjam/bayar) hanya melayani saat kapal merapat.
-- Sebelumnya keempat API ini tidak memeriksa pelayaran, sehingga gold bisa disetor
-- di tengah laut, bahkan setelah bajak laut / Tony and Gank terlihat (lihat
-- claude/AUDIT-Pemain-forward-alokasi-2026-11-07.md).
-- Isi fungsi sama dengan 0002_economy.sql, ditambah game.bank_land_guard().
-- =====================================================================

create or replace function game.bank_land_guard(p_pid uuid) returns void
language plpgsql as $$
declare v_enc boolean;
begin
  select l.pending_encounter is not null and jsonb_typeof(l.pending_encounter) = 'object' into v_enc
    from game.player_location l where l.player_id = p_pid;
  if game.in_transit(p_pid) or coalesce(v_enc, false) then
    raise exception 'PelicanSystem sedang offline, Kapten. Bank hanya melayani saat kapal merapat.';
  end if;
end $$;

create or replace function public.api_bankDeposit(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_amt bigint := game.arg_int(a, 0); v_me game.players; st jsonb;
begin
  if v_amt is null or v_amt <= 0 then raise exception 'Jumlah setor tidak valid.'; end if;
  v_me := game.me(true);
  perform game.bank_land_guard(v_me.player_id);
  perform game.spot_service_guard(v_me.player_id);
  st := game.bank_state(v_me.player_id);
  if v_me.gold < v_amt then raise exception 'Gold tidak cukup.'; end if;
  update game.players set bank_balance = (st ->> 'bankBalance')::bigint + v_amt, gold = gold - v_amt
   where player_id = v_me.player_id;
  perform game.log(v_me.player_id, 'Deposited ' || v_amt || ' gold at the Bank.');
  return game.bank_state(v_me.player_id) || jsonb_build_object('newGold', v_me.gold - v_amt);
end $$;
select game.expose('api_bankdeposit');

create or replace function public.api_bankWithdraw(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_amt bigint := game.arg_int(a, 0); v_me game.players; st jsonb;
begin
  if v_amt is null or v_amt <= 0 then raise exception 'Jumlah tarik tidak valid.'; end if;
  v_me := game.me(true);
  perform game.bank_land_guard(v_me.player_id);
  perform game.spot_service_guard(v_me.player_id);
  st := game.bank_state(v_me.player_id);
  if (st ->> 'bankBalance')::bigint < v_amt then raise exception 'Saldo Bank tidak cukup.'; end if;
  update game.players set bank_balance = (st ->> 'bankBalance')::bigint - v_amt, gold = gold + v_amt
   where player_id = v_me.player_id;
  perform game.log(v_me.player_id, 'Withdrew ' || v_amt || ' gold from the Bank.');
  return game.bank_state(v_me.player_id) || jsonb_build_object('newGold', v_me.gold + v_amt);
end $$;
select game.expose('api_bankwithdraw');

create or replace function public.api_bankBorrow(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_amt bigint := game.arg_int(a, 0); v_me game.players; st jsonb;
begin
  if v_amt is null or v_amt <= 0 then raise exception 'Jumlah pinjam tidak valid.'; end if;
  v_me := game.me(true);
  perform game.bank_land_guard(v_me.player_id);
  perform game.spot_service_guard(v_me.player_id);
  st := game.bank_state(v_me.player_id);
  if (st ->> 'debtBalance')::numeric + v_amt > (st ->> 'maxDebt')::numeric then
    raise exception 'Melebihi batas pinjaman Moneylender (maksimum utang % gold).', st ->> 'maxDebt';
  end if;
  update game.players set debt_balance = (st ->> 'debtBalance')::bigint + v_amt, gold = gold + v_amt
   where player_id = v_me.player_id;
  perform game.log(v_me.player_id, 'Borrowed ' || v_amt || ' gold from the Moneylender.');
  return game.bank_state(v_me.player_id) || jsonb_build_object('newGold', v_me.gold + v_amt);
end $$;
select game.expose('api_bankborrow');

create or replace function public.api_bankRepay(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_amt bigint := game.arg_int(a, 0); v_me game.players; st jsonb; pay bigint;
begin
  if v_amt is null or v_amt <= 0 then raise exception 'Jumlah bayar tidak valid.'; end if;
  v_me := game.me(true);
  perform game.bank_land_guard(v_me.player_id);
  perform game.spot_service_guard(v_me.player_id);
  st := game.bank_state(v_me.player_id);
  pay := least(v_amt, (st ->> 'debtBalance')::bigint, v_me.gold);
  if pay <= 0 then raise exception 'Tidak ada yang bisa dibayar (cek gold atau utangmu).'; end if;
  update game.players set debt_balance = (st ->> 'debtBalance')::bigint - pay, gold = gold - pay
   where player_id = v_me.player_id;
  perform game.log(v_me.player_id, 'Repaid ' || pay || ' gold to the Moneylender.');
  return game.bank_state(v_me.player_id) || jsonb_build_object('newGold', v_me.gold - pay);
end $$;
select game.expose('api_bankrepay');

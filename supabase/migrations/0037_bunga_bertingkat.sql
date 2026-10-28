-- =====================================================================
-- 0037 — Bunga Bertingkat (Tide v39)
-- Bunga bank dihitung per bagian saldo (seperti tarif pajak):
--   0 – 5 jt    : 0,5% / hari game
--   5 – 10 jt   : 0,3%
--   10 – 20 jt  : 0,2%
--   di atas 20 jt : 0%
-- Saldo lama tidak dipotong. Bunga utang tidak berubah.
-- Config: BankTier = "batas:persen,batas:persen,...,inf:persen" (batas atas tiap tingkat).
-- RAHASIA: pemain hanya melihat "Bunga 0% s/d 0,5%"; rincian tingkat tidak dikirim ke klien.
-- Menimpa game.bank_state dari 0002 (fungsi lain tetap sama).
-- =====================================================================

insert into game.config(key, value) values
  ('BankTier', '5000000:0.5,10000000:0.3,20000000:0.2,inf:0')
on conflict (key) do nothing;

-- Tingkat bunga sebagai array jsonb [{upTo: number|null, rate: numeric}], urut naik.
create or replace function game.bank_tiers() returns jsonb
language plpgsql stable as $$
declare raw text := coalesce(nullif(trim(game.cfg('BankTier')), ''), '');
  part text; lim text; rt text; out jsonb := '[]'::jsonb;
begin
  if raw = '' then
    return jsonb_build_array(jsonb_build_object('upTo', null, 'rate', game.cfg_num('BankInterestRatePercent', 0.5)));
  end if;
  foreach part in array string_to_array(raw, ',') loop
    part := trim(part);
    if part = '' or position(':' in part) = 0 then continue; end if;
    lim := trim(split_part(part, ':', 1));
    rt := trim(split_part(part, ':', 2));
    begin
      out := out || jsonb_build_array(jsonb_build_object(
        'upTo', case when lower(lim) in ('inf', '') then null else lim::numeric end,
        'rate', rt::numeric));
    exception when others then continue;
    end;
  end loop;
  if jsonb_array_length(out) = 0 then
    return jsonb_build_array(jsonb_build_object('upTo', null, 'rate', game.cfg_num('BankInterestRatePercent', 0.5)));
  end if;
  return out;
end $$;

-- Bunga satu hari game untuk saldo tertentu (per bagian saldo).
create or replace function game.bank_interest_day(p_bal double precision, p_tiers jsonb) returns double precision
language plpgsql immutable as $$
declare t jsonb; lo double precision := 0; hi double precision; part double precision; total double precision := 0;
begin
  if p_bal is null or p_bal <= 0 then return 0; end if;
  for t in select * from jsonb_array_elements(p_tiers) loop
    hi := case when t ->> 'upTo' is null then 'Infinity'::double precision else (t ->> 'upTo')::double precision end;
    if p_bal > lo then
      part := least(p_bal, hi) - lo;
      total := total + part * (t ->> 'rate')::double precision / 100;
    end if;
    lo := hi;
    exit when p_bal <= hi;
  end loop;
  return total;
end $$;

-- Bunga maksimal per hari game (bila tingkat teratas 0%), null bila tak terbatas.
create or replace function game.bank_interest_cap(p_tiers jsonb) returns double precision
language plpgsql immutable as $$
declare last jsonb := p_tiers -> (jsonb_array_length(p_tiers) - 1); top double precision := 0; t jsonb;
begin
  if (last ->> 'upTo') is not null or coalesce((last ->> 'rate')::numeric, 0) > 0 then return null; end if;
  for t in select * from jsonb_array_elements(p_tiers) loop
    if t ->> 'upTo' is not null then top := greatest(top, (t ->> 'upTo')::double precision); end if;
  end loop;
  return game.bank_interest_day(top, p_tiers);
end $$;

create or replace function game.bank_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare p game.players; day int; debt_rate numeric;
  bank_last int; debt_last int; bank_days int; debt_days int;
  bank_bal double precision; debt_bal double precision;
  tiers jsonb := game.bank_tiers(); cap double precision := game.bank_interest_cap(game.bank_tiers());
  top double precision := 0; t jsonb; i int; step double precision;
begin
  select * into p from game.players where player_id = p_pid;
  if not found then raise exception 'Player % tidak ditemukan.', p_pid; end if;
  day := game.game_day();
  debt_rate := game.cfg_num('DebtInterestRatePercent', 2);

  bank_bal := coalesce(p.bank_balance, 0);
  debt_bal := coalesce(p.debt_balance, 0);
  bank_last := coalesce(p.bank_last_interest_day, day);
  debt_last := coalesce(p.debt_last_interest_day, day);
  bank_days := greatest(0, day - bank_last);
  debt_days := greatest(0, day - debt_last);

  for t in select * from jsonb_array_elements(tiers) loop
    if t ->> 'upTo' is not null then top := greatest(top, (t ->> 'upTo')::double precision); end if;
  end loop;

  -- Bunga bertingkat, majemuk per hari game. Begitu saldo melewati tingkat
  -- teratas yang berbunga, bunga harian tetap (cap) -> sisa hari dihitung lurus.
  if bank_days > 0 and bank_bal > 0 then
    i := 0;
    while i < bank_days loop
      if cap is not null and bank_bal >= top then
        bank_bal := bank_bal + cap * (bank_days - i);
        exit;
      end if;
      step := game.bank_interest_day(bank_bal, tiers);
      exit when step <= 0;
      bank_bal := bank_bal + step;
      i := i + 1;
      exit when i >= 5000;  -- pengaman untuk akun yang tidur sangat lama
    end loop;
    bank_bal := game.eco_round(bank_bal);
  end if;
  if debt_days > 0 and debt_bal > 0 then
    debt_bal := game.eco_round(debt_bal * power(1 + debt_rate::double precision / 100, debt_days));
  end if;

  if bank_days > 0 or debt_days > 0 or p.bank_last_interest_day is null or p.debt_last_interest_day is null then
    update game.players set
      bank_balance = game.eco_round(bank_bal),
      debt_balance = game.eco_round(debt_bal),
      bank_last_interest_day = case when bank_days > 0 or bank_last_interest_day is null then day else bank_last_interest_day end,
      debt_last_interest_day = case when debt_days > 0 or debt_last_interest_day is null then day else debt_last_interest_day end
    where player_id = p_pid;
  end if;

  return jsonb_build_object(
    'bankBalance', game.eco_round(bank_bal),
    'debtBalance', game.eco_round(debt_bal),
    -- Rincian tingkat sengaja tidak dikirim ke klien; pemain hanya melihat rentang bunga.
    'bankRatePercent', trim_scale((select max((t2 ->> 'rate')::numeric) from jsonb_array_elements(tiers) t2)),
    'bankRateMinPercent', trim_scale((select min((t2 ->> 'rate')::numeric) from jsonb_array_elements(tiers) t2)),
    'debtRatePercent', trim_scale(debt_rate),
    'maxDebt', trim_scale(game.cfg_num('MaxDebtAmount', 100000)),
    'migrated', true);
end $$;

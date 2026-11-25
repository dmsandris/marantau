-- =====================================================================
-- 0104 Kasino Mutiara (Paradiso) · Tide v84
-- Konsep: claude/KONSEP-PRD-Kasino-Mutiara (dari pemilik) + claude/AUDIT-Kasino-Mutiara-2026-11-24.md
--
-- Meja (semua melawan bandar, tanpa PvP):
--   dadu      Duel Dadu Bandar  · 2 dadu vs 2 dadu, menang 1:1, seri uang kembali
--   roulette  Roulette Mutiara  · 36 angka + kantong mutiara (0, tidak bisa dipasang)
--   blackjack Blackjack         · 6 dek dikocok ulang tiap ronde, bandar stand soft 17, Blackjack 3:2,
--                                 hit / stand / double (2 kartu pertama), tanpa split
--   slot      Slot Mutiara      · 3 gulungan, garis tengah, tabel bayar tetap (maks 50×)
--
-- Peluang: satu angka Edge per meja (config KasinoEdge<Meja>, -0.10..+0.10), diatur GM lewat api_gmKasino.
--   Edge = rata-rata kerugian kapten per 1 gold taruhan. Tabel bayar yang dilihat pemain TIDAK berubah;
--   Edge diterapkan lewat peluang:
--     dadu      peluang menang di ronde non-seri = (1 - e/(1-t))/2, t = 146/1296 (peluang seri 2d6 vs 2d6)
--     roulette  e >= 0: kantong 0 muncul dengan peluang e. e < 0: dengan peluang λ bola diarahkan ke
--               kantong yang paling menguntungkan taruhan kapten (λ = -e / EV kantong terbaik)
--     slot      RTP dasar gulungan R0 ≈ 1,1018; dengan peluang 1-(1-e)/R0 hasil diganti kombinasi kalah
--     blackjack "dorongan" kartu k dari tabel kalibrasi tools/sim-kasino.js (basic strategy)
--   Edge TIDAK pernah dikirim ke pemain.
--
-- Pengaman: hanya di Paradiso & saat merapat, ditolak bila ada utang Moneylender, era Pasir bukan 'kini',
--   taruhan 100..100.000 (KasinoMinBet/KasinoMaxBet) dari gold di tangan, jeda antar ronde KasinoJedaMs,
--   satu ronde Blackjack aktif (auto-stand 120 dtk / saat berlayar), nonce anti kirim ganda,
--   batas MENANG bersih KasinoMenangHarian (2,5 jt) per HARI NYATA (00:00 WIB, game.hr_today()).
--   Bayaran dipotong ke sisa kuota; sesudah penuh meja tutup diam-diam sampai besok. Tanpa batas kalah.
--   Angka kuota tidak dikirim ke pemain.
--
-- Money trace: game.kasino_round (saldo sebelum/sesudah, taruhan, bayaran, Edge). Panel Ops membaca
--   tabel ini langsung (aliran.js, penjaga.js, tab Kasino) — tidak menulis ke player_log per ronde.
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('KasinoOpen', '0'),
  ('KasinoOpenDadu', '1'), ('KasinoOpenRoulette', '1'), ('KasinoOpenBlackjack', '1'), ('KasinoOpenSlot', '1'),
  ('KasinoEdgeDadu', '0'), ('KasinoEdgeRoulette', '0'), ('KasinoEdgeBlackjack', '0'), ('KasinoEdgeSlot', '0'),
  ('KasinoMinBet', '100'), ('KasinoMaxBet', '100000'), ('KasinoMenangHarian', '2500000'),
  ('KasinoJedaMs', '700'), ('KasinoBjDetik', '120'), ('KasinoAlarmMinRonde', '1000')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Tabel
-- ---------------------------------------------------------------------
create table if not exists game.kasino_round (
  id            bigserial primary key,
  player_id     uuid not null references game.players(player_id) on update cascade on delete cascade,
  ks_day        date not null,                       -- hari nyata WIB (acuan batas menang harian)
  game_day      int not null,                        -- hari game saat ronde dimulai (info)
  game_type     text not null check (game_type in ('dadu', 'roulette', 'blackjack', 'slot')),
  gold_before   bigint not null,                     -- gold di tangan sebelum taruhan dipotong
  bet_amount    bigint not null check (bet_amount > 0),
  payout_amount bigint not null default 0 check (payout_amount >= 0),
  net_delta     bigint not null default 0,           -- payout - bet
  gold_after    bigint,                              -- gold di tangan sesudah ronde selesai
  edge_applied  numeric(5,4) not null,
  client_nonce  text not null,
  status        text not null default 'settled' check (status in ('active', 'settled', 'expired')),
  capped        boolean not null default false,      -- bayaran dipotong ke sisa kuota harian
  state_json    jsonb not null default '{}'::jsonb,  -- detail hasil (dadu/angka/kartu/simbol); sepatu BJ saat aktif
  created_at    timestamptz not null default now(),
  settled_at    timestamptz
);
create unique index if not exists kasino_round_nonce_uq on game.kasino_round (player_id, client_nonce);
create index if not exists kasino_round_day_idx on game.kasino_round (player_id, ks_day);
create index if not exists kasino_round_pid_idx on game.kasino_round (player_id, id desc);
create index if not exists kasino_round_type_idx on game.kasino_round (game_type, created_at);
create unique index if not exists kasino_round_active_uq on game.kasino_round (player_id) where status = 'active';
alter table game.kasino_round enable row level security;

-- Ringkasan harian per kapten: cek kuota & jeda O(1), tidak menjumlah ulang ronde.
create table if not exists game.kasino_daily (
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  ks_day    date not null,
  net       bigint not null default 0,     -- menang bersih ronde yang sudah selesai
  rounds    int not null default 0,
  turnover  bigint not null default 0,
  last_at   timestamptz,                   -- ronde terakhir dimulai
  primary key (player_id, ks_day)
);
alter table game.kasino_daily enable row level security;
create index if not exists kasino_daily_day_idx on game.kasino_daily (ks_day, turnover desc);

create table if not exists game.kasino_edge_audit (
  id         bigserial primary key,
  gm_id      uuid not null references game.players(player_id) on update cascade on delete cascade,
  game_type  text not null,
  old_edge   numeric(5,4) not null,
  new_edge   numeric(5,4) not null,
  note       text not null,
  created_at timestamptz not null default now()
);
alter table game.kasino_edge_audit enable row level security;

-- ---------------------------------------------------------------------
-- Bantuan
-- ---------------------------------------------------------------------
create or replace function game.ks_games() returns text[]
language sql immutable as $$ select array['dadu', 'roulette', 'blackjack', 'slot'] $$;

create or replace function game.ks_key(p_game text) returns text
language sql immutable as $$ select case p_game when 'dadu' then 'Dadu' when 'roulette' then 'Roulette'
  when 'blackjack' then 'Blackjack' when 'slot' then 'Slot' end $$;

create or replace function game.ks_edge(p_game text) returns numeric
language sql stable as $$
  select greatest(-0.10, least(0.10, round(game.cfg_num('KasinoEdge' || game.ks_key(p_game), 0), 4)))
$$;

create or replace function game.ks_day() returns date
language sql stable as $$ select game.hr_today() $$;

create or replace function game.ks_cap() returns bigint
language sql stable as $$ select greatest(0, game.cfg_num('KasinoMenangHarian', 2500000))::bigint $$;

create or replace function game.ks_net_today(p_pid uuid) returns bigint
language sql stable as $$
  select coalesce((select net from game.kasino_daily where player_id = p_pid and ks_day = game.ks_day()), 0)
$$;
-- Catat ronde ke ringkasan harian (p_start: ronde dimulai; p_net/p_bet: ronde selesai)
create or replace function game.ks_daily_add(p_pid uuid, p_day date, p_start boolean, p_net bigint, p_bet bigint) returns void
language sql as $$
  insert into game.kasino_daily as k (player_id, ks_day, net, rounds, turnover, last_at)
  values (p_pid, p_day, coalesce(p_net, 0), case when p_net is null then 0 else 1 end, coalesce(p_bet, 0),
          case when p_start then now() end)
  on conflict (player_id, ks_day) do update set net = k.net + coalesce(p_net, 0),
    rounds = k.rounds + case when p_net is null then 0 else 1 end, turnover = k.turnover + coalesce(p_bet, 0),
    last_at = case when p_start then now() else k.last_at end
$$;

create or replace function game.ks_table_on(p_game text) returns boolean
language sql stable as $$ select lower(coalesce(game.cfg('KasinoOpen' || game.ks_key(p_game)), '1')) in ('1', 'true', 'on', 'ya') $$;

-- Alasan kasino tidak melayani (null = melayani). Urutan: gerbang, zaman, kota, laut, utang, kuota.
create or replace function game.ks_gate(p_pid uuid) returns text
language plpgsql stable as $$
declare v_enc boolean; v_debt numeric;
begin
  if not game.fitur_on(p_pid, 'KasinoOpen') then return 'tutup'; end if;
  if game.pasir_era(p_pid) <> 'kini' then return 'tutup'; end if;
  if game.current_city(p_pid) is distinct from 'paradiso' then return 'kota'; end if;
  select l.pending_encounter is not null and jsonb_typeof(l.pending_encounter) = 'object' into v_enc
    from game.player_location l where l.player_id = p_pid;
  if game.in_transit(p_pid) or coalesce(v_enc, false) then return 'laut'; end if;
  v_debt := coalesce((game.bank_state(p_pid) ->> 'debtBalance')::numeric, 0);
  if v_debt > 0 then return 'utang'; end if;
  if game.ks_net_today(p_pid) >= game.ks_cap() then return 'penuh'; end if;
  return null;
end $$;

create or replace function game.ks_gate_msg(p_why text) returns text
language sql immutable as $$
  select case p_why
    when 'tutup' then 'Pintu Kasino Mutiara masih tertutup, Kapten.'
    when 'kota'  then 'Kasino Mutiara hanya ada di Paradiso, Kapten.'
    when 'laut'  then 'PelicanSystem sedang offline, Kapten. Kasino hanya melayani saat kapal merapat.'
    when 'utang' then 'Juru buku menutup pintu: lunasi dulu seluruh utang Moneylender-mu, Kapten.'
    when 'penuh' then 'Bandar sudah menutup semua meja untukmu malam ini, Kapten. Kembalilah besok.'
    else 'Kasino tidak melayani saat ini.' end
$$;

-- Untuk getGameState (0010): hanya penanda tombol, tanpa angka apa pun.
create or replace function game.ks_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
begin
  if not game.fitur_on(p_pid, 'KasinoOpen') or game.pasir_era(p_pid) <> 'kini' then return null; end if;
  return jsonb_build_object('on', true);
exception when others then return null;
end $$;

-- Bayaran dipotong supaya menang bersih hari ini tidak melewati kuota.
create or replace function game.ks_clamp(p_pid uuid, p_bet bigint, p_pay bigint) returns bigint
language sql stable as $$
  select least(p_pay, p_bet + greatest(0, game.ks_cap() - game.ks_net_today(p_pid)))
$$;

create or replace function game.ks_ri(p_n int) returns int
language sql volatile as $$ select floor(random() * p_n)::int $$;

-- Validasi bersama awal ronde. Mengembalikan baris pemain (terkunci).
create or replace function game.ks_begin(p_game text, p_bet bigint, p_nonce text) returns game.players
language plpgsql as $$
declare v_me game.players; v_why text; v_last timestamptz;
  v_min bigint := greatest(1, game.cfg_num('KasinoMinBet', 100))::bigint;
  v_max bigint := greatest(1, game.cfg_num('KasinoMaxBet', 100000))::bigint;
begin
  v_me := game.me(true);
  v_why := game.ks_gate(v_me.player_id);
  if v_why is not null then raise exception '%', game.ks_gate_msg(v_why); end if;
  if not game.ks_table_on(p_game) then raise exception 'Meja ini sedang ditutup bandar, Kapten.'; end if;
  if p_nonce is null or length(p_nonce) < 6 or length(p_nonce) > 64 then raise exception 'Permintaan meja tidak valid.'; end if;
  if p_bet is null or p_bet < v_min or p_bet > v_max then
    raise exception 'Taruhan harus antara % dan % gold.', replace(to_char(v_min, 'FM999,999,999'), ',', '.'), replace(to_char(v_max, 'FM999,999,999'), ',', '.');
  end if;
  if v_me.gold < p_bet then raise exception 'Gold di tangan tidak cukup. Simpanan bank tidak bisa dipakai di meja.'; end if;
  if exists (select 1 from game.kasino_round where player_id = v_me.player_id and status = 'active') then
    raise exception 'Selesaikan dulu ronde Blackjack-mu, Kapten.';
  end if;
  select max(last_at) into v_last from game.kasino_daily where player_id = v_me.player_id and ks_day >= game.ks_day() - 1;
  if v_last is not null and v_last > now() - make_interval(secs => game.cfg_num('KasinoJedaMs', 700) / 1000.0) then
    raise exception 'Bandar masih merapikan meja, Kapten. Sebentar.';
  end if;
  return v_me;
end $$;

-- Catat ronde instan (dadu, roulette, slot): potong taruhan, bayar, simpan jejak.
create or replace function game.ks_settle_instant(p_me game.players, p_game text, p_bet bigint, p_pay bigint,
  p_nonce text, p_res jsonb) returns jsonb
language plpgsql as $$
declare v_pay bigint := game.ks_clamp(p_me.player_id, p_bet, p_pay); v_after bigint := p_me.gold - p_bet + v_pay; v_id bigint;
  v_out jsonb;
begin
  update game.players set gold = v_after where player_id = p_me.player_id;
  insert into game.kasino_round(player_id, ks_day, game_day, game_type, gold_before, bet_amount, payout_amount, net_delta,
    gold_after, edge_applied, client_nonce, status, capped, state_json, settled_at)
  values (p_me.player_id, game.ks_day(), game.game_day(), p_game, p_me.gold, p_bet, v_pay, v_pay - p_bet,
    v_after, game.ks_edge(p_game), p_nonce, 'settled', v_pay < p_pay, p_res, now())
  returning id into v_id;
  v_out := jsonb_build_object('id', v_id, 'game', p_game, 'bet', p_bet, 'payout', v_pay, 'net', v_pay - p_bet,
    'capped', v_pay < p_pay, 'result', p_res);
  update game.kasino_round set state_json = state_json || jsonb_build_object('out', v_out) where id = v_id;
  perform game.ks_daily_add(p_me.player_id, game.ks_day(), true, v_pay - p_bet, p_bet);
  return v_out;
end $$;

-- ---------------------------------------------------------------------
-- Duel Dadu Bandar
-- ---------------------------------------------------------------------
create or replace function game.ks_dadu_roll(p_want int) returns jsonb   -- 1 menang, 0 seri, -1 kalah
language plpgsql volatile as $$
declare a int; b int; c int; d int; n int := 0;
begin
  loop
    a := 1 + game.ks_ri(6); b := 1 + game.ks_ri(6); c := 1 + game.ks_ri(6); d := 1 + game.ks_ri(6);
    exit when sign((a + b) - (c + d)) = p_want;
    n := n + 1; exit when n > 400;
  end loop;
  return jsonb_build_object('p', jsonb_build_array(a, b), 'd', jsonb_build_array(c, d));
end $$;

create or replace function game.ks_play_dadu(p_bet bigint, p_nonce text) returns jsonb
language plpgsql as $$
declare v_me game.players := game.ks_begin('dadu', p_bet, p_nonce); e numeric := game.ks_edge('dadu');
  t numeric := 146.0 / 1296; q numeric; u double precision := random(); v_want int; r jsonb; v_pay bigint;
begin
  if u < t then v_want := 0;
  else
    q := (1 - e / (1 - t)) / 2;
    v_want := case when random() < q then 1 else -1 end;
  end if;
  r := game.ks_dadu_roll(v_want);
  v_pay := case v_want when 1 then p_bet * 2 when 0 then p_bet else 0 end;
  r := r || jsonb_build_object('hasil', case v_want when 1 then 'menang' when 0 then 'seri' else 'kalah' end);
  return game.ks_settle_instant(v_me, 'dadu', p_bet, v_pay, p_nonce, r);
end $$;

-- ---------------------------------------------------------------------
-- Roulette Mutiara
-- ---------------------------------------------------------------------
create or replace function game.ks_rl_red(n int) returns boolean
language sql immutable as $$ select n = any (array[1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36]) $$;

-- Bayaran (termasuk modal) satu taruhan bila bola jatuh di kantong p_n.
create or replace function game.ks_rl_pay(p_bet jsonb, p_n int) returns bigint
language plpgsql immutable as $$
declare t text := p_bet ->> 't'; a bigint := (p_bet ->> 'a')::bigint; x int := (p_bet ->> 'n')::int; w boolean;
begin
  if p_n = 0 then return 0; end if;
  w := case t
    when 'red' then game.ks_rl_red(p_n) when 'black' then not game.ks_rl_red(p_n)
    when 'even' then p_n % 2 = 0 when 'odd' then p_n % 2 = 1
    when 'low' then p_n <= 18 when 'high' then p_n >= 19
    when 'd1' then p_n <= 12 when 'd2' then p_n between 13 and 24 when 'd3' then p_n >= 25
    when 'num' then p_n = x else false end;
  if not w then return 0; end if;
  return a * case when t = 'num' then 36 when t in ('d1', 'd2', 'd3') then 3 else 2 end;
end $$;

-- Rapikan & validasi daftar taruhan: [{t, a, n?}], maks 16 taruhan, tiap a >= KasinoMinBet.
create or replace function game.ks_rl_clean(p_bets jsonb) returns jsonb
language plpgsql stable as $$
declare b jsonb; out jsonb := '[]'::jsonb; t text; a bigint; n int;
  v_min bigint := greatest(1, game.cfg_num('KasinoMinBet', 100))::bigint;
begin
  if p_bets is null or jsonb_typeof(p_bets) <> 'array' or jsonb_array_length(p_bets) = 0 then
    raise exception 'Pasang chip di papan dulu, Kapten.';
  end if;
  if jsonb_array_length(p_bets) > 16 then raise exception 'Terlalu banyak taruhan di satu putaran (maks 16).'; end if;
  for b in select * from jsonb_array_elements(p_bets) loop
    if jsonb_typeof(b) <> 'object' then raise exception 'Taruhan tidak valid.'; end if;
    t := lower(coalesce(b ->> 't', ''));
    begin a := floor((b ->> 'a')::numeric)::bigint; exception when others then a := null; end;
    if t not in ('red', 'black', 'even', 'odd', 'low', 'high', 'd1', 'd2', 'd3', 'num') then raise exception 'Jenis taruhan tidak dikenal.'; end if;
    if a is null or a < v_min then raise exception 'Setiap taruhan minimal % gold.', v_min; end if;
    if t = 'num' then
      begin n := (b ->> 'n')::int; exception when others then n := null; end;
      if n is null or n < 1 or n > 36 then raise exception 'Angka tunggal hanya 1 sampai 36. Kantong mutiara milik bandar.'; end if;
      out := out || jsonb_build_array(jsonb_build_object('t', t, 'a', a, 'n', n));
    else
      out := out || jsonb_build_array(jsonb_build_object('t', t, 'a', a));
    end if;
  end loop;
  return out;
end $$;

create or replace function game.ks_rl_total_pay(p_bets jsonb, p_n int) returns bigint
language sql immutable as $$ select coalesce(sum(game.ks_rl_pay(b, p_n)), 0)::bigint from jsonb_array_elements(p_bets) b $$;

create or replace function game.ks_play_roulette(p_bets jsonb, p_nonce text) returns jsonb
language plpgsql as $$
declare v_bets jsonb := game.ks_rl_clean(p_bets); v_tot bigint; v_me game.players; e numeric := game.ks_edge('roulette');
  v_n int; v_best bigint := 0; v_bestn int[]; v_ev numeric; lam numeric; i int; v_p bigint; v_pay bigint;
begin
  select sum((b ->> 'a')::bigint) into v_tot from jsonb_array_elements(v_bets) b;
  v_me := game.ks_begin('roulette', v_tot, p_nonce);
  if e > 0 and random() < e then
    v_n := 0;
  elsif e < 0 then
    for i in 1..36 loop
      v_p := game.ks_rl_total_pay(v_bets, i);
      if v_p > v_best then v_best := v_p; v_bestn := array[i]; elsif v_p = v_best and v_p > 0 then v_bestn := v_bestn || i; end if;
    end loop;
    v_ev := v_best::numeric / v_tot - 1;
    lam := case when v_ev > 0 then least(1, -e / v_ev) else 0 end;
    if lam > 0 and random() < lam then v_n := v_bestn[1 + game.ks_ri(array_length(v_bestn, 1))];
    else v_n := 1 + game.ks_ri(36); end if;
  else
    v_n := 1 + game.ks_ri(36);
  end if;
  v_pay := game.ks_rl_total_pay(v_bets, v_n);
  return game.ks_settle_instant(v_me, 'roulette', v_tot, v_pay, p_nonce, jsonb_build_object('n', v_n,
    'warna', case when v_n = 0 then 'mutiara' when game.ks_rl_red(v_n) then 'merah' else 'hitam' end, 'bets', v_bets));
end $$;

-- ---------------------------------------------------------------------
-- Slot Mutiara
-- Bobot gulungan (sama untuk 3 gulungan): mutiara 2, jangkar 2, kompas 3, bir 7, kerang 7 (dari 21).
-- Bayaran: 3 mutiara 50×, 3 jangkar 30×, 3 kompas 20×, 3 bir 12×, 3 kerang 6×, 2 mutiara 3×, 1 mutiara 1×.
-- ---------------------------------------------------------------------
create or replace function game.ks_slot_sym(u double precision) returns text
language sql immutable as $$
  select case when u < 2/21.0 then 'pearl' when u < 4/21.0 then 'anchor' when u < 7/21.0 then 'compass'
              when u < 14/21.0 then 'tankard' else 'shell' end
$$;
create or replace function game.ks_slot_mult(a text, b text, c text) returns int
language plpgsql immutable as $$
declare np int := (a = 'pearl')::int + (b = 'pearl')::int + (c = 'pearl')::int;
begin
  if a = b and b = c then
    return case a when 'pearl' then 50 when 'anchor' then 30 when 'compass' then 20 when 'tankard' then 12 else 6 end;
  end if;
  return case np when 2 then 3 when 1 then 1 else 0 end;
end $$;
create or replace function game.ks_slot_r0() returns numeric
language sql immutable as $$
  select (8 * 50 + 8 * 30 + 27 * 20 + 343 * 12 + 343 * 6)::numeric / 9261
       + 3 * (2/21.0) ^ 2 * (19/21.0) * 3 + 3 * (2/21.0) * (19/21.0) ^ 2 * 1
$$;

create or replace function game.ks_play_slot(p_bet bigint, p_nonce text) returns jsonb
language plpgsql as $$
declare v_me game.players := game.ks_begin('slot', p_bet, p_nonce); e numeric := game.ks_edge('slot');
  k numeric := greatest(0, 1 - (1 - e) / game.ks_slot_r0()); s text[]; m int; n int := 0; v_force boolean;
begin
  v_force := random() < k;
  loop
    s := array[game.ks_slot_sym(random()), game.ks_slot_sym(random()), game.ks_slot_sym(random())];
    m := game.ks_slot_mult(s[1], s[2], s[3]);
    exit when not v_force or m = 0;
    n := n + 1; exit when n > 200;
  end loop;
  if v_force and m > 0 then s := array['tankard', 'shell', 'compass']; m := 0; end if;
  return game.ks_settle_instant(v_me, 'slot', p_bet, p_bet * m, p_nonce,
    jsonb_build_object('reels', to_jsonb(s), 'mult', m));
end $$;

-- ---------------------------------------------------------------------
-- Blackjack
-- Kartu = 0..51 (suit*13 + rank-1). Sepatu 6 dek dikocok ulang tiap ronde, disimpan di state_json selama aktif,
-- tidak pernah dikirim ke klien. Kartu tertutup bandar baru dikirim saat ronde selesai.
-- ---------------------------------------------------------------------
create or replace function game.ks_bj_val(c int) returns int
language sql immutable as $$ select case when c % 13 = 0 then 11 when c % 13 >= 9 then 10 else c % 13 + 1 end $$;
create or replace function game.ks_bj_score(h int[]) returns int
language plpgsql immutable as $$
declare t int := 0; a int := 0; c int;
begin
  if h is null then return 0; end if;
  foreach c in array h loop t := t + game.ks_bj_val(c); if c % 13 = 0 then a := a + 1; end if; end loop;
  while t > 21 and a > 0 loop t := t - 10; a := a - 1; end loop;
  return t;
end $$;

-- Kalibrasi Edge -> dorongan k (tools/sim-kasino.js, 1,5 jt tangan per titik, basic strategy).
-- k > 0 membantu bandar, k < 0 membantu kapten. ev = EV kapten per 1 gold.
create or replace function game.ks_bj_k(p_edge numeric) returns numeric
language plpgsql immutable as $$
declare tgt numeric := -p_edge; k0 numeric; e0 numeric; k1 numeric; e1 numeric; r record; first boolean := true;
begin
  for r in select * from (values
    (-2.0,0.13999), (-1.9,0.13318), (-1.8,0.12900), (-1.7,0.12487), (-1.6,0.11886), (-1.5,0.11239), (-1.4,0.10868), (-1.3,0.10306), (-1.2,0.09723), (-1.1,0.09162), (-1,0.08763), (-0.9,0.07704), (-0.8,0.06806), (-0.7,0.05852), (-0.6,0.04714), (-0.5,0.03859), (-0.4,0.02649), (-0.3,0.01551), (-0.2,0.00906), (-0.1,0.00010), (0,-0.01000), (0.1,-0.02607), (0.2,-0.03989), (0.3,-0.05805), (0.4,-0.07470), (0.5,-0.09189), (0.6,-0.10809), (0.7,-0.12427), (0.8,-0.14215)
  ) as t(k, ev) order by k loop
    if first then
      first := false; k0 := r.k; e0 := r.ev;
      if tgt >= e0 then return k0; end if;
      continue;
    end if;
    k1 := r.k; e1 := r.ev;
    if tgt >= e1 then return round(k0 + (k1 - k0) * (e0 - tgt) / nullif(e0 - e1, 0), 4); end if;
    k0 := k1; e0 := e1;
  end loop;
  return k0;
end $$;

create or replace function game.ks_bj_view(r game.kasino_round, p_done boolean) returns jsonb
language plpgsql stable as $$
declare s jsonb := r.state_json; p int[]; d int[];
begin
  select array_agg(x::int order by o) into p from jsonb_array_elements_text(s -> 'p') with ordinality as t(x, o);
  select array_agg(x::int order by o) into d from jsonb_array_elements_text(s -> 'd') with ordinality as t(x, o);
  return jsonb_build_object('id', r.id, 'game', 'blackjack', 'bet', r.bet_amount, 'active', not p_done,
    'p', to_jsonb(p), 'ps', game.ks_bj_score(p),
    'd', case when p_done then to_jsonb(d) else to_jsonb(array[d[1]]) end,
    'ds', case when p_done then game.ks_bj_score(d) else game.ks_bj_score(array[d[1]]) end,
    'canDouble', not p_done and array_length(p, 1) = 2,
    'expiresMs', case when p_done then null
      else (extract(epoch from r.created_at) * 1000)::bigint + (game.cfg_num('KasinoBjDetik', 120) * 1000)::bigint end)
    || case when p_done then jsonb_build_object('payout', r.payout_amount, 'net', r.net_delta, 'capped', r.capped,
         'hasil', s ->> 'hasil', 'double', coalesce((s ->> 'dbl')::boolean, false)) else '{}'::jsonb end;
end $$;

-- Ambil kartu berikutnya. p_who: 'p' (kapten) / 'd' (bandar). Dorongan k diterapkan pada kartu yang membuat bust.
create or replace function game.ks_bj_draw(s jsonb, p_who text) returns jsonb
language plpgsql volatile as $$
declare shoe jsonb := s -> 'shoe'; i int := (s ->> 'i')::int; k numeric := (s ->> 'k')::numeric;
  h int[]; c int;
begin
  select coalesce(array_agg(x::int order by o), '{}') into h from jsonb_array_elements_text(s -> p_who) with ordinality as t(x, o);
  c := (shoe ->> i)::int; i := i + 1;
  if p_who = 'd' and k > 0 and game.ks_bj_score(h || c) > 21 and random() < k then c := (shoe ->> i)::int; i := i + 1; end if;
  if p_who = 'p' and k < 0 then
    if game.ks_bj_score(h || c) > 21 and random() < least(1, -k) then c := (shoe ->> i)::int; i := i + 1; end if;
    if k < -1 and game.ks_bj_score(h || c) > 21 and random() < -k - 1 then c := (shoe ->> i)::int; i := i + 1; end if;
  end if;
  return s || jsonb_build_object('i', i, p_who, to_jsonb(h || c));
end $$;

-- Selesaikan ronde: bandar main (bila kapten tidak bust), hitung bayaran, potong kuota, bayar, buang sepatu.
create or replace function game.ks_bj_finish(p_id bigint, p_status text default 'settled') returns jsonb
language plpgsql as $$
declare r game.kasino_round; s jsonb; p int[]; d int[]; ps int; ds int; v_pay bigint; v_raw bigint; v_res text;
  v_gold bigint; v_nat boolean;
begin
  select * into r from game.kasino_round where id = p_id for update;
  if r.status <> 'active' then return game.ks_bj_view(r, true); end if;
  s := r.state_json;
  select array_agg(x::int order by o) into p from jsonb_array_elements_text(s -> 'p') with ordinality as t(x, o);
  ps := game.ks_bj_score(p);
  v_nat := coalesce((s ->> 'nat')::boolean, false);
  if ps <= 21 and not v_nat then
    loop
      select array_agg(x::int order by o) into d from jsonb_array_elements_text(s -> 'd') with ordinality as t(x, o);
      exit when game.ks_bj_score(d) >= 17;
      s := game.ks_bj_draw(s, 'd');
    end loop;
  end if;
  select array_agg(x::int order by o) into d from jsonb_array_elements_text(s -> 'd') with ordinality as t(x, o);
  ds := game.ks_bj_score(d);
  if v_nat then
    if ds = 21 and array_length(d, 1) = 2 then v_raw := r.bet_amount; v_res := 'seri';
    else v_raw := floor(r.bet_amount * 2.5)::bigint; v_res := 'blackjack'; end if;
  elsif ps > 21 then v_raw := 0; v_res := 'bust';
  elsif ds > 21 or ps > ds then v_raw := r.bet_amount * 2; v_res := 'menang';
  elsif ps = ds then v_raw := r.bet_amount; v_res := 'seri';
  else v_raw := 0; v_res := 'kalah'; end if;
  v_pay := game.ks_clamp(r.player_id, r.bet_amount, v_raw);
  update game.players set gold = gold + v_pay where player_id = r.player_id returning gold into v_gold;
  s := (s - 'shoe' - 'i' - 'k' - 'acts') || jsonb_build_object('hasil', v_res, 'ps', ps, 'ds', ds);
  update game.kasino_round set status = p_status, payout_amount = v_pay, net_delta = v_pay - bet_amount, gold_after = v_gold,
         capped = v_pay < v_raw, state_json = s, settled_at = now()
   where id = p_id returning * into r;
  perform game.ks_daily_add(r.player_id, r.ks_day, false, r.net_delta, r.bet_amount);
  return game.ks_bj_view(r, true);
end $$;

-- Ronde aktif yang sudah lewat batas waktu (atau semua, bila p_force) diselesaikan dengan stand otomatis.
create or replace function game.ks_bj_expire(p_pid uuid, p_force boolean default false) returns jsonb
language plpgsql as $$
declare r game.kasino_round; v jsonb := null;
begin
  for r in select * from game.kasino_round where player_id = p_pid and status = 'active'
     and (p_force or created_at < now() - make_interval(secs => game.cfg_num('KasinoBjDetik', 120))) loop
    v := game.ks_bj_finish(r.id, 'expired');
  end loop;
  return v;
end $$;

create or replace function game.ks_bj_start(p_bet bigint, p_nonce text) returns jsonb
language plpgsql as $$
declare v_me game.players := game.ks_begin('blackjack', p_bet, p_nonce); e numeric := game.ks_edge('blackjack');
  s jsonb; shoe jsonb; r game.kasino_round; p int[]; d int[]; v_id bigint;
begin
  select jsonb_agg(c order by random()) into shoe from (select g % 52 as c from generate_series(0, 311) g) x;
  s := jsonb_build_object('shoe', shoe, 'i', 4, 'k', game.ks_bj_k(e), 'acts', '[]'::jsonb,
         'p', jsonb_build_array(shoe -> 0, shoe -> 2), 'd', jsonb_build_array(shoe -> 1, shoe -> 3));
  update game.players set gold = gold - p_bet where player_id = v_me.player_id;
  insert into game.kasino_round(player_id, ks_day, game_day, game_type, gold_before, bet_amount, edge_applied,
    client_nonce, status, state_json)
  values (v_me.player_id, game.ks_day(), game.game_day(), 'blackjack', v_me.gold, p_bet, e, p_nonce, 'active', s)
  returning * into r;
  v_id := r.id;
  perform game.ks_daily_add(v_me.player_id, r.ks_day, true, null, null);
  p := array[(shoe ->> 0)::int, (shoe ->> 2)::int]; d := array[(shoe ->> 1)::int, (shoe ->> 3)::int];
  -- Bandar mengintip bila kartu terbukanya As / bernilai 10
  if game.ks_bj_val(d[1]) >= 10 and game.ks_bj_score(d) = 21 then
    return game.ks_bj_finish(v_id);
  end if;
  if game.ks_bj_score(p) = 21 then
    update game.kasino_round set state_json = state_json || '{"nat":true}'::jsonb where id = v_id;
    return game.ks_bj_finish(v_id);
  end if;
  return game.ks_bj_view(r, false);
end $$;

create or replace function game.ks_bj_act(p_id bigint, p_act text, p_nonce text) returns jsonb
language plpgsql as $$
declare v_me game.players := game.me(true); r game.kasino_round; s jsonb; p int[]; ps int;
begin
  select * into r from game.kasino_round where id = p_id and player_id = v_me.player_id for update;
  if not found then raise exception 'Ronde tidak ditemukan.'; end if;
  if r.status <> 'active' then return game.ks_bj_view(r, true); end if;
  if p_nonce is not null and r.state_json -> 'acts' ? p_nonce then return game.ks_bj_view(r, false); end if;
  if r.created_at < now() - make_interval(secs => game.cfg_num('KasinoBjDetik', 120)) then
    return game.ks_bj_finish(r.id, 'expired');
  end if;
  s := r.state_json;
  if p_nonce is not null then s := jsonb_set(s, '{acts}', (s -> 'acts') || to_jsonb(p_nonce)); end if;
  if p_act = 'stand' then
    update game.kasino_round set state_json = s where id = r.id;
    return game.ks_bj_finish(r.id);
  elsif p_act = 'hit' then
    s := game.ks_bj_draw(s, 'p');
  elsif p_act = 'double' then
    if jsonb_array_length(s -> 'p') <> 2 then raise exception 'Double hanya untuk dua kartu pertama.'; end if;
    if v_me.gold < r.bet_amount then raise exception 'Gold di tangan tidak cukup untuk Double.'; end if;
    update game.players set gold = gold - r.bet_amount where player_id = v_me.player_id;
    update game.kasino_round set bet_amount = bet_amount * 2 where id = r.id;
    s := game.ks_bj_draw(s, 'p') || '{"dbl":true}'::jsonb;
    update game.kasino_round set state_json = s where id = r.id;
    return game.ks_bj_finish(r.id);
  else
    raise exception 'Aksi meja tidak dikenal.';
  end if;
  update game.kasino_round set state_json = s where id = r.id returning * into r;
  select array_agg(x::int order by o) into p from jsonb_array_elements_text(s -> 'p') with ordinality as t(x, o);
  ps := game.ks_bj_score(p);
  if ps >= 21 then return game.ks_bj_finish(r.id); end if;
  return game.ks_bj_view(r, false);
end $$;

-- ---------------------------------------------------------------------
-- Papan Gambler (lobi): top 3 hari ini + top 1 pekan ini (Senin..Minggu WIB).
-- Peringkat berdasar TOTAL TARUHAN (turnover), bukan menang bersih, supaya batas
-- menang harian tidak terbaca dari papan dan angka kuota tetap tersembunyi.
-- ---------------------------------------------------------------------
create or replace function game.ks_papan(p_pid uuid) returns jsonb
language sql stable as $$
  with hr as (
    select d.player_id, d.turnover, d.rounds from game.kasino_daily d
     where d.ks_day = game.ks_day() and d.turnover > 0
     order by d.turnover desc, d.rounds desc, d.player_id limit 3),
  pk as (
    select d.player_id, sum(d.turnover)::bigint turnover, sum(d.rounds)::int rounds from game.kasino_daily d
     where d.ks_day between date_trunc('week', game.ks_day()::timestamp)::date and game.ks_day()
     group by d.player_id having sum(d.turnover) > 0
     order by 2 desc, 3 desc, 1 limit 1)
  select jsonb_build_object(
    'hari', coalesce((select jsonb_agg(jsonb_build_object('n', coalesce(nullif(p.character_name, ''), p.username),
               'turnover', h.turnover, 'rounds', h.rounds, 'me', h.player_id = p_pid)
               order by h.turnover desc, h.rounds desc, h.player_id)
               from hr h join game.players p on p.player_id = h.player_id), '[]'::jsonb),
    'pekan', (select jsonb_build_object('n', coalesce(nullif(p.character_name, ''), p.username),
               'turnover', k.turnover, 'rounds', k.rounds, 'me', k.player_id = p_pid)
               from pk k join game.players p on p.player_id = k.player_id))
$$;

-- ---------------------------------------------------------------------
-- Status untuk lobi (tanpa Edge, tanpa angka kuota)
-- ---------------------------------------------------------------------
create or replace function game.ks_status(p_pid uuid) returns jsonb
language plpgsql as $$
declare v_why text; v_gold bigint; v_bj game.kasino_round; v_log jsonb; v_tot jsonb;
begin
  perform game.ks_bj_expire(p_pid);
  v_why := game.ks_gate(p_pid);
  select gold into v_gold from game.players where player_id = p_pid;
  select * into v_bj from game.kasino_round where player_id = p_pid and status = 'active' limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'game', game_type, 'bet', bet_amount, 'net', net_delta,
           'at', (extract(epoch from coalesce(settled_at, created_at)) * 1000)::bigint) order by id desc), '[]'::jsonb)
    into v_log from (select * from game.kasino_round where player_id = p_pid and status <> 'active' order by id desc limit 12) x;
  select jsonb_build_object('rounds', count(*), 'turnover', coalesce(sum(bet_amount), 0), 'net', coalesce(sum(net_delta), 0))
    into v_tot from game.kasino_round where player_id = p_pid and status <> 'active';
  return jsonb_build_object(
    'open', v_why is null, 'why', v_why, 'msg', case when v_why is null then null else game.ks_gate_msg(v_why) end,
    'gold', v_gold, 'now', (extract(epoch from clock_timestamp()) * 1000)::bigint,
    'minBet', game.cfg_num('KasinoMinBet', 100), 'maxBet', game.cfg_num('KasinoMaxBet', 100000),
    'tables', jsonb_build_object('dadu', game.ks_table_on('dadu'), 'roulette', game.ks_table_on('roulette'),
                                 'blackjack', game.ks_table_on('blackjack'), 'slot', game.ks_table_on('slot')),
    'bj', case when v_bj.id is null then null else game.ks_bj_view(v_bj, false) end,
    'catatan', v_log, 'total', v_tot, 'papan', game.ks_papan(p_pid));
end $$;

-- ---------------------------------------------------------------------
-- API pemain: api_kasino([aksi, ...])
--   ['status']
--   ['dadu', taruhan, nonce]           ['slot', taruhan, nonce]
--   ['roulette', [{t,a,n?}], nonce]    t: red|black|even|odd|low|high|d1|d2|d3|num
--   ['bj', taruhan, nonce]             ['bjact', roundId, 'hit'|'stand'|'double', nonce]
-- ---------------------------------------------------------------------
create or replace function public.api_kasino(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_act text := lower(coalesce(game.arg(a, 0), 'status')); v_pid uuid; v_nonce text; r game.kasino_round; v_out jsonb;
begin
  v_pid := (game.me(true)).player_id;
  perform game.ks_bj_expire(v_pid);
  if v_act = 'status' then return jsonb_build_object('kasino', game.ks_status(v_pid)); end if;

  if v_act in ('dadu', 'slot', 'roulette', 'bj') then
    v_nonce := left(coalesce(game.arg(a, 2), ''), 64);
    -- Kiriman ganda: kembalikan hasil ronde yang sama
    select * into r from game.kasino_round where player_id = v_pid and client_nonce = v_nonce;
    if found then
      v_out := case when r.game_type = 'blackjack' then game.ks_bj_view(r, r.status <> 'active') else r.state_json -> 'out' end;
      return jsonb_build_object('round', v_out, 'replay', true, 'newGold', (select gold from game.players where player_id = v_pid),
        'kasino', game.ks_status(v_pid));
    end if;
    v_out := case v_act
      when 'dadu' then game.ks_play_dadu(game.arg_int(a, 1), v_nonce)
      when 'slot' then game.ks_play_slot(game.arg_int(a, 1), v_nonce)
      when 'roulette' then game.ks_play_roulette(game.arg_json(a, 1), v_nonce)
      else game.ks_bj_start(game.arg_int(a, 1), v_nonce) end;
  elsif v_act = 'bjact' then
    v_out := game.ks_bj_act(game.arg_int(a, 1), lower(coalesce(game.arg(a, 2), '')), left(game.arg(a, 3), 64));
  else
    raise exception 'Aksi tidak dikenal.';
  end if;
  return jsonb_build_object('round', v_out, 'newGold', (select gold from game.players where player_id = v_pid),
    'kasino', game.ks_status(v_pid));
end $$;
select game.expose('api_kasino');

-- ---------------------------------------------------------------------
-- GM: api_gmKasino([aksi, ...])
--   ['status']
--   ['edge', meja, persen (-10..10), catatan]   -> tercatat di kasino_edge_audit
--   ['gate', 'all'|meja, true|false]
-- ---------------------------------------------------------------------
create or replace function game.ks_gm_stats() returns jsonb
language sql stable as $$
  with r as (
    select game_type g, bet_amount::numeric b, payout_amount::numeric p, edge_applied::numeric e, ks_day, created_at
      from game.kasino_round where status <> 'active'),
  s as (
    select g, count(*) n, sum(b) bet, sum(p) pay, sum(b * (1 - e)) expv, sum(b * b) b2,
           avg(power(p / b - (1 - e), 2)) v,
           sum(b) filter (where created_at > now() - interval '24 hours') bet24,
           sum(p) filter (where created_at > now() - interval '24 hours') pay24,
           count(*) filter (where created_at > now() - interval '24 hours') n24
      from r group by g),
  z as (select *, case when v > 0 and b2 > 0 then (pay - expv) / sqrt(b2 * v) else 0 end zz from s)
  select coalesce(jsonb_object_agg(g, jsonb_build_object(
    'rounds', n, 'turnover', bet, 'payout', pay, 'houseNet', bet - pay,
    'rtp', round(pay / nullif(bet, 0), 4), 'rtpTarget', round(expv / nullif(bet, 0), 4), 'z', round(zz, 2),
    'rounds24', n24, 'turnover24', coalesce(bet24, 0), 'houseNet24', coalesce(bet24, 0) - coalesce(pay24, 0),
    'alarm', n >= game.cfg_num('KasinoAlarmMinRonde', 1000) and (zz > 4 or (g <> 'blackjack' and zz < -4)))), '{}'::jsonb)
  from z
$$;

create or replace function public.api_gmKasino(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_act text := lower(coalesce(game.arg(a, 0), 'status')); v_g text; v_new numeric; v_old numeric;
  v_note text; v_on boolean; k text;
begin
  if not game.is_gm(v_id) then raise exception 'Perintah ini khusus GM.'; end if;
  if v_act = 'edge' then
    v_g := lower(coalesce(game.arg(a, 1), ''));
    if not (v_g = any (game.ks_games())) then raise exception 'Meja tidak dikenal.'; end if;
    begin v_new := round((game.arg(a, 2))::numeric / 100, 4); exception when others then v_new := null; end;
    if v_new is null or v_new < -0.10 or v_new > 0.10 then raise exception 'Edge harus antara -10%% dan +10%%.'; end if;
    v_note := btrim(coalesce(game.arg(a, 3), ''));
    if length(v_note) < 3 then raise exception 'Isi catatan perubahan (alasan) dulu.'; end if;
    v_old := game.ks_edge(v_g);
    perform game.cfg_set('KasinoEdge' || game.ks_key(v_g), v_new::text);
    insert into game.kasino_edge_audit(gm_id, game_type, old_edge, new_edge, note) values (v_id, v_g, v_old, v_new, left(v_note, 300));
  elsif v_act = 'gate' then
    v_g := lower(coalesce(game.arg(a, 1), ''));
    v_on := lower(coalesce(game.arg(a, 2), '')) in ('1', 'true', 'on', 'ya');
    if v_g = 'all' then k := 'KasinoOpen';
    elsif v_g = any (game.ks_games()) then k := 'KasinoOpen' || game.ks_key(v_g);
    else raise exception 'Meja tidak dikenal.'; end if;
    perform game.cfg_set(k, case when v_on then '1' else '0' end);
    perform game.log(v_id, 'GM Kasino: ' || k || ' = ' || case when v_on then 'buka' else 'tutup' end || '.');
  elsif v_act <> 'status' then
    raise exception 'Aksi tidak dikenal.';
  end if;
  return jsonb_build_object(
    'open', lower(coalesce(game.cfg('KasinoOpen'), '0')) in ('1', 'true', 'on', 'ya'),
    'penguji', coalesce(game.cfg('FiturPenguji'), ''),
    'tables', (select jsonb_object_agg(g, game.ks_table_on(g)) from unnest(game.ks_games()) g),
    'edges', (select jsonb_object_agg(g, game.ks_edge(g) * 100) from unnest(game.ks_games()) g),
    'limits', jsonb_build_object('minBet', game.cfg_num('KasinoMinBet', 100), 'maxBet', game.cfg_num('KasinoMaxBet', 100000),
                                 'menangHarian', game.ks_cap(), 'alarmMinRonde', game.cfg_num('KasinoAlarmMinRonde', 1000)),
    'stats', game.ks_gm_stats(),
    'today', (select jsonb_build_object('rounds', count(*), 'players', count(distinct player_id),
                'turnover', coalesce(sum(bet_amount), 0), 'houseNet', -coalesce(sum(net_delta), 0))
                from game.kasino_round where ks_day = game.ks_day() and status <> 'active'),
    'top', (select coalesce(jsonb_agg(x order by (x ->> 'net')::bigint desc), '[]'::jsonb) from (
              select jsonb_build_object('kapten', coalesce(nullif(p.character_name, ''), p.username), 'net', sum(k.net_delta),
                       'rounds', count(*), 'penuh', sum(k.net_delta) >= game.ks_cap()) x
                from game.kasino_round k join game.players p on p.player_id = k.player_id
               where k.ks_day = game.ks_day() and k.status <> 'active'
               group by p.player_id, p.character_name, p.username order by sum(k.net_delta) desc limit 8) t),
    'audit', (select coalesce(jsonb_agg(jsonb_build_object('at', (extract(epoch from x.created_at) * 1000)::bigint,
                'gm', coalesce(p.username, '?'), 'game', x.game_type, 'old', x.old_edge * 100, 'new', x.new_edge * 100, 'note', x.note)
                order by x.id desc), '[]'::jsonb)
                from (select * from game.kasino_edge_audit order by id desc limit 15) x left join game.players p on p.player_id = x.gm_id));
end $$;
select game.expose('api_gmkasino');

-- ---------------------------------------------------------------------
-- Berlayar: ronde Blackjack aktif diselesaikan otomatis (stand) sebelum kapal berangkat.
-- Dibungkus di th_sail_guard (dipanggil mp_sail_guard 0030 dari quest_on_sail).
-- ---------------------------------------------------------------------
do $$
begin
  drop function if exists game.th_sail_guard_ks(uuid);
  alter function game.th_sail_guard(uuid) rename to th_sail_guard_ks;
end $$;
create or replace function game.th_sail_guard(p_pid uuid) returns void
language plpgsql as $$
begin
  perform game.ks_bj_expire(p_pid, true);
  perform game.th_sail_guard_ks(p_pid);
end $$;

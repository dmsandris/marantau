-- =====================================================================
-- Marantau (Supabase) - 0026 DUEL LAMBUNG (duel kapal antar pemain, Tide v30)
-- ---------------------------------------------------------------------
-- Pengganti duel "suit" untuk PvP. Duel melawan bajak laut & quest TIDAK berubah.
--   Fase taktis  : tiap giliran kedua kapten mengunci perintah (kemudi, layar, meriam kiri/kanan,
--                  peluru). Server mensimulasikan 3 detik pelayaran (angin, busur lambung, karang,
--                  tabrakan) dan menghitung tembakan. Taruhan aman karena semuanya dihitung server.
--   Pertarungan Terakhir : saat lambung kedua kapal <= 40% (atau giliran ke-24) taruhan DISELESAIKAN
--                  menurut kondisi kapal saat itu, lalu duel lanjut realtime di klien TANPA taruhan
--                  (hanya rekor & rating). Klien bertukar posisi lewat Realtime broadcast "duel:<id>"
--                  dengan cadangan relay RPC (api_mpDuelRt). Hasil dilaporkan masing-masing kapten
--                  (api_mpDuelFinal); laporan yang bertentangan -> seri.
-- Juga memperbaiki temuan audit duel (claude/AUDIT-Duel-Kapal-2026-10.md):
--   #2 duel yang ditinggal langsung diselesaikan (tidak lagi 1 ronde per menit)
--   #3 tidak bisa berlayar saat duel/undangan berjalan; penantang yang sudah pergi tidak bisa diterima
--   #4 kondisi kapal 0% tidak lagi dibaca 100%
-- Aman diulang (migrasi dijalankan ulang tiap deploy).
-- =====================================================================

alter table game.mp_duels add column if not exists st jsonb;            -- {w, a:{..}, b:{..}, stakeWin}
alter table game.mp_duels add column if not exists ord_a jsonb;         -- perintah giliran ini (rahasia)
alter table game.mp_duels add column if not exists ord_b jsonb;
alter table game.mp_duels add column if not exists ev jsonb;            -- hasil giliran terakhir (untuk animasi)
alter table game.mp_duels add column if not exists phase text;          -- plan | final
alter table game.mp_duels add column if not exists fin jsonb;           -- laporan akhir realtime {a:{..}, b:{..}}
alter table game.mp_duels add column if not exists stake_done boolean not null default false;
alter table game.mp_duels add column if not exists final_ts bigint;     -- ms mulai Pertarungan Terakhir

create table if not exists game.mp_duel_rt (
  duel_id text not null,
  side    text not null,
  st      jsonb,
  ts      bigint not null default 0,
  primary key (duel_id, side)
);
create table if not exists game.mp_duel_rtev (
  seq     bigserial primary key,
  duel_id text not null,
  side    text not null,
  ev      jsonb not null,
  ts      bigint not null
);
create index if not exists mp_duel_rtev_idx on game.mp_duel_rtev (duel_id, seq);
alter table game.mp_duel_rt enable row level security;
alter table game.mp_duel_rtev enable row level security;

-- ---------------------------------------------------------------------
-- Konstanta (satu tempat; klien DuelLambung.html memakai angka yang sama)
-- ---------------------------------------------------------------------
create or replace function game.lb_k(p_key text) returns float8
language sql immutable as $$
  select case p_key
    when 'plan_ms'  then 15000   -- waktu memberi perintah
    when 'anim_ms'  then 3400    -- animasi 3 detik + jeda
    when 'final_ms' then 75000   -- lama Pertarungan Terakhir
    when 'grace_ms' then 20000   -- batas tunggu laporan akhir
    when 'final_at' then 40      -- % lambung kedua kapal untuk masuk Pertarungan Terakhir
    when 'max_rounds' then 24
    else 0 end
$$;

-- sudut ke [-pi, pi)
create or replace function game.lb_ang(a float8) returns float8
language sql immutable as $$ select a - 2 * pi() * floor((a + pi()) / (2 * pi())) $$;

-- faktor kecepatan menurut sudut angin (w = arah angin bertiup)
create or replace function game.lb_wf(h float8, w float8) returns float8
language plpgsql immutable as $$
declare a float8 := abs(game.lb_ang(h - (w + pi())));
begin
  if a < 0.62 then return 0.12 + a * 0.12; end if;
  if a < 1.75 then return 0.25 + 0.75 * sin((a - 0.62) / (1.75 - 0.62) * pi() / 2); end if;
  return 1.0 - (a - 1.75) / (pi() - 1.75) * 0.22;
end $$;

-- satu langkah fisika kapal: kembalikan {x, y, h, v, bump}
create or replace function game.lb_step(x float8, y float8, h float8, v float8, rud int, sails int, sail float8, dt float8, w float8)
returns float8[] language plpgsql immutable as $$
declare tr float8; ts float8; bump float8 := 0; m float8 := 60;
begin
  tr := 0.2 * (case when sails = 1 then 0.85 else 1 end) * (0.55 + 0.45 * least(1, v / 30));
  h := game.lb_ang(h + rud * tr * dt);
  ts := 62 * game.lb_wf(h, w) * (case when sails = 1 then 1 else 0.55 end) * (0.3 + 0.7 * sail / 100);
  v := v + (ts - v) * (1 - exp(-dt * 0.9));
  x := x + sin(h) * v * dt; y := y - cos(h) * v * dt;
  if x < m then x := m; bump := 1; end if;
  if x > 2200 - m then x := 2200 - m; bump := 1; end if;
  if y < m then y := m; bump := 1; end if;
  if y > 1500 - m then y := 1500 - m; bump := 1; end if;
  if bump = 1 then v := v * 0.4; end if;
  return array[x, y, h, v, bump];
end $$;

create or replace function game.lb_reload(crew float8) returns float8
language sql immutable as $$ select 5.4 * (1 + (100 - crew) / 100 * 0.9) $$;

-- salvo 5 meriam dari (fx,fy,fh) ke sasaran (tx,ty) di sisi side (-1 kiri, +1 kanan)
create or replace function game.lb_volley(fx float8, fy float8, fh float8, tx float8, ty float8, side int, ammo text,
  crew float8, dm float8, tf float8)
returns jsonb language plpgsql volatile as $$
declare rel float8; off float8; q float8 := 0; d float8; maxr float8; p float8; hits jsonb := '[]'::jsonb; k int; hit boolean;
  dh float8 := 0; ds float8 := 0; dc float8 := 0; cl float8;
begin
  d := sqrt(power(tx - fx, 2) + power(ty - fy, 2));
  rel := game.lb_ang(atan2(tx - fx, -(ty - fy)) - fh);
  off := abs(game.lb_ang(rel - side * pi() / 2));
  if off <= 0.62 then q := 1 - off / 0.62 * 0.6; end if;
  maxr := case when ammo = 'grape' then 300 else 470 end;
  p := greatest(0, least(0.92, 1.05 - d / (maxr * 1.05))) * (0.75 + 0.25 * crew / 100);
  cl := greatest(0, least(1, (300 - d) / 200));
  for k in 1..5 loop
    hit := q > 0 and d <= maxr and random() < p * q;
    hits := hits || to_jsonb(hit);
    if hit then
      if ammo = 'ball' then dh := dh + (3.4 + random() * 1.2) * dm * tf; dc := dc + 0.6;
      elsif ammo = 'chain' then ds := ds + (5.5 + random() * 2) * dm; dh := dh + 0.6 * tf;
      else dc := dc + (5 + random() * 2) * (0.35 + 0.65 * cl) * dm; dh := dh + 0.8 * tf;
      end if;
    end if;
  end loop;
  return jsonb_build_object('hits', hits, 'd', round(d::numeric, 1), 'q', round(q::numeric, 3),
    'hull', round(dh::numeric, 2), 'sail', round(ds::numeric, 2), 'crew', round(dc::numeric, 2));
end $$;

-- kapal awal dari statistik petarung (mp_fighter): daya tembak & ketangguhan ikut tier/upgrade
create or replace function game.lb_ship0(f jsonb, x float8, y float8, h float8) returns jsonb
language sql immutable as $$
  select jsonb_build_object('x', x, 'y', y, 'h', h, 'v', 22, 'hull', 100, 'sail', 100, 'crew', 100, 'rlL', 0, 'rlR', 0,
    'rud', 0, 'sails', 1, 'ammo', 'ball',
    'dm', greatest(0.8, least(1.35, 0.8 + (coalesce((f ->> 'atk')::float8, 20) - 20) / 100)),
    'tf', greatest(0.75, least(1.25, 120 / greatest(1, coalesce((f ->> 'maxHp')::float8, 120)))))
$$;

create or replace function game.lb_auto(s jsonb) returns jsonb
language sql immutable as $$
  select jsonb_build_object('rud', coalesce((s ->> 'rud')::int, 0), 'sails', coalesce((s ->> 'sails')::int, 1),
    'fl', false, 'fr', false, 'ammo', coalesce(s ->> 'ammo', 'ball'), 'auto', true)
$$;

-- validasi perintah dari klien
create or replace function game.lb_order(o jsonb) returns jsonb
language plpgsql stable as $$
declare r int; s int; a text;
begin
  if o is null or jsonb_typeof(o) <> 'object' then raise exception 'Perintah tidak valid.'; end if;
  begin r := (o ->> 'rud')::int; exception when others then r := 0; end;
  begin s := (o ->> 'sails')::int; exception when others then s := 1; end;
  a := coalesce(o ->> 'ammo', 'ball');
  if a not in ('ball', 'chain', 'grape') then a := 'ball'; end if;
  return jsonb_build_object('rud', greatest(-2, least(2, coalesce(r, 0))), 'sails', case when s = 0 then 0 else 1 end,
    'fl', game.mp_truthy(o -> 'fl'), 'fr', game.mp_truthy(o -> 'fr'), 'ammo', a);
end $$;

-- ---------------------------------------------------------------------
-- finish_ (pengganti 0005): bayar pot HANYA bila taruhan belum diselesaikan
-- ---------------------------------------------------------------------
create or replace function game.mp_finish(d game.mp_duels) returns game.mp_duels
language plpgsql as $$
declare pot bigint := d.stake * 2; w uuid; l uuid; what text; msg text; nm_a text; nm_b text; v_pay boolean;
begin
  d.status := 'done'; d.ended := game.now_ms();
  v_pay := not coalesce(d.stake_done, false) and d.stake > 0;
  if d.winner = 'draw' then
    if v_pay then
      update game.players set gold = gold + d.stake where player_id = d.a_id;
      update game.players set gold = gold + d.stake where player_id = d.b_id;
    end if;
    perform game.mp_pvp_update(d.a_id, d.b_id, true);
  else
    w := case when d.winner = 'a' then d.a_id else d.b_id end;
    l := case when d.winner = 'a' then d.b_id else d.a_id end;
    if v_pay then update game.players set gold = gold + pot where player_id = w; end if;
    perform game.mp_pvp_update(w, l, false);
  end if;
  d.stake_done := true;
  nm_a := d.fa ->> 'n'; nm_b := d.fb ->> 'n';
  what := case when d.kind = 'dice' then 'duel dadu' else 'duel kapal' end;
  msg := case when d.winner = 'draw' then 'Seri dalam ' || what || ' melawan ' || nm_b || '.'
    when d.winner = 'a' then 'Menang ' || what || ' melawan ' || nm_b || case when v_pay then ' (+' || d.stake || ' gold).' else '.' end
    else 'Kalah ' || what || ' melawan ' || nm_b || case when v_pay then ' (-' || d.stake || ' gold).' else '.' end end;
  begin perform game.log(d.a_id, msg); exception when others then null; end;
  msg := case when d.winner = 'draw' then 'Seri dalam ' || what || ' melawan ' || nm_a || '.'
    when d.winner = 'b' then 'Menang ' || what || ' melawan ' || nm_a || case when v_pay then ' (+' || d.stake || ' gold).' else '.' end
    else 'Kalah ' || what || ' melawan ' || nm_a || case when v_pay then ' (-' || d.stake || ' gold).' else '.' end end;
  begin perform game.log(d.b_id, msg); exception when others then null; end;
  delete from game.mp_duel_rt where duel_id = d.id;
  delete from game.mp_duel_rtev where duel_id = d.id;
  return d;
end $$;

-- taruhan diselesaikan saat masuk Pertarungan Terakhir (kondisi kapal saat itu)
create or replace function game.lb_settle_stake(d game.mp_duels) returns game.mp_duels
language plpgsql as $$
declare ca float8; cb float8; v_w text;
begin
  ca := (d.st -> 'a' ->> 'hull')::float8 + (d.st -> 'a' ->> 'crew')::float8 * 0.5;
  cb := (d.st -> 'b' ->> 'hull')::float8 + (d.st -> 'b' ->> 'crew')::float8 * 0.5;
  v_w := case when abs(ca - cb) < 5 then 'draw' when ca > cb then 'a' else 'b' end;
  if d.stake > 0 and not coalesce(d.stake_done, false) then
    if v_w = 'draw' then
      update game.players set gold = gold + d.stake where player_id in (d.a_id, d.b_id);
      begin perform game.log(d.a_id, 'Taruhan duel dikembalikan: kedua kapal sama-sama sekarat.'); exception when others then null; end;
      begin perform game.log(d.b_id, 'Taruhan duel dikembalikan: kedua kapal sama-sama sekarat.'); exception when others then null; end;
    else
      update game.players set gold = gold + d.stake * 2 where player_id = case when v_w = 'a' then d.a_id else d.b_id end;
      begin perform game.log(case when v_w = 'a' then d.a_id else d.b_id end, 'Taruhan duel dimenangkan (+' || d.stake || ' gold): kapalmu lebih utuh saat Pertarungan Terakhir dimulai.'); exception when others then null; end;
      begin perform game.log(case when v_w = 'a' then d.b_id else d.a_id end, 'Taruhan duel lepas (-' || d.stake || ' gold): kapal lawan lebih utuh saat Pertarungan Terakhir dimulai.'); exception when others then null; end;
    end if;
  end if;
  d.stake_done := true;
  d.st := d.st || jsonb_build_object('stakeWin', v_w);
  return d;
end $$;

-- ---------------------------------------------------------------------
-- Simulasi satu giliran (3 detik, langkah 0,05 detik). p_base = cap waktu dasar giliran berikutnya.
-- ---------------------------------------------------------------------
create or replace function game.lb_resolve(d game.mp_duels, p_base bigint) returns game.mp_duels
language plpgsql as $$
declare
  s jsonb := d.st; w float8 := (d.st ->> 'w')::float8; sa0 jsonb := d.st -> 'a'; sb0 jsonb := d.st -> 'b';
  oa jsonb := coalesce(d.ord_a, game.lb_auto(d.st -> 'a')); ob jsonb := coalesce(d.ord_b, game.lb_auto(d.st -> 'b'));
  ax float8 := (sa0 ->> 'x')::float8; ay float8 := (sa0 ->> 'y')::float8; ah float8 := (sa0 ->> 'h')::float8; av float8 := (sa0 ->> 'v')::float8;
  bx float8 := (sb0 ->> 'x')::float8; by_ float8 := (sb0 ->> 'y')::float8; bh float8 := (sb0 ->> 'h')::float8; bv float8 := (sb0 ->> 'v')::float8;
  ahull float8 := (sa0 ->> 'hull')::float8; asail float8 := (sa0 ->> 'sail')::float8; acrew float8 := (sa0 ->> 'crew')::float8;
  bhull float8 := (sb0 ->> 'hull')::float8; bsail float8 := (sb0 ->> 'sail')::float8; bcrew float8 := (sb0 ->> 'crew')::float8;
  arl float8 := (sa0 ->> 'rlL')::float8; arr float8 := (sa0 ->> 'rlR')::float8; brl float8 := (sb0 ->> 'rlL')::float8; brr float8 := (sb0 ->> 'rlR')::float8;
  adm float8 := (sa0 ->> 'dm')::float8; atf float8 := (sa0 ->> 'tf')::float8; bdm float8 := (sb0 ->> 'dm')::float8; btf float8 := (sb0 ->> 'tf')::float8;
  ra int := (oa ->> 'rud')::int; sla int := (oa ->> 'sails')::int; rb int := (ob ->> 'rud')::int; slb int := (ob ->> 'sails')::int;
  ama text := oa ->> 'ammo'; amb text := ob ->> 'ammo';
  areef float8 := 0; breef float8 := 0; ramcd float8 := 0; dt float8 := 0.05; t float8 := 0; i int; fired boolean := false;
  r float8[]; shots jsonb := '[]'::jsonb; vol jsonb; rams int := 0; dd float8; bb float8; push float8; rv float8;
  hit_a jsonb := jsonb_build_object('hull', 0, 'sail', 0, 'crew', 0); hit_b jsonb := jsonb_build_object('hull', 0, 'sail', 0, 'crew', 0);
  v_end text; t_now bigint := game.now_ms();
begin
  for i in 1..60 loop
    r := game.lb_step(ax, ay, ah, av, ra, sla, asail, dt, w); ax := r[1]; ay := r[2]; ah := r[3]; av := r[4];
    if r[5] = 1 and areef <= 0 then ahull := greatest(0, ahull - 2.5); areef := 1.2; end if;
    r := game.lb_step(bx, by_, bh, bv, rb, slb, bsail, dt, w); bx := r[1]; by_ := r[2]; bh := r[3]; bv := r[4];
    if r[5] = 1 and breef <= 0 then bhull := greatest(0, bhull - 2.5); breef := 1.2; end if;
    areef := areef - dt; breef := breef - dt;
    arl := greatest(0, arl - dt); arr := greatest(0, arr - dt); brl := greatest(0, brl - dt); brr := greatest(0, brr - dt);
    t := t + dt;
    if not fired and t >= 1.0 - 1e-9 then
      fired := true;
      -- salvo serentak: damage dihitung dari posisi saat ini, lalu diterapkan bersama
      if coalesce((oa ->> 'fl')::boolean, false) and arl <= 0 then
        vol := game.lb_volley(ax, ay, ah, bx, by_, -1, ama, acrew, adm, btf); arl := game.lb_reload(acrew);
        shots := shots || jsonb_build_array(vol || jsonb_build_object('by', 'a', 'side', -1, 'ammo', ama, 'fx', ax, 'fy', ay, 'fh', ah, 'tx', bx, 'ty', by_));
        hit_b := jsonb_build_object('hull', (hit_b ->> 'hull')::float8 + (vol ->> 'hull')::float8, 'sail', (hit_b ->> 'sail')::float8 + (vol ->> 'sail')::float8, 'crew', (hit_b ->> 'crew')::float8 + (vol ->> 'crew')::float8);
      end if;
      if coalesce((oa ->> 'fr')::boolean, false) and arr <= 0 then
        vol := game.lb_volley(ax, ay, ah, bx, by_, 1, ama, acrew, adm, btf); arr := game.lb_reload(acrew);
        shots := shots || jsonb_build_array(vol || jsonb_build_object('by', 'a', 'side', 1, 'ammo', ama, 'fx', ax, 'fy', ay, 'fh', ah, 'tx', bx, 'ty', by_));
        hit_b := jsonb_build_object('hull', (hit_b ->> 'hull')::float8 + (vol ->> 'hull')::float8, 'sail', (hit_b ->> 'sail')::float8 + (vol ->> 'sail')::float8, 'crew', (hit_b ->> 'crew')::float8 + (vol ->> 'crew')::float8);
      end if;
      if coalesce((ob ->> 'fl')::boolean, false) and brl <= 0 then
        vol := game.lb_volley(bx, by_, bh, ax, ay, -1, amb, bcrew, bdm, atf); brl := game.lb_reload(bcrew);
        shots := shots || jsonb_build_array(vol || jsonb_build_object('by', 'b', 'side', -1, 'ammo', amb, 'fx', bx, 'fy', by_, 'fh', bh, 'tx', ax, 'ty', ay));
        hit_a := jsonb_build_object('hull', (hit_a ->> 'hull')::float8 + (vol ->> 'hull')::float8, 'sail', (hit_a ->> 'sail')::float8 + (vol ->> 'sail')::float8, 'crew', (hit_a ->> 'crew')::float8 + (vol ->> 'crew')::float8);
      end if;
      if coalesce((ob ->> 'fr')::boolean, false) and brr <= 0 then
        vol := game.lb_volley(bx, by_, bh, ax, ay, 1, amb, bcrew, bdm, atf); brr := game.lb_reload(bcrew);
        shots := shots || jsonb_build_array(vol || jsonb_build_object('by', 'b', 'side', 1, 'ammo', amb, 'fx', bx, 'fy', by_, 'fh', bh, 'tx', ax, 'ty', ay));
        hit_a := jsonb_build_object('hull', (hit_a ->> 'hull')::float8 + (vol ->> 'hull')::float8, 'sail', (hit_a ->> 'sail')::float8 + (vol ->> 'sail')::float8, 'crew', (hit_a ->> 'crew')::float8 + (vol ->> 'crew')::float8);
      end if;
      ahull := greatest(0, ahull - (hit_a ->> 'hull')::float8); asail := greatest(0, asail - (hit_a ->> 'sail')::float8); acrew := greatest(0, acrew - (hit_a ->> 'crew')::float8);
      bhull := greatest(0, bhull - (hit_b ->> 'hull')::float8); bsail := greatest(0, bsail - (hit_b ->> 'sail')::float8); bcrew := greatest(0, bcrew - (hit_b ->> 'crew')::float8);
    end if;
    -- tabrakan lambung
    dd := sqrt(power(bx - ax, 2) + power(by_ - ay, 2));
    if dd < 58 then
      bb := atan2(bx - ax, -(by_ - ay)); push := (58 - dd) / 2 + 1;
      ax := ax - sin(bb) * push; ay := ay + cos(bb) * push; bx := bx + sin(bb) * push; by_ := by_ - cos(bb) * push;
      if ramcd <= 0 then
        rv := abs(av - bv) + (av + bv) * 0.3;
        ahull := greatest(0, ahull - (1.5 + rv * 0.05) * atf); bhull := greatest(0, bhull - (1.5 + rv * 0.05) * btf);
        av := av * 0.5; bv := bv * 0.5; ramcd := 1.0; rams := rams + 1;
      end if;
    end if;
    ramcd := ramcd - dt;
  end loop;

  d.ev := jsonb_build_object('r', d.round, 'start', s, 'oa', oa, 'ob', ob, 'shots', shots, 'rams', rams,
    'hitA', hit_a, 'hitB', hit_b, 'auto', jsonb_build_object('a', d.ord_a is null, 'b', d.ord_b is null));
  d.st := jsonb_build_object('w', game.lb_ang(w + (random() - 0.5) * 0.5),
    'a', sa0 || jsonb_build_object('x', ax, 'y', ay, 'h', ah, 'v', av, 'hull', ahull, 'sail', asail, 'crew', acrew, 'rlL', arl, 'rlR', arr,
                                   'rud', ra, 'sails', sla, 'ammo', ama),
    'b', sb0 || jsonb_build_object('x', bx, 'y', by_, 'h', bh, 'v', bv, 'hull', bhull, 'sail', bsail, 'crew', bcrew, 'rlL', brl, 'rlR', brr,
                                   'rud', rb, 'sails', slb, 'ammo', amb));
  d.ord_a := null; d.ord_b := null; d.pick_a := null; d.pick_b := null; d.pick_ts := 0;
  d.log := coalesce(d.log, '[]'::jsonb) || jsonb_build_array(jsonb_build_object('r', d.round, 'a', round(ahull::numeric), 'b', round(bhull::numeric)));
  while jsonb_array_length(d.log) > 30 loop d.log := d.log - 0; end loop;

  -- tenggelam / menyerah
  if ahull <= 0 or acrew <= 0 or bhull <= 0 or bcrew <= 0 then
    v_end := case when (ahull <= 0 or acrew <= 0) and (bhull <= 0 or bcrew <= 0) then 'draw'
                  when ahull <= 0 or acrew <= 0 then 'b' else 'a' end;
    d.winner := v_end;
    return game.mp_finish(d);
  end if;
  -- Pertarungan Terakhir
  if (ahull <= game.lb_k('final_at') and bhull <= game.lb_k('final_at')) or d.round >= game.lb_k('max_rounds') then
    d := game.lb_settle_stake(d);
    d.phase := 'final';
    d.final_ts := greatest(p_base, t_now) + game.lb_k('anim_ms')::bigint + 2500;
    d.round_ts := d.final_ts;
    return d;
  end if;
  d.round := d.round + 1;
  d.round_ts := p_base + game.lb_k('anim_ms')::bigint;
  return d;
end $$;

-- hasil Pertarungan Terakhir dari laporan kedua kapten
create or replace function game.lb_final_decide(d game.mp_duels, p_timeout boolean) returns game.mp_duels
language plpgsql as $$
declare fa jsonb := d.fin -> 'a'; fb jsonb := d.fin -> 'b'; sa boolean; sb boolean; ha float8; hb float8;
begin
  sa := coalesce((fa ->> 'sunk')::boolean, false); sb := coalesce((fb ->> 'sunk')::boolean, false);
  if not (sa or sb or (fa is not null and fb is not null) or p_timeout) then return d; end if;
  if sa and sb then d.winner := 'draw';
  elsif sa then d.winner := 'b';
  elsif sb then d.winner := 'a';
  elsif fa is null and fb is null then d.winner := 'draw';
  elsif fa is null then d.winner := 'b'; d.forfeit := 'a';
  elsif fb is null then d.winner := 'a'; d.forfeit := 'b';
  else
    ha := (fa ->> 'hull')::float8 + (fa ->> 'crew')::float8 * 0.25; hb := (fb ->> 'hull')::float8 + (fb ->> 'crew')::float8 * 0.25;
    d.winner := case when abs(ha - hb) < 2 then 'draw' when ha > hb then 'a' else 'b' end;
  end if;
  return game.mp_finish(d);
end $$;

-- ---------------------------------------------------------------------
-- tick_ & needs_tick (pengganti 0005): + duel lambung, + penyelesaian duel yang ditinggal sekaligus
-- ---------------------------------------------------------------------
create or replace function game.mp_needs_tick(d game.mp_duels) returns boolean
language plpgsql stable as $$
declare t bigint := game.now_ms();
begin
  if d.id is null then return false; end if;
  if d.status = 'invited' then return t - d.created > 60000; end if;
  if d.status <> 'active' then return false; end if;
  if d.kind = 'lambung' then
    if d.phase = 'final' then return t > d.final_ts + game.lb_k('final_ms') + game.lb_k('grace_ms'); end if;
    return t > d.round_ts + game.lb_k('plan_ms');
  end if;
  if d.kind <> 'naval' then return false; end if;
  if d.pick_a is not null or d.pick_b is not null then return t - d.pick_ts > 25000; end if;
  return t - d.round_ts > 60000;
end $$;

create or replace function game.mp_tick(d game.mp_duels) returns game.mp_duels
language plpgsql as $$
declare t bigint := game.now_ms(); one boolean; gone_a boolean; gone_b boolean; n int; v_base bigint;
begin
  if d.status = 'invited' and t - d.created > 60000 then d.status := 'expired'; return d; end if;
  if d.status <> 'active' then return d; end if;
  if d.kind = 'lambung' then
    if d.phase = 'final' then
      if t > d.final_ts + game.lb_k('final_ms') + game.lb_k('grace_ms') then d := game.lb_final_decide(d, true); end if;
      return d;
    end if;
    for n in 1..40 loop
      exit when d.status <> 'active' or coalesce(d.phase, 'plan') <> 'plan' or t <= d.round_ts + game.lb_k('plan_ms');
      v_base := d.round_ts + game.lb_k('plan_ms')::bigint;
      if d.ord_a is null then d.afk_a := coalesce(d.afk_a, 0) + 1; end if;
      if d.ord_b is null then d.afk_b := coalesce(d.afk_b, 0) + 1; end if;
      gone_a := d.afk_a >= 3; gone_b := d.afk_b >= 3;
      if gone_a and gone_b then d.winner := 'draw'; return game.mp_finish(d); end if;
      if gone_a then d.winner := 'b'; d.forfeit := 'a'; return game.mp_finish(d); end if;
      if gone_b then d.winner := 'a'; d.forfeit := 'b'; return game.mp_finish(d); end if;
      d := game.lb_resolve(d, v_base);
    end loop;
    return d;
  end if;
  if d.kind <> 'naval' then return d; end if;
  -- duel suit lama (sisa duel yang masih berjalan saat deploy)
  one := d.pick_a is not null or d.pick_b is not null;
  if (one and t - d.pick_ts > 25000) or (not one and t - d.round_ts > 60000) then
    if d.pick_a is null then d.pick_a := 'brace'; d.afk_a := coalesce(d.afk_a, 0) + 1; end if;
    if d.pick_b is null then d.pick_b := 'brace'; d.afk_b := coalesce(d.afk_b, 0) + 1; end if;
    gone_a := d.afk_a >= 3; gone_b := d.afk_b >= 3;
    if gone_a and gone_b then d.winner := 'draw'; return game.mp_finish(d); end if;
    if gone_a then d.winner := 'b'; d.forfeit := 'a'; return game.mp_finish(d); end if;
    if gone_b then d.winner := 'a'; d.forfeit := 'b'; return game.mp_finish(d); end if;
    d := game.mp_resolve(d);
  end if;
  return d;
end $$;

create or replace function game.mp_duel_refresh(p_id text) returns game.mp_duels
language plpgsql as $$
declare d game.mp_duels; before text;
begin
  if p_id is null then return d; end if;
  select * into d from game.mp_duels where id = p_id;
  if not found or not game.mp_needs_tick(d) then return d; end if;
  select * into d from game.mp_duels where id = p_id for update;
  before := d.status || '|' || d.round || '|' || coalesce(d.phase, '');
  d := game.mp_tick(d);
  if d.status || '|' || d.round || '|' || coalesce(d.phase, '') <> before then perform game.mp_duel_save(d); end if;
  return d;
end $$;

create or replace function game.mp_duel_save(d game.mp_duels) returns void
language plpgsql as $$
begin
  update game.mp_duels set
    kind = d.kind, stake = d.stake, status = d.status, city = d.city, created = d.created, ended = d.ended,
    fa = d.fa, fb = d.fb, round = d.round, hp_a = d.hp_a, hp_b = d.hp_b, ammo_a = d.ammo_a, ammo_b = d.ammo_b,
    pick_a = d.pick_a, pick_b = d.pick_b, pick_ts = d.pick_ts, round_ts = d.round_ts, afk_a = d.afk_a, afk_b = d.afk_b,
    log = d.log, last = d.last, winner = d.winner, forfeit = d.forfeit, dice = d.dice,
    st = d.st, ord_a = d.ord_a, ord_b = d.ord_b, ev = d.ev, phase = d.phase, fin = d.fin, stake_done = d.stake_done, final_ts = d.final_ts
  where id = d.id;
  perform game.mp_rt('player:' || (d.fa ->> 'pub'), 'duel', jsonb_build_object('duelId', d.id, 'status', d.status, 'round', d.round));
  perform game.mp_rt('player:' || (d.fb ->> 'pub'), 'duel', jsonb_build_object('duelId', d.id, 'status', d.status, 'round', d.round));
end $$;

-- ---------------------------------------------------------------------
-- Tampilan untuk klien
-- ---------------------------------------------------------------------
create or replace function game.lb_view(d game.mp_duels, p_viewer uuid) returns jsonb
language plpgsql stable as $$
declare me_a boolean := d.a_id = p_viewer; ms text; os text; you jsonb; foe jsonb; sw text;
begin
  ms := case when me_a then 'a' else 'b' end; os := case when me_a then 'b' else 'a' end;
  you := case when me_a then d.fa else d.fb end; foe := case when me_a then d.fb else d.fa end;
  sw := d.st ->> 'stakeWin';
  return jsonb_build_object(
    'id', d.id, 'kind', d.kind, 'status', d.status, 'stake', d.stake, 'round', d.round, 'maxRounds', game.lb_k('max_rounds'),
    'created', d.created, 't', game.now_ms(), 'challenger', me_a,
    'you', jsonb_build_object('id', you -> 'pub', 'n', you -> 'n', 'a', you -> 'a', 'tier', you -> 'tier', 'f', coalesce(you -> 'f', 'null'::jsonb), 's', coalesce(you -> 's', 'null'::jsonb)),
    'foe', jsonb_build_object('id', foe -> 'pub', 'n', foe -> 'n', 'a', foe -> 'a', 'tier', foe -> 'tier', 'f', coalesce(foe -> 'f', 'null'::jsonb), 's', coalesce(foe -> 's', 'null'::jsonb)),
    'winner', case when d.winner = 'draw' then 'draw' when d.winner is null then null when d.winner = ms then 'you' else 'foe' end,
    'forfeit', case when d.forfeit is null then null when d.forfeit = ms then 'you' else 'foe' end,
    'lb', jsonb_build_object(
      'me', ms, 'phase', coalesce(d.phase, 'plan'), 'st', d.st, 'ev', d.ev,
      'myOrd', case when me_a then d.ord_a else d.ord_b end,
      'locked', case when me_a then d.ord_a is not null else d.ord_b is not null end,
      'foeLocked', case when me_a then d.ord_b is not null else d.ord_a is not null end,
      'planStart', d.round_ts, 'planDeadline', d.round_ts + game.lb_k('plan_ms')::bigint,
      'finalTs', d.final_ts, 'finalEnd', case when d.final_ts is null then null else d.final_ts + game.lb_k('final_ms')::bigint end,
      'stakeWin', case when sw is null then null when sw = 'draw' then 'draw' when sw = ms then 'you' else 'foe' end,
      'reported', d.fin -> ms is not null, 'foeReported', d.fin -> os is not null,
      'finFoe', case when d.status = 'done' then d.fin -> os else null end,
      'k', jsonb_build_object('planMs', game.lb_k('plan_ms'), 'animMs', game.lb_k('anim_ms'), 'finalMs', game.lb_k('final_ms'), 'finalAt', game.lb_k('final_at'))));
end $$;

-- mp_view (pengganti 0005): cabang duel lambung
create or replace function game.mp_view_v1(d game.mp_duels, p_viewer uuid) returns jsonb
language plpgsql stable as $$
declare me_a boolean := d.a_id = p_viewer; ms text; os text; you jsonb; foe jsonb; v jsonb;
  y_hp int; y_ammo int; y_pick text; f_hp int; f_ammo int; f_pick text;
begin
  ms := case when me_a then 'a' else 'b' end; os := case when me_a then 'b' else 'a' end;
  you := case when me_a then d.fa else d.fb end; foe := case when me_a then d.fb else d.fa end;
  y_hp := case when me_a then d.hp_a else d.hp_b end; f_hp := case when me_a then d.hp_b else d.hp_a end;
  y_ammo := case when me_a then d.ammo_a else d.ammo_b end; f_ammo := case when me_a then d.ammo_b else d.ammo_a end;
  y_pick := case when me_a then d.pick_a else d.pick_b end; f_pick := case when me_a then d.pick_b else d.pick_a end;
  v := jsonb_build_object(
    'id', d.id, 'kind', d.kind, 'status', d.status, 'stake', d.stake, 'round', d.round, 'maxRounds', 12,
    'created', d.created, 't', game.now_ms(),
    'you', jsonb_strip_nulls(jsonb_build_object('id', you -> 'pub', 'n', you -> 'n', 'a', you -> 'a', 'tier', you -> 'tier',
             'maxHp', you -> 'maxHp', 'hp', y_hp, 'ammo', y_ammo, 'ammoMax', you -> 'ammoMax', 'picked', y_pick is not null))
           || jsonb_build_object('f', coalesce(you -> 'f', 'null'::jsonb), 's', coalesce(you -> 's', 'null'::jsonb), 'pick', y_pick),
    'foe', jsonb_strip_nulls(jsonb_build_object('id', foe -> 'pub', 'n', foe -> 'n', 'a', foe -> 'a', 'tier', foe -> 'tier',
             'maxHp', foe -> 'maxHp', 'hp', f_hp, 'ammo', f_ammo, 'ammoMax', foe -> 'ammoMax', 'picked', f_pick is not null))
           || jsonb_build_object('f', coalesce(foe -> 'f', 'null'::jsonb), 's', coalesce(foe -> 's', 'null'::jsonb)),
    'challenger', me_a,
    'pickDeadline', case when d.pick_ts > 0 then d.pick_ts + 25000 else 0 end,
    'roundTs', d.round_ts,
    'winner', case when d.winner = 'draw' then 'draw' when d.winner is null then null when d.winner = ms then 'you' else 'foe' end,
    'forfeit', case when d.forfeit is null then null when d.forfeit = ms then 'you' else 'foe' end);
  if d.last is not null then
    v := v || jsonb_build_object('last', jsonb_build_object('r', d.last -> 'r',
      'youPick', d.last -> 'pick' -> ms, 'foePick', d.last -> 'pick' -> os,
      'youDmg', d.last -> 'dmg' -> ms, 'foeDmg', d.last -> 'dmg' -> os,
      'youNote', d.last -> 'note' -> ms, 'foeNote', d.last -> 'note' -> os));
  end if;
  if d.dice is not null then
    v := v || jsonb_build_object('dice', jsonb_build_object('you', d.dice -> ms, 'foe', d.dice -> os));
  end if;
  return v;
end $$;

create or replace function game.mp_view(d game.mp_duels, p_viewer uuid) returns jsonb
language plpgsql stable as $$
begin
  if d.kind = 'lambung' then return game.lb_view(d, p_viewer); end if;
  return game.mp_view_v1(d, p_viewer);
end $$;

-- ---------------------------------------------------------------------
-- fighter_ (pengganti 0005): kondisi 0% tidak lagi dibaca 100% (audit #4)
-- ---------------------------------------------------------------------
create or replace function game.mp_fighter(p_pid uuid) returns jsonb
language plpgsql as $$
declare p game.players; sh jsonb; st jsonb; o game.mp_presence; v_tier numeric; v_cond numeric;
begin
  select * into p from game.players where player_id = p_pid;
  if not found or coalesce(p.archetype, '') = '' then raise exception 'Kapten tidak ditemukan.'; end if;
  begin sh := game.ship_json(p_pid); exception when others then sh := null; end;
  st := coalesce(game.stats_json(p_pid), '{}'::jsonb);
  select * into o from game.mp_presence where player_id = p_pid;
  if o.pub is null then raise exception 'Kapten itu sudah tidak terlihat di pelabuhan.'; end if;
  v_tier := game.mp_jsnum(sh ->> 'TierNum', 1);
  begin v_cond := coalesce((sh ->> 'ConditionPct')::numeric, 100); exception when others then v_cond := 100; end;
  v_cond := greatest(0, least(100, v_cond));
  return jsonb_build_object(
    'pub', o.pub, 'n', p.character_name, 'a', p.archetype, 'f', coalesce(o.f, 'null'::jsonb), 'tier', v_tier,
    's', coalesce(o.s, 'null'::jsonb),
    'maxHp', 80 + v_tier * 20 + game.mp_jsround(v_cond / 5),
    'atk', 12 + game.mp_jsnum(st ->> 'Combat', 0) * 0.18 + game.mp_jsnum(sh ->> 'Combat', 0) * 1.2
               + game.mp_jsnum(sh ->> 'CannonBonusPercent', 0) * 0.08,
    'luck', game.mp_jsnum(st ->> 'Luck', 0),
    'ammoMax', least(6, game.mp_jsnum(sh ->> 'MaxCannonAmmo', 3)));
end $$;

-- ---------------------------------------------------------------------
-- ENDPOINT
-- ---------------------------------------------------------------------
-- Tantangan: duel kapal kini selalu "lambung" (permintaan 'naval' dari klien lama ikut diubah)
create or replace function public.api_mpDuelChallenge(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_target uuid; v_kind text; v_stake bigint; t game.mp_presence; me_p game.mp_presence;
  v_loc text; v_gold bigint; d game.mp_duels;
begin
  v_target := game.mp_unpub(game.arg(a, 0));
  v_kind := case when game.arg(a, 2) = 'dice' then 'dice' else 'lambung' end;
  if v_target = v_id then raise exception 'Tidak bisa menantang diri sendiri.'; end if;
  v_stake := game.mp_clamp(a, 1, 0, 100000);
  perform game.mp_xlock(v_id);
  select * into t from game.mp_presence where player_id = v_target;
  if not found or not game.mp_online(t) then raise exception 'Kapten itu sedang tidak online.'; end if;
  me_p := game.mp_presence_sync(v_id);
  if me_p.player_id is null then raise exception 'Muat ulang game dulu sebelum mengobrol.'; end if;
  perform game.mp_duel_refresh(game.mp_slot(v_id));
  if game.mp_slot(v_id) is not null then raise exception 'Kamu masih punya duel yang belum selesai.'; end if;
  perform game.mp_duel_refresh(game.mp_slot(v_target));
  if game.mp_slot(v_target) is not null then raise exception '% sedang berduel dengan kapten lain.', t.n; end if;
  v_loc := game.current_city(v_id);
  if game.in_transit(v_id) then raise exception 'Duel hanya bisa saat kapal merapat.'; end if;
  if t.sea or t.c <> v_loc then raise exception '% tidak berada di pelabuhan yang sama.', t.n; end if;
  select gold into v_gold from game.players where player_id = v_id;
  if coalesce(v_gold, 0) < v_stake then raise exception 'Gold-mu tidak cukup untuk taruhan %.', v_stake; end if;
  insert into game.mp_duels(id, kind, stake, status, city, created, a_id, b_id, fa, fb)
  values (game.mp_uid('d'), v_kind, v_stake, 'invited', v_loc, game.now_ms(), v_id, v_target,
          game.mp_fighter(v_id), game.mp_fighter(v_target))
  returning * into d;
  perform game.mp_push_inbox(v_target, jsonb_build_object('type', 'duel_invite', 'duelId', d.id, 'kind', v_kind,
    'from', d.fa ->> 'n', 'fromId', d.fa ->> 'pub', 'stake', v_stake, 'fa', d.fa ->> 'a', 'ff', d.fa -> 'f'));
  return game.mp_view(d, v_id);
end $$;
select game.expose('api_mpduelchallenge');

create or replace function public.api_mpDuelRespond(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_duel text := game.arg(a, 0); v_accept boolean := game.mp_truthy(game.arg_json(a, 1));
  d game.mp_duels; v_slot text; ga bigint; gb bigint; v_w float8;
begin
  perform game.mp_xlock(v_id);
  select * into d from game.mp_duels where id = v_duel for update;
  if not found or d.b_id <> v_id then raise exception 'Tantangan tidak ditemukan atau sudah kedaluwarsa.'; end if;
  if d.status <> 'invited' then return game.mp_view(d, v_id); end if;
  if game.now_ms() - d.created > 60000 then raise exception 'Tantangan sudah kedaluwarsa.'; end if;
  if not v_accept then
    d.status := 'declined';
    perform game.mp_duel_save(d);
    perform game.mp_push_inbox(d.a_id, jsonb_build_object('type', 'duel_declined', 'duelId', d.id, 'from', d.fb ->> 'n'));
    return game.mp_view(d, v_id);
  end if;
  v_slot := game.mp_slot(v_id);
  if v_slot is not null and v_slot <> d.id then
    perform game.mp_duel_refresh(v_slot);
    v_slot := game.mp_slot(v_id);
    if v_slot is not null and v_slot <> d.id then raise exception 'Selesaikan duelmu yang lain dulu.'; end if;
  end if;
  select gold into ga from game.players where player_id = d.a_id;
  select gold into gb from game.players where player_id = v_id;
  if coalesce(gb, 0) < d.stake then raise exception 'Gold-mu tidak cukup untuk taruhan %.', d.stake; end if;
  if coalesce(ga, 0) < d.stake then raise exception '% sudah tidak punya cukup gold untuk taruhan ini.', d.fa ->> 'n'; end if;
  if game.current_city(v_id) <> d.city or game.in_transit(v_id) then raise exception 'Kamu harus berada di pelabuhan yang sama.'; end if;
  -- audit #3: penantang harus masih merapat di pelabuhan yang sama
  if coalesce(game.current_city(d.a_id), '') <> d.city or game.in_transit(d.a_id) then
    raise exception '% sudah meninggalkan pelabuhan.', d.fa ->> 'n';
  end if;
  if d.stake > 0 then
    update game.players set gold = gold - d.stake where player_id = d.a_id and gold >= d.stake;
    if not found then raise exception '% sudah tidak punya cukup gold untuk taruhan ini.', d.fa ->> 'n'; end if;
    update game.players set gold = gold - d.stake where player_id = v_id and gold >= d.stake;
    if not found then raise exception 'Gold-mu tidak cukup untuk taruhan %.', d.stake; end if;
  end if;
  d.status := 'active';
  if d.kind = 'dice' then
    d := game.mp_roll_dice(d);
    d := game.mp_finish(d);
  elsif d.kind = 'lambung' then
    v_w := random() * 2 * pi() - pi();
    d.round := 1; d.phase := 'plan'; d.afk_a := 0; d.afk_b := 0; d.stake_done := false; d.fin := null;
    d.round_ts := game.now_ms() + 4500;   -- salvo kehormatan sebelum giliran pertama
    d.st := jsonb_build_object('w', v_w,
      'a', game.lb_ship0(d.fa, 836, 900, 0.9),
      'b', game.lb_ship0(d.fb, 1364, 600, -2.25));
  else
    d.round := 1; d.round_ts := game.now_ms();
    d.hp_a := (d.fa ->> 'maxHp')::numeric; d.hp_b := (d.fb ->> 'maxHp')::numeric;
    d.ammo_a := (d.fa ->> 'ammoMax')::numeric; d.ammo_b := (d.fb ->> 'ammoMax')::numeric;
    d.afk_a := 0; d.afk_b := 0;
  end if;
  perform game.mp_duel_save(d);
  perform game.mp_push_inbox(d.a_id, jsonb_build_object('type', 'duel_start', 'duelId', d.id, 'from', d.fb ->> 'n', 'kind', d.kind));
  return game.mp_view(d, v_id);
end $$;
select game.expose('api_mpduelrespond');

-- Aksi: duel lambung menerima objek perintah {rud, sails, fl, fr, ammo}; duel suit lama tetap
create or replace function public.api_mpDuelAct(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_duel text := game.arg(a, 0); v_round bigint := game.arg_int(a, 1); v_tac text;
  d game.mp_duels; before text; me_a boolean; v_ord jsonb;
begin
  select * into d from game.mp_duels where id = v_duel for update;
  if not found or (d.a_id <> v_id and d.b_id <> v_id) then raise exception 'Duel tidak ditemukan.'; end if;
  me_a := d.a_id = v_id;
  if d.kind = 'lambung' then
    v_ord := game.lb_order(game.arg_json(a, 2));
    before := d.status || '|' || d.round || '|' || coalesce(d.phase, '');
    d := game.mp_tick(d);
    if d.status <> 'active' or d.phase <> 'plan' or v_round is distinct from d.round::bigint then
      if d.status || '|' || d.round || '|' || coalesce(d.phase, '') <> before then perform game.mp_duel_save(d); end if;
      return game.mp_view(d, v_id);
    end if;
    if me_a and d.ord_a is null then d.ord_a := v_ord; d.afk_a := 0; d.pick_a := 'x';
    elsif not me_a and d.ord_b is null then d.ord_b := v_ord; d.afk_b := 0; d.pick_b := 'x';
    end if;
    if d.ord_a is not null and d.ord_b is not null then
      d := game.lb_resolve(d, greatest(game.now_ms(), d.round_ts));
    end if;
    perform game.mp_duel_save(d);
    return game.mp_view(d, v_id);
  end if;
  -- duel suit lama
  v_tac := game.arg(a, 2);
  if v_tac is null or v_tac not in ('fire', 'evade', 'ram', 'brace', 'reload') then raise exception 'Taktik tidak dikenal.'; end if;
  before := d.status || '|' || d.round;
  d := game.mp_tick(d);
  if d.status <> 'active' or d.kind <> 'naval' then
    if d.status || '|' || d.round <> before then perform game.mp_duel_save(d); end if;
    return game.mp_view(d, v_id);
  end if;
  if v_round is distinct from d.round::bigint then
    if d.status || '|' || d.round <> before then perform game.mp_duel_save(d); end if;
    return game.mp_view(d, v_id);
  end if;
  if v_tac = 'fire' and coalesce(case when me_a then d.ammo_a else d.ammo_b end, 0) <= 0 then v_tac := 'brace'; end if;
  if me_a and d.pick_a is null then
    d.pick_a := v_tac; d.afk_a := 0; if d.pick_ts = 0 then d.pick_ts := game.now_ms(); end if;
  elsif not me_a and d.pick_b is null then
    d.pick_b := v_tac; d.afk_b := 0; if d.pick_ts = 0 then d.pick_ts := game.now_ms(); end if;
  end if;
  if d.pick_a is not null and d.pick_b is not null then d := game.mp_resolve(d); end if;
  perform game.mp_duel_save(d);
  return game.mp_view(d, v_id);
end $$;
select game.expose('api_mpduelact');

-- Laporan akhir Pertarungan Terakhir: kondisi kapal SENDIRI (pemilik kapal yang berwenang atas lambungnya)
create or replace function public.api_mpDuelFinal(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_duel text := game.arg(a, 0); d game.mp_duels; ms text; v_h float8; v_c float8; v_sunk boolean; v_max float8;
begin
  select * into d from game.mp_duels where id = v_duel for update;
  if not found or (d.a_id <> v_id and d.b_id <> v_id) then raise exception 'Duel tidak ditemukan.'; end if;
  if d.status <> 'active' or d.kind <> 'lambung' or d.phase <> 'final' then return game.mp_view(d, v_id); end if;
  ms := case when d.a_id = v_id then 'a' else 'b' end;
  if d.fin -> ms is null then
    -- lambung tidak bisa bertambah selama Pertarungan Terakhir
    v_max := (d.st -> ms ->> 'hull')::float8;
    begin v_h := (game.arg(a, 1))::float8; exception when others then v_h := 0; end;
    begin v_c := (game.arg(a, 2))::float8; exception when others then v_c := 0; end;
    v_h := greatest(0, least(coalesce(v_max, 100), coalesce(v_h, 0)));
    v_c := greatest(0, least((d.st -> ms ->> 'crew')::float8, coalesce(v_c, 0)));
    v_sunk := game.mp_truthy(game.arg_json(a, 3)) or v_h <= 0 or v_c <= 0;
    d.fin := coalesce(d.fin, '{}'::jsonb) || jsonb_build_object(ms, jsonb_build_object('hull', round(v_h::numeric, 1), 'crew', round(v_c::numeric, 1), 'sunk', v_sunk, 'ts', game.now_ms()));
  end if;
  d := game.lb_final_decide(d, false);
  perform game.mp_duel_save(d);
  return game.mp_view(d, v_id);
end $$;
select game.expose('api_mpduelfinal');

-- Relay cadangan Pertarungan Terakhir (bila Realtime broadcast tidak tersedia)
create or replace function public.api_mpDuelRt(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_duel text := game.arg(a, 0); v_st jsonb := game.arg_json(a, 1); v_evs jsonb := game.arg_json(a, 2);
  v_since bigint := coalesce(game.arg_int(a, 3), 0); d game.mp_duels; ms text; os text; e jsonb; n int := 0; f game.mp_duel_rt;
  v_ev jsonb; v_max bigint; t bigint := game.now_ms();
begin
  select * into d from game.mp_duels where id = v_duel;
  if not found or (d.a_id <> v_id and d.b_id <> v_id) then raise exception 'Duel tidak ditemukan.'; end if;
  ms := case when d.a_id = v_id then 'a' else 'b' end; os := case when ms = 'a' then 'b' else 'a' end;
  if d.status <> 'active' or d.phase <> 'final' then return jsonb_build_object('status', d.status, 'phase', d.phase, 't', t); end if;
  if v_st is not null and jsonb_typeof(v_st) = 'object' and length(v_st::text) < 600 then
    insert into game.mp_duel_rt(duel_id, side, st, ts) values (d.id, ms, v_st, t)
    on conflict (duel_id, side) do update set st = excluded.st, ts = excluded.ts;
  end if;
  if v_evs is not null and jsonb_typeof(v_evs) = 'array' then
    for e in select value from jsonb_array_elements(v_evs) loop
      n := n + 1; exit when n > 12;
      if length(e::text) < 700 then insert into game.mp_duel_rtev(duel_id, side, ev, ts) values (d.id, ms, e, t); end if;
    end loop;
  end if;
  select * into f from game.mp_duel_rt where duel_id = d.id and side = os;
  select coalesce(jsonb_agg(jsonb_build_object('seq', x.seq, 'ev', x.ev) order by x.seq), '[]'::jsonb), max(x.seq) into v_ev, v_max
  from (select * from game.mp_duel_rtev where duel_id = d.id and side = os and seq > v_since order by seq limit 40) x;
  return jsonb_build_object('status', d.status, 'phase', d.phase, 't', t, 'foe', f.st, 'foeTs', f.ts, 'ev', v_ev, 'seq', coalesce(v_max, v_since));
end $$;
select game.expose('api_mpduelrt');

create or replace function public.api_mpDuelForfeit(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_duel text := game.arg(a, 0); d game.mp_duels;
begin
  select * into d from game.mp_duels where id = v_duel for update;
  if not found or (d.a_id <> v_id and d.b_id <> v_id) then raise exception 'Duel tidak ditemukan.'; end if;
  if d.status = 'invited' and d.a_id = v_id then
    d.status := 'cancelled'; perform game.mp_duel_save(d); return game.mp_view(d, v_id);
  end if;
  if d.status <> 'active' then return game.mp_view(d, v_id); end if;
  d.winner := case when d.a_id = v_id then 'b' else 'a' end;
  d.forfeit := case when d.a_id = v_id then 'a' else 'b' end;
  d := game.mp_finish(d);
  perform game.mp_duel_save(d);
  return game.mp_view(d, v_id);
end $$;
select game.expose('api_mpduelforfeit');

-- ---------------------------------------------------------------------
-- Audit #3: tidak bisa berlayar saat duel / undangan duel masih berjalan
-- (quest_on_sail dipanggil di dalam transaksi api_setSail; raise = pelayaran batal)
-- ---------------------------------------------------------------------
create or replace function game.mp_sail_guard(p_pid uuid) returns void
language plpgsql as $$
declare v_slot text; d game.mp_duels;
begin
  v_slot := game.mp_slot(p_pid);
  if v_slot is null then return; end if;
  d := game.mp_duel_refresh(v_slot);
  if d.status = 'invited' then raise exception 'Batalkan dulu tantangan duelmu sebelum berlayar.'; end if;
  if d.status = 'active' then raise exception 'Selesaikan duelmu dulu sebelum berlayar.'; end if;
end $$;

create or replace function game.quest_on_sail(p_pid uuid, p_origin text, p_dest text) returns void
language plpgsql as $$
begin
  perform game.mp_sail_guard(p_pid);
  perform game.ww_on_sail(p_pid, p_origin, p_dest);
  perform game.bx_on_sail(p_pid, p_origin, p_dest);
  perform game.kp_on_sail(p_pid, p_origin, p_dest);
end $$;

-- ---------------------------------------------------------------------
-- Realtime: kanal "duel:<id>" boleh didengar & dipakai kirim oleh kedua kapten duel itu saja
-- ---------------------------------------------------------------------
create or replace function public.mt_rt_duel_ok(p_topic text) returns boolean
language plpgsql stable security definer set search_path = game, public as $$
declare v_id text;
begin
  if auth.uid() is null or p_topic is null or p_topic not like 'duel:%' then return false; end if;
  v_id := substr(p_topic, 6);
  return exists (select 1 from game.mp_duels where id = v_id and status = 'active' and (a_id = auth.uid() or b_id = auth.uid()));
end $$;
revoke all on function public.mt_rt_duel_ok(text) from public;
revoke all on function public.mt_rt_duel_ok(text) from anon;
grant execute on function public.mt_rt_duel_ok(text) to authenticated;

create or replace function public.mt_rt_can_read(p_topic text) returns boolean
language plpgsql stable security definer set search_path = game, public as $$
declare v_pub text;
begin
  if auth.uid() is null or p_topic is null then return false; end if;
  if p_topic = 'chat:global' or p_topic like 'chat:city:%' then return true; end if;
  if p_topic like 'player:%' then
    select pub into v_pub from game.mp_presence where player_id = auth.uid();
    return v_pub is not null and p_topic = 'player:' || v_pub;
  end if;
  if p_topic like 'duel:%' then return public.mt_rt_duel_ok(p_topic); end if;
  return false;
end $$;
revoke all on function public.mt_rt_can_read(text) from public;
revoke all on function public.mt_rt_can_read(text) from anon;
grant execute on function public.mt_rt_can_read(text) to authenticated;

do $$
begin
  if to_regclass('realtime.messages') is not null then
    execute 'drop policy if exists "marantau kirim duel" on realtime.messages';
    execute 'create policy "marantau kirim duel" on realtime.messages for insert to authenticated '
         || 'with check (realtime.messages.extension = ''broadcast'' and public.mt_rt_duel_ok(realtime.topic()))';
  end if;
exception when others then
  raise warning 'Kebijakan kirim duel tidak terpasang (relay RPC tetap jalan): %', sqlerrm;
end $$;

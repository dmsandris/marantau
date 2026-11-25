-- =====================================================================
-- 0106 · S5 mini game "Dengar Tanah" (kind = 'listen'), konsep 8.4
--
--   Preset: cari_lereng · lagu_tidur · lagu_tidur_pendek · akar_selatan
--   game.mg_listen_build(pid, ctx, preset, assist) -> params (dikirim ke klien; tanpa nilai ekonomi)
--   game.mg_listen_judge(params, log, elapsed)     -> {won, ...} ; log tidak sah -> exception
--   Penilaian identik dengan klien (web/src/S5Dengar.html, blok S5DengarNilai), diuji JS = SQL.
--   Semua waktu milidetik bilangan bulat. Bantuan otomatis 0/15/30 dari kerangka 0105.
-- Aman diulang.
-- =====================================================================

-- Pola napas (selang denyut, ms). A = napas tidur (selalu jawaban).
create or replace function game.mg_listen_pola() returns jsonb
language sql immutable as $$
  select '{"A":[1000,1000,2000,1000,1000,2000],"B":[500,500,500,500,500,500],"C":[1500,500,1500,500,1500,500]}'::jsonb
$$;

-- Tiga frasa lagu tidur: [pad, offset_beat]
create or replace function game.mg_listen_frasa() returns jsonb
language sql immutable as $$
  select '{"1":[[1,0],[1,1],[2,2],[1,4]],
           "2":[[1,0],[1,1],[2,2],[1,4],[0,5],[0,6]],
           "3":[[1,0],[1,1],[2,2],[1,4],[0,5],[0,6],[1,8],[2,9]]}'::jsonb
$$;

create or replace function game.mg_listen_build(p_pid uuid, p_ctx text, p_preset text, p_assist int) returns jsonb
language plpgsql volatile as $$
declare k numeric := case p_assist when 30 then 1.4 when 15 then 1.2 else 1 end; v_urut jsonb;
begin
  if p_preset = 'cari_lereng' then
    select jsonb_agg(x order by random()) into v_urut from unnest(array['A', 'B', 'C']) x;
    return jsonb_build_object('preset', p_preset, 'assist', p_assist,
      'S', game.rand_int(0, 8), 'urut', v_urut, 'pola', game.mg_listen_pola(),
      'probes', case p_assist when 30 then 8 when 15 then 7 else 5 end,
      'answers', case p_assist when 30 then 3 else 2 end,
      'tries', 2, 'listen_ms', 1500, 'max_ms', 90000, 'min_total_ms', 12000);
  elsif p_preset in ('lagu_tidur', 'lagu_tidur_pendek') then
    return jsonb_build_object('preset', p_preset, 'assist', p_assist,
      'frasa', case when p_preset = 'lagu_tidur' then game.mg_listen_frasa()
                    else jsonb_build_object('3', game.mg_listen_frasa() -> '3') end,
      'urutan', case when p_preset = 'lagu_tidur' then '[1,2,3]'::jsonb else '[3]'::jsonb end,
      'beat_ms', 750, 'tol_ms', floor(200 * k)::int,
      'tries', case p_assist when 30 then 3 else 2 end, 'replays', 2,
      'max_ms', case when p_preset = 'lagu_tidur' then 180000 else 90000 end,
      'min_total_ms', case when p_preset = 'lagu_tidur' then 25000 else 12000 end);
  elsif p_preset = 'akar_selatan' then
    return jsonb_build_object('preset', p_preset, 'assist', p_assist,
      'target', 4, 'answers', 2, 'interval_ms', 1800, 'beats', 6,
      'hits_needed', case p_assist when 30 then 3 else 4 end, 'tol_ms', floor(300 * k)::int,
      'max_ms', 120000, 'min_total_ms', 20000);
  end if;
  raise exception 'Aksi tidak dikenal.';
end $$;

-- ---------- pemeriksa bentuk log ----------
create or replace function game.mg_listen_int(v jsonb, p_min bigint, p_max bigint) returns bigint
language plpgsql immutable as $$
declare n numeric;
begin
  if coalesce(jsonb_typeof(v), '') <> 'number' then raise exception 'Catatan permainan tidak sah.'; end if;
  n := v::text::numeric;
  if n <> trunc(n) or n < p_min or n > p_max then raise exception 'Catatan permainan tidak sah.'; end if;
  return n::bigint;
end $$;

create or replace function game.mg_listen_arr(v jsonb, p_max int) returns jsonb
language plpgsql immutable as $$
begin
  if v is null or jsonb_typeof(v) = 'null' then return '[]'::jsonb; end if;
  if jsonb_typeof(v) <> 'array' or jsonb_array_length(v) > p_max then raise exception 'Catatan permainan tidak sah.'; end if;
  return v;
end $$;

-- Satu percobaan frasa cocok? (urutan pad sama, waktu relatif ke ketukan pertama dalam toleransi)
create or replace function game.mg_listen_frasa_cocok(p_att jsonb, p_frasa jsonb, p_beat int, p_tol int) returns boolean
language plpgsql immutable as $$
declare j int; t0 bigint; e0 int; tj bigint; ej int;
begin
  if jsonb_typeof(p_att) <> 'array' or jsonb_array_length(p_att) <> jsonb_array_length(p_frasa) then return false; end if;
  t0 := (p_att -> 0 ->> 't_ms')::bigint; e0 := (p_frasa -> 0 ->> 1)::int;
  for j in 0 .. jsonb_array_length(p_frasa) - 1 loop
    if (p_att -> j ->> 'pad')::int <> (p_frasa -> j ->> 0)::int then return false; end if;
    tj := (p_att -> j ->> 't_ms')::bigint; ej := (p_frasa -> j ->> 1)::int;
    if abs((tj - t0) - (ej - e0)::bigint * p_beat) > p_tol then return false; end if;
  end loop;
  return true;
end $$;

-- Pencocokan detak akar: tiap ketukan berurutan -> detak terdekat yang belum terpakai dalam toleransi (seri -> indeks terkecil)
create or replace function game.mg_listen_hits(p_taps jsonb, p_t0 bigint, p_interval int, p_beats int, p_tol int) returns int
language plpgsql immutable as $$
declare used boolean[] := array_fill(false, array[p_beats]); i int; k int; t bigint; best int; bd bigint; d bigint; hits int := 0;
begin
  for i in 0 .. jsonb_array_length(p_taps) - 1 loop
    t := (p_taps -> i ->> 't_ms')::bigint; best := -1; bd := null;
    for k in 0 .. p_beats - 1 loop
      if not used[k + 1] then
        d := abs(t - (p_t0 + k::bigint * p_interval));
        if d <= p_tol and (bd is null or d < bd) then bd := d; best := k; end if;
      end if;
    end loop;
    if best >= 0 then used[best + 1] := true; hits := hits + 1; end if;
  end loop;
  return hits;
end $$;

create or replace function game.mg_listen_judge(p jsonb, l jsonb, p_elapsed bigint) returns jsonb
language plpgsql stable as $$
declare
  v_pre text := p ->> 'preset'; v_max bigint := (p ->> 'max_ms')::bigint; v_lim bigint := p_elapsed + 3000;
  a jsonb; b jsonb; c jsonb; i int; j int; x jsonb; v_last bigint := -1; t bigint; v_ok boolean; v_dir boolean := false;
  v_n int; v_frasa jsonb; v_hits int; v_t0 bigint; v_try int; v_idx int := -1; k int;
begin
  if coalesce(jsonb_typeof(l), '') <> 'object' then raise exception 'Catatan permainan tidak sah.'; end if;
  v_lim := least(v_lim, v_max);

  if v_pre = 'cari_lereng' then
    a := game.mg_listen_arr(l -> 'probes', (p ->> 'probes')::int);
    b := game.mg_listen_arr(l -> 'answers', (p ->> 'answers')::int);
    c := game.mg_listen_arr(l -> 'pattern_picks', (p ->> 'tries')::int);
    -- urutan fase: dengar & gali (bercampur, waktu tidak menurun), lalu baca napas
    for i in 0 .. jsonb_array_length(a) - 1 loop
      t := game.mg_listen_int(a -> i -> 't_ms', 0, v_lim); perform game.mg_listen_int(a -> i -> 'p', 0, 8);
      if i > 0 and t < (a -> (i - 1) ->> 't_ms')::bigint then raise exception 'Catatan permainan tidak sah.'; end if;
    end loop;
    for i in 0 .. jsonb_array_length(b) - 1 loop
      t := game.mg_listen_int(b -> i -> 't_ms', 0, v_lim);
      if t < v_last then raise exception 'Catatan permainan tidak sah.'; end if; v_last := t;
      if game.mg_listen_int(b -> i -> 'p', 0, 8) = (p ->> 'S')::int then v_dir := true; v_idx := i; exit; end if;
    end loop;
    if v_dir and jsonb_array_length(b) > v_idx + 1 then raise exception 'Catatan permainan tidak sah.'; end if;   -- tidak ada galian setelah benar
    v_ok := false;
    for i in 0 .. jsonb_array_length(c) - 1 loop
      if not v_dir then raise exception 'Catatan permainan tidak sah.'; end if;
      t := game.mg_listen_int(c -> i -> 't_ms', 0, v_lim);
      if t < v_last then raise exception 'Catatan permainan tidak sah.'; end if; v_last := t;
      if coalesce(jsonb_typeof(c -> i -> 'opsi'), '') <> 'string' or (c -> i ->> 'opsi') not in ('A', 'B', 'C') then raise exception 'Catatan permainan tidak sah.'; end if;
      if c -> i ->> 'opsi' = 'A' then v_ok := true; v_idx := i; exit; end if;
    end loop;
    if v_ok and jsonb_array_length(c) > v_idx + 1 then raise exception 'Catatan permainan tidak sah.'; end if;
    return jsonb_build_object('won', v_dir and v_ok, 'gali', v_dir, 'napas', v_ok);

  elsif v_pre in ('lagu_tidur', 'lagu_tidur_pendek') then
    a := game.mg_listen_arr(l -> 'phrases', jsonb_array_length(p -> 'urutan'));
    v_ok := jsonb_array_length(a) = jsonb_array_length(p -> 'urutan');
    for i in 0 .. jsonb_array_length(a) - 1 loop
      x := a -> i;
      if coalesce(jsonb_typeof(x), '') <> 'object' then raise exception 'Catatan permainan tidak sah.'; end if;
      v_n := game.mg_listen_int(x -> 'n', 1, 3);
      if v_n <> (p -> 'urutan' ->> i)::int then raise exception 'Catatan permainan tidak sah.'; end if;
      if x ? 'replays' and game.mg_listen_int(x -> 'replays', 0, 99) > (p ->> 'replays')::int then raise exception 'Catatan permainan tidak sah.'; end if;
      b := game.mg_listen_arr(x -> 'attempts', (p ->> 'tries')::int);
      v_frasa := p -> 'frasa' -> v_n::text; v_try := 0;
      for j in 0 .. jsonb_array_length(b) - 1 loop
        c := game.mg_listen_arr(b -> j, 24);
        for k in 0 .. jsonb_array_length(c) - 1 loop
          t := game.mg_listen_int(c -> k -> 't_ms', 0, v_lim); perform game.mg_listen_int(c -> k -> 'pad', 0, 2);
          if t < v_last then raise exception 'Catatan permainan tidak sah.'; end if; v_last := t;
        end loop;
        if game.mg_listen_frasa_cocok(c, v_frasa, (p ->> 'beat_ms')::int, (p ->> 'tol_ms')::int) then v_try := j + 1; exit; end if;
      end loop;
      if v_try = 0 then
        v_ok := false;
        if i < jsonb_array_length(a) - 1 then raise exception 'Catatan permainan tidak sah.'; end if;   -- frasa berikut tak boleh ada bila ini gagal
      elsif v_try < jsonb_array_length(b) then raise exception 'Catatan permainan tidak sah.';           -- tidak ada percobaan setelah cocok
      end if;
    end loop;
    return jsonb_build_object('won', v_ok, 'frasa', jsonb_array_length(a));

  elsif v_pre = 'akar_selatan' then
    a := game.mg_listen_arr(l -> 'dir_answers', (p ->> 'answers')::int);
    for i in 0 .. jsonb_array_length(a) - 1 loop
      t := game.mg_listen_int(a -> i -> 't_ms', 0, v_lim);
      if t < v_last then raise exception 'Catatan permainan tidak sah.'; end if; v_last := t;
      if game.mg_listen_int(a -> i -> 'd', 0, 7) = (p ->> 'target')::int then v_dir := true; v_idx := i; exit; end if;
    end loop;
    if v_dir and jsonb_array_length(a) > v_idx + 1 then raise exception 'Catatan permainan tidak sah.'; end if;
    b := game.mg_listen_arr(l -> 'taps', 2 * (p ->> 'beats')::int);
    if not v_dir then
      if jsonb_array_length(b) > 0 then raise exception 'Catatan permainan tidak sah.'; end if;
      return jsonb_build_object('won', false, 'arah', false, 'hits', 0);
    end if;
    v_t0 := game.mg_listen_int(l -> 't0_ms', v_last, v_lim);
    for i in 0 .. jsonb_array_length(b) - 1 loop
      t := game.mg_listen_int(b -> i -> 't_ms', v_last, v_lim);
      if i > 0 and t < (b -> (i - 1) ->> 't_ms')::bigint then raise exception 'Catatan permainan tidak sah.'; end if;
    end loop;
    v_hits := game.mg_listen_hits(b, v_t0, (p ->> 'interval_ms')::int, (p ->> 'beats')::int, (p ->> 'tol_ms')::int);
    return jsonb_build_object('won', v_hits >= (p ->> 'hits_needed')::int, 'arah', true, 'hits', v_hits);
  end if;
  raise exception 'Catatan permainan tidak sah.';
end $$;

-- =====================================================================
-- 0112 · S5 mini game "Susur Ombak" (kind = 'wave'), konsep 8.2
--
--   Tiga lajur, kapal melaju otomatis, ketuk kiri/kanan pindah satu lajur.
--   Lintasan (baris rintangan) DIBUAT SERVER di params.course; klien hanya menggambar.
--   Penilaian: simulasi tick 20 ms, bilangan bulat, identik dengan klien
--   (web/src/S5Ombak.html, blok S5OmbakNilai), diuji JS = SQL.
--   Preset: pelangi · pelangi_ulang · valkyrie · ular_muda · hafgufa · lari_biasa
--   hit/regen disetel lewat simulasi (bot acak kalah >= 99%, bot manusia-simulasi mendekati target 8.2).
--   Angka preset bisa disetel lewat game.config: S5Ombak_<preset>_<kunci> (mis. S5Ombak_valkyrie_hit).
-- Aman diulang.
-- =====================================================================

create or replace function game.mg_wave_bawaan() returns jsonb
language sql immutable as $$
  select '{
    "pelangi":       {"dur":28000,"lead":1800,"gap":1400,"jit":500,"wk":40,"wy":40,"wo":20,"p1":70,"hit":4500,"regen":3,"kulit":"pelangi","kejar":""},
    "pelangi_ulang": {"dur":18000,"lead":1800,"gap":1400,"jit":500,"wk":40,"wy":40,"wo":20,"p1":35,"hit":5500,"regen":2,"kulit":"pelangi","kejar":""},
    "valkyrie":      {"dur":32000,"lead":1500,"gap":1150,"jit":400,"wk":40,"wy":30,"wo":30,"p1":45,"hit":5500,"regen":5,"kulit":"laut","kejar":"valkyrie"},
    "ular_muda":     {"dur":30000,"lead":1500,"gap":1250,"jit":400,"wk":40,"wy":35,"wo":25,"p1":55,"hit":5500,"regen":5,"kulit":"laut","kejar":"ular"},
    "hafgufa":       {"dur":38000,"lead":1400,"gap":1050,"jit":350,"wk":30,"wy":20,"wo":50,"p1":50,"hit":5500,"regen":5,"kulit":"laut","kejar":"hafgufa"},
    "lari_biasa":    {"dur":25000,"lead":1500,"gap":1250,"jit":400,"wk":40,"wy":35,"wo":25,"p1":55,"hit":5500,"regen":2,"kulit":"laut","kejar":"monster"}
  }'::jsonb
$$;

create or replace function game.mg_wave_preset(p_preset text) returns jsonb
language plpgsql stable as $$
declare d jsonb := game.mg_wave_bawaan() -> p_preset; k text;
begin
  if d is null then return null; end if;
  for k in select jsonb_object_keys(d) loop
    if jsonb_typeof(d -> k) = 'number' then
      d := d || jsonb_build_object(k, floor(game.cfg_num('S5Ombak_' || p_preset || '_' || k, (d ->> k)::numeric))::int);
    end if;
  end loop;
  return d;
end $$;

-- Pembangkit lintasan (8.2): baris berurutan, tak tumpang tindih, selalu ada lajur aman yang terjangkau.
create or replace function game.mg_wave_course(p_dur int, p_gap int, p_jit int, p_wk int, p_wy int, p_wo int, p_p1 int) returns jsonb
language plpgsql volatile as $$
declare
  v_start int := 2500; v_tail int := 1500; t int; v_tersedia int; v_aman int := 1; i int := 0;
  v_out jsonb := '[]'::jsonb; r int; v_j text; v_len int; v_cand int[]; s int; v_non int[]; v_mask int; v_tot int := p_wk + p_wy + p_wo;
begin
  t := v_start; v_tersedia := v_start;
  loop
    r := game.rand_int(1, greatest(1, v_tot));
    v_j := case when r <= p_wk then 'k' when r <= p_wk + p_wy then 'y' else 'o' end;
    v_len := case v_j when 'k' then 500 when 'y' then 350 else 700 end;
    v_cand := array[]::int[];
    for s in 0 .. 2 loop
      if abs(s - v_aman) * 250 + 350 <= v_tersedia then v_cand := v_cand || s; end if;
    end loop;
    v_aman := v_cand[game.rand_int(1, array_length(v_cand, 1))];
    v_non := array(select x from unnest(array[0, 1, 2]) x where x <> v_aman order by x);
    if v_j = 'o' or game.rand_int(1, 100) > p_p1 then
      v_mask := (1 << v_non[1]) | (1 << v_non[2]);
    else
      v_mask := 1 << v_non[game.rand_int(1, 2)];
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('t', t, 'len', v_len, 'm', v_mask, 'j', v_j));
    i := i + 1;
    t := t + v_len;
    v_tersedia := p_gap + game.rand_int(0, greatest(0, p_jit));
    t := t + v_tersedia;
    exit when t + 700 > p_dur - v_tail or i >= 60;
  end loop;
  return v_out;
end $$;

create or replace function game.mg_wave_build(p_pid uuid, p_ctx text, p_preset text, p_assist int) returns jsonb
language plpgsql volatile as $$
declare d jsonb := game.mg_wave_preset(p_preset); v_hit int; v_regen int; v_awal boolean := false;
begin
  if d is null then raise exception 'Aksi tidak dikenal.'; end if;
  v_hit := (d ->> 'hit')::int; v_regen := (d ->> 'regen')::int;
  -- keringanan awal langkah kejaran: tiga percobaan pertama (tidak diumumkan)
  if p_preset = 'valkyrie' and p_ctx = 'quest' then
    v_awal := (select count(*) from game.mg_session where player_id = p_pid and kind = 'wave' and preset = 'valkyrie' and context = 'quest') < 3;
    if v_awal then v_hit := floor(v_hit * 0.7)::int; end if;
  end if;
  if p_assist >= 30 then v_hit := floor(v_hit * 0.6)::int; v_regen := greatest(v_regen + 1, floor(v_regen * 1.25)::int);
  elsif p_assist >= 15 then v_hit := floor(v_hit * 0.8)::int; end if;
  return jsonb_build_object('preset', p_preset, 'assist', p_assist, 'kulit', d ->> 'kulit', 'kejar', d ->> 'kejar',
    'dur', (d ->> 'dur')::int, 'tick', 20, 'lead', (d ->> 'lead')::int, 'gap_ms', 100, 'iframes', 800, 'daya_maks', 10000,
    'hit', v_hit, 'regen', v_regen,
    'course', game.mg_wave_course((d ->> 'dur')::int, (d ->> 'gap')::int, (d ->> 'jit')::int, (d ->> 'wk')::int, (d ->> 'wy')::int, (d ->> 'wo')::int, (d ->> 'p1')::int),
    'max_ms', (d ->> 'dur')::int + 5000, 'min_total_ms', 0);
end $$;

-- Simulasi baku (urutan tiap tick T = k*20): ketukan -> pulih -> tabrak -> kalah?
create or replace function game.mg_wave_judge(p jsonb, l jsonb, p_elapsed bigint) returns jsonb
language plpgsql stable as $$
declare
  v_dur int := (p ->> 'dur')::int; v_taps jsonb; n int; i int := 0; k int; T int;
  v_lane int := 1; v_lastmv bigint := -100000; v_daya int := (p ->> 'daya_maks')::int; v_max int := (p ->> 'daya_maks')::int;
  v_kebal int := 0; v_hit int := (p ->> 'hit')::int; v_regen int := (p ->> 'regen')::int; v_if int := (p ->> 'iframes')::int;
  c jsonb := p -> 'course'; v_nc int; r int := 0; v_rt int; v_rl int; v_hitrow int := -1; v_tabrak int := 0;
  v_t bigint; v_dir int; v_prev bigint := 0; v_won boolean := true; x jsonb; v_nl int;
begin
  v_taps := case when jsonb_typeof(l) = 'array' then l when jsonb_typeof(l) = 'object' then l -> 'taps' else null end;
  if coalesce(jsonb_typeof(v_taps), '') <> 'array' then raise exception 'Catatan permainan tidak sah.'; end if;
  n := jsonb_array_length(v_taps);
  if n > v_dur / 100 then raise exception 'Catatan permainan tidak sah.'; end if;
  for i in 0 .. n - 1 loop
    x := v_taps -> i;
    if coalesce(jsonb_typeof(x -> 't_ms'), '') <> 'number' or coalesce(jsonb_typeof(x -> 'dir'), '') <> 'number' then raise exception 'Catatan permainan tidak sah.'; end if;
    if (x ->> 't_ms')::numeric <> floor((x ->> 't_ms')::numeric) then raise exception 'Catatan permainan tidak sah.'; end if;
    v_t := (x ->> 't_ms')::bigint; v_dir := (x ->> 'dir')::numeric;
    if v_t < 0 or v_t > v_dur or v_t < v_prev or (x ->> 'dir') not in ('-1', '1') then raise exception 'Catatan permainan tidak sah.'; end if;
    v_prev := v_t;
  end loop;
  if n > 0 and v_prev > p_elapsed + 3000 then raise exception 'Catatan permainan tidak sah.'; end if;

  v_nc := jsonb_array_length(c); i := 0;
  for k in 0 .. v_dur / 20 - 1 loop
    T := k * 20;
    while i < n and ((v_taps -> i ->> 't_ms')::bigint) <= T loop
      v_t := (v_taps -> i ->> 't_ms')::bigint; v_nl := v_lane + (v_taps -> i ->> 'dir')::int;
      if v_t - v_lastmv >= 100 and v_nl between 0 and 2 then v_lane := v_nl; v_lastmv := v_t; end if;
      i := i + 1;
    end loop;
    v_daya := least(v_max, v_daya + v_regen);
    while r < v_nc and ((c -> r ->> 't')::int + (c -> r ->> 'len')::int) <= T loop r := r + 1; end loop;
    if T >= v_kebal and r < v_nc then
      v_rt := (c -> r ->> 't')::int; v_rl := (c -> r ->> 'len')::int;
      if v_rt <= T and T < v_rt + v_rl and ((c -> r ->> 'm')::int & (1 << v_lane)) <> 0 and v_hitrow <> r then
        v_daya := v_daya - v_hit; v_hitrow := r; v_kebal := T + v_if; v_tabrak := v_tabrak + 1;
      end if;
    end if;
    if v_daya <= 0 then v_won := false; exit; end if;
  end loop;
  if v_won and p_elapsed < v_dur - 3000 then raise exception 'Catatan permainan tidak sah.'; end if;
  return jsonb_build_object('won', v_won, 'tabrak', v_tabrak, 'daya', greatest(v_daya, 0));
end $$;

-- =====================================================================
-- Tide v55 — Hemat honor_state (performa, TANPA perubahan perilaku)
--
-- Masalah: game.honor_state() dipanggil di setiap api_getGameState.
-- Pengukuran: ia memakan ±28% waktu seluruh sub-fungsi getGameState.
-- Sebabnya perhitungan kembar, bukan query yang jelek:
--   * game.honor_tier_of / honor_tier_name / honor_tier_min masing-masing
--     memanggil game.honor_tiers(), dan honor_tiers() membaca game.config
--     lalu memparsing string setiap kali dipanggil.
--   * Di dalam honor_city_json rangkaian itu terjadi ±11 kali.
--   * honor_state mengulanginya untuk 8 pulau, DAN memanggil
--     honor_city_json dua kali untuk kota tempat pemain berdiri,
--     DAN honor_lot_max(t) dua kali.
--   Totalnya >100 baca game.config untuk satu getGameState.
--
-- Perubahan di sini HANYA menghapus perhitungan kembar:
--   * honor_city_json: honor_tiers() dipanggil 1× (dulu ±11×).
--   * honor_state: honor_city_json & honor_lot_max dipakai ulang.
-- Tidak ada cache, tidak ada trigger, tidak ada status yang bisa basi.
-- Keluaran JSON wajib identik -- dibuktikan di test/0070-hemat-honor.test.js
-- dengan membandingkan hasil migrasi s/d 0069 vs s/d 0070.
--
-- Tanda tangan fungsi tidak berubah. honor_city_json hanya dipakai di
-- honor_state. Aman diulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- honor_city_json: honor_tiers() sekali, bukan ±11 kali
-- Keluaran sama persis dengan versi 0038:
--   tier     = honor_tier_of(p_rep)
--   tierName = honor_tier_name(tier)            -> 'Tamu' bila tak ada
--   next     = honor_tier_min(tier + 1)         -> null bila tak ada
--   nextName = honor_tier_name(tier + 1) bila next tidak null
--   floor    = honor_tier_min(tier)             -> null untuk tier 0
-- ---------------------------------------------------------------------
create or replace function game.honor_city_json(p_pid uuid, p_city text, p_rep numeric) returns jsonb
language plpgsql stable as $$
declare
  v_arr jsonb := game.honor_tiers();        -- satu-satunya baca config di sini
  v_rep numeric := coalesce(p_rep, 0);
  v_tier int; v_next numeric; v_next_name text; v_tier_name text; v_floor numeric;
begin
  select coalesce(max((e ->> 'tier')::int), 0) into v_tier
    from jsonb_array_elements(v_arr) e where v_rep >= (e ->> 'min')::numeric;

  select coalesce(e ->> 'name', 'Tamu') into v_tier_name
    from jsonb_array_elements(v_arr) e where (e ->> 'tier')::int = v_tier;
  v_tier_name := coalesce(v_tier_name, 'Tamu');   -- tier 0 tidak ada di daftar

  select (e ->> 'min')::numeric into v_floor
    from jsonb_array_elements(v_arr) e where (e ->> 'tier')::int = v_tier;

  select (e ->> 'min')::numeric into v_next
    from jsonb_array_elements(v_arr) e where (e ->> 'tier')::int = v_tier + 1;

  if v_next is not null then
    select coalesce(e ->> 'name', 'Tamu') into v_next_name
      from jsonb_array_elements(v_arr) e where (e ->> 'tier')::int = v_tier + 1;
    v_next_name := coalesce(v_next_name, 'Tamu');
  end if;

  return jsonb_build_object(
    'id', p_city,
    'name', game.city_name(p_city),
    'rep', trim_scale(v_rep),
    'tier', v_tier,
    'tierName', v_tier_name,
    'next', v_next,
    'nextName', v_next_name,
    'floor', v_floor);
end $$;

-- ---------------------------------------------------------------------
-- honor_state: salinan versi 0038, dengan dua pemakaian ulang.
-- Perbedaan dari 0038 HANYA:
--   * v_cj  = honor_city_json(...) dihitung sekali per pulau
--   * v_lot = honor_lot_max(t) dihitung sekali untuk kota ini
-- Sisanya sama baris per baris.
-- ---------------------------------------------------------------------
create or replace function game.honor_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare v_me game.players; c text; r numeric; v_list jsonb := '[]'::jsonb; v_here jsonb; v_city text; t int;
  v_top jsonb; v_top_t int := 0; v_top_r numeric := -1; v_pel int := 0; v_tiers jsonb; v_unl jsonb;
  v_cj jsonb; v_lot int;
begin
  if p_pid is null or not game.fitur_on(p_pid, 'KehormatanOpen') then return null; end if;
  select * into v_me from game.players where player_id = p_pid;
  if not found or coalesce(v_me.archetype, '') = '' then return null; end if;
  v_city := game.current_city(p_pid);
  begin v_unl := game.player_unlocks(p_pid); exception when others then v_unl := '[]'::jsonb; end;
  foreach c in array game.honor_cities() loop
    r := game.honor_num(v_me.reputation, c);
    if r <= 0 and not game.honor_visible(p_pid, c, v_unl) then continue; end if;
    t := game.honor_tier_of(r);
    v_cj := game.honor_city_json(p_pid, c, r);          -- sekali, dipakai 2×
    v_list := v_list || jsonb_build_array(v_cj);
    if t = 5 then v_pel := v_pel + 1; end if;
    if t > v_top_t or (t = v_top_t and t > 0 and r > v_top_r) then
      v_top_t := t; v_top_r := r;
      v_top := jsonb_build_object('city', c, 'cityName', game.city_name(c), 'tier', t, 'tierName', game.honor_tier_name(t));
    end if;
    if c = v_city then
      v_lot := game.honor_lot_max(t);                   -- sekali, dipakai 2×
      v_here := v_cj || jsonb_build_object(
        'lotMax', v_lot, 'lotUsed', game.honor_lot_used(p_pid, c),
        'goods', case when v_lot > 0 then game.honor_lot_goods(p_pid, c) else '[]'::jsonb end);
    end if;
  end loop;
  select coalesce(jsonb_agg(t2 || jsonb_build_object('lots', game.honor_lot_max((t2 ->> 'tier')::int))), '[]'::jsonb)
    into v_tiers from jsonb_array_elements(game.honor_tiers()) t2;
  return jsonb_build_object(
    'tiers', v_tiers,
    'cities', v_list,
    'here', v_here,
    'top', v_top,
    'pelindung', v_pel,
    'pelindungAll', v_pel >= array_length(game.honor_cities(), 1),
    'boardMin', game.cfg_num('HonorBoardMin', 15),
    'lotResetMs', game.hr_reset_in_ms(),
    'unseen', coalesce((select jsonb_agg(jsonb_build_object('city', ht.city_id, 'cityName', game.city_name(ht.city_id),
                 'tier', ht.tier, 'tierName', game.honor_tier_name(ht.tier)) order by ht.at, ht.tier)
               from (select * from game.honor_tier where player_id = p_pid and not seen order by at, tier limit 12) ht), '[]'::jsonb),
    'notes', coalesce((select jsonb_agg(jsonb_build_object('id', hn.id, 'kind', hn.kind, 'city', hn.city_id,
                 'cityName', game.city_name(hn.city_id), 'data', hn.data) order by hn.id)
               from (select * from game.honor_note where player_id = p_pid and not seen order by id desc limit 10) hn), '[]'::jsonb));
end $$;

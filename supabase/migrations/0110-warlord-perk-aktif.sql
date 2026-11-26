-- =====================================================================
-- 0110 · Perk Warlord yang belum terasa: Palka, Lambung, Meriam  (Tide v89)
--   Sama seperti Mesin Jolt (0108), tiga komponen lain terpasang tetapi sebagian
--   efeknya tertelan batas/dasar hitungan lama:
--   - Palka Warlord: +15% dihitung dari kapasitas DASAR kapal (30 -> +5 saja), bukan
--     dari kapasitas efektif (dasar + upgrade, ±1.900). Sekarang +WarlordPalkaPct %
--     dari (dasar + bonus upgrade Cargo).
--   - Lambung Warlord: aus per layar -10% terpotong batas 60% total
--     (upgrade mentok 50% + Warlord 10% pas 60%; dengan buku Catatan Angin +30% semuanya terpotong).
--     Pemilik Lambung Warlord batasnya 70%.
--   - Meriam Warlord: +5% peluang kena terpotong batas peluang 92%.
--     Pemilik Meriam Warlord batasnya 97% (lihat game.voy_hit_max di 0003 & 0087).
--   Mesin Jolt Warlord diperbaiki di 0108.
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values ('WarlordPalkaPct', '15')
on conflict (key) do nothing;

do $$
begin
  drop function if exists game.voy_effective_stats_wp(uuid);
  alter function game.voy_effective_stats(uuid) rename to voy_effective_stats_wp;
  drop function if exists game.voy_decay_red_wp(uuid);
  alter function game.voy_decay_red(uuid) rename to voy_decay_red_wp;
end $$;
revoke all on function game.voy_effective_stats_wp(uuid) from public, anon, authenticated;
revoke all on function game.voy_decay_red_wp(uuid) from public, anon, authenticated;

-- Palka Warlord: persen dari kapasitas efektif (dasar + upgrade), menggantikan +15% dari dasar (0078)
create or replace function game.voy_effective_stats(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare j jsonb; v_cargo numeric; v_up numeric; v_pct numeric;
begin
  j := game.voy_effective_stats_wp(p_pid);
  begin
    if game.wl_has(p_pid, 'cargo') then
      select cargo into v_cargo from game.ships where player_id = p_pid;
      v_cargo := coalesce(v_cargo, 0);
      v_up := coalesce(game.voy_num(game.voy_player_upgrades(p_pid) -> 'cargo' -> 'accumulated'), 0);
      v_pct := greatest(0, game.cfg_num('WarlordPalkaPct', 15)) / 100;
      j := j || jsonb_build_object('cargoBonus',
        coalesce((j ->> 'cargoBonus')::numeric, 0) - round(v_cargo * 0.15) + round((v_cargo + v_up) * v_pct));
    end if;
  exception when others then null;
  end;
  return j;
end $$;

-- Lambung Warlord: batas pengurangan aus 60% -> 70% agar -10% benar-benar terasa
create or replace function game.voy_decay_red(p_pid uuid) returns numeric
language plpgsql stable as $$
begin
  if game.wl_has(p_pid, 'condition') then
    return least(70, coalesce((game.voy_effective_stats(p_pid) ->> 'decayReductionPercent')::numeric, 0)
      + case when game.ship_book_effect(p_pid, 'oto_angin') then 30 else 0 end);
  end if;
  return game.voy_decay_red_wp(p_pid);
end $$;

-- Garasi Warlord: teks efek Palka menampilkan tambahan kapasitas yang sebenarnya untuk pemain ini
do $$
begin
  drop function if exists game.wl_state_wp(uuid);
  alter function game.wl_state(uuid) rename to wl_state_wp;
end $$;
revoke all on function game.wl_state_wp(uuid) from public, anon, authenticated;

create or replace function game.wl_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare j jsonb := game.wl_state_wp(p_pid); v_cargo numeric; v_up numeric; v_n int;
begin
  if j is null or jsonb_typeof(j -> 'komponen') <> 'array' then return j; end if;
  select cargo into v_cargo from game.ships where player_id = p_pid;
  v_up := coalesce(game.voy_num(game.voy_player_upgrades(p_pid) -> 'cargo' -> 'accumulated'), 0);
  v_n := round((coalesce(v_cargo, 0) + v_up) * greatest(0, game.cfg_num('WarlordPalkaPct', 15)) / 100)::int;
  return j || jsonb_build_object('komponen',
    (select jsonb_agg(case when k ->> 'grup' = 'cargo'
        then k || jsonb_build_object('efek', 'Kapasitas palka +' || game.cfg_num('WarlordPalkaPct', 15)::int || '% (+' || v_n || ' muatan)')
        else k end order by o)
       from jsonb_array_elements(j -> 'komponen') with ordinality x(k, o)));
exception when others then return j;
end $$;

-- =====================================================================
-- 0111 · Meriam Warlord berlaku di Duel Lambung (PvP)  (Tide v89)
--   Sebelumnya (0087) pengali damage Meriam Warlord hanya di tempur laut vs NPC.
--   Duel Lambung memakai mesin sendiri: damage tembakan = f(dm) dari game.lb_power,
--   dipakai di fase taktis (server, lb_volley) DAN Pertarungan Terakhir (klien, volley()).
--   Karena keduanya membaca 'dm' dari lb_power, satu titik cukup:
--   pemilik Meriam Warlord -> dm x DuelMeriamWarlordKali (bawaan: sama dengan MeriamDmgWarlord = 5).
--   Kenop keseimbangan: game.config 'DuelMeriamWarlordKali' (turunkan bila duel terlalu timpang).
--   Serbuan Bersama & Perburuan Tony (mesin lain) tidak diubah.
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values ('DuelMeriamWarlordKali', '5')
on conflict (key) do nothing;

do $$
begin
  drop function if exists game.mp_fighter_wd(uuid);
  alter function game.mp_fighter(uuid) rename to mp_fighter_wd;
  drop function if exists game.lb_power_wd(jsonb);
  alter function game.lb_power(jsonb) rename to lb_power_wd;
end $$;
revoke all on function game.mp_fighter_wd(uuid) from public, anon, authenticated;
revoke all on function game.lb_power_wd(jsonb) from public, anon, authenticated;

-- fighter membawa penanda Meriam Warlord (disimpan di mp_duels.fa/fb saat tantangan dibuat)
create or replace function game.mp_fighter(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare j jsonb;
begin
  j := game.mp_fighter_wd(p_pid);
  if j is null then return j; end if;
  begin
    if game.wl_has(p_pid, 'cannons') then j := j || jsonb_build_object('wlCannons', true); end if;
  exception when others then null;
  end;
  return j;
end $$;

-- kekuatan di laut: damage meriam (dm) dikali untuk pemilik Meriam Warlord
create or replace function game.lb_power(f jsonb) returns jsonb
language plpgsql stable as $$
declare pw jsonb := game.lb_power_wd(f); k numeric;
begin
  if coalesce((f ->> 'wlCannons')::boolean, false) then
    k := greatest(1, game.cfg_num('DuelMeriamWarlordKali', game.cfg_num('MeriamDmgWarlord', 5)));
    pw := pw || jsonb_build_object('dm', round(((pw ->> 'dm')::numeric * k), 3));
    pw := jsonb_set(pw, '{src}', coalesce(pw -> 'src', '{}'::jsonb) || jsonb_build_object('wl', k));
  end if;
  return pw;
end $$;

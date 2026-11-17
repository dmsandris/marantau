-- =====================================================================
-- 0086 · Tide v66 — Rupa kapal per Tier + rupa Warlord
--   game.ship_visual menambah dua kunci (hanya rupa, tanpa angka tempur/ekonomi):
--     tier : Tier kapal 1..5 (rata-rata Level empat jalur upgrade, sama dengan
--            TierNum di ship_json tapi TIDAK ikut naik ke 6 saat Warlord lengkap)
--     wl   : komponen Warlord yang sudah terpasang, mis. ["cannons","speed"]
--   Keduanya ikut ke mp_presence.s lewat mp_touch, jadi kapten lain melihat
--   siluet dan rupa Warlord yang sama.
--   Pola bungkus: fungsi asli (0003) diganti nama menjadi ship_visual_inti,
--   lalu pembungkus dibuat dengan nama asli. Aman diulang.
-- =====================================================================

do $$
begin
  drop function if exists game.ship_visual_inti(uuid);
  alter function game.ship_visual(uuid) rename to ship_visual_inti;
end $$;
revoke all on function game.ship_visual_inti(uuid) from public, anon, authenticated;

create or replace function game.ship_visual(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare j jsonb; t int := 1; w text[] := '{}'::text[];
begin
  j := game.ship_visual_inti(p_pid);
  if j is null then return j; end if;
  begin
    t := greatest(1, least(5, coalesce(game.ship_tier_num(p_pid), 1)));
  exception when others then t := 1;
  end;
  begin
    w := coalesce(game.wl_set(p_pid), '{}'::text[]);
  exception when others then w := '{}'::text[];
  end;
  return j || jsonb_build_object('tier', t, 'wl', to_jsonb(w));
end $$;

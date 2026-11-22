-- =====================================================================
-- 0095 · Saga 4: pintu masuk bisa ditutup untuk pemain baru
--   Pemain yang sudah punya quest 'mahkota' tetap lolos walau MahkotaOpen = 0.
--   Pemain baru butuh MahkotaOpen = 1 (atau terdaftar di FiturPenguji).
--   Nilai MahkotaOpen diatur manual (jangan diubah di migrasi: semua migrasi dijalankan ulang tiap deploy).
-- Aman diulang.
-- =====================================================================
create or replace function game.mk_eligible(p_pid uuid) returns boolean
language plpgsql stable as $$
declare h int;
begin
  if p_pid is null then return false; end if;
  if game.mk_mulai(p_pid) then return true; end if;
  if not game.fitur_on(p_pid, 'MahkotaOpen') then return false; end if;
  if game.ps_step(p_pid, 'ps14') < 6 then return false; end if;
  if coalesce(game.pasir_era(p_pid), 'kini') <> 'kini' then return false; end if;
  h := game.mk_hari_saga3(p_pid);
  return h is not null and game.game_day() > h;
exception when others then return false;
end $$;

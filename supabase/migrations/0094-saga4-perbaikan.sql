-- =====================================================================
-- 0094 · Saga 4 perbaikan (laporan 20 Nov 2026)
--   * Zona Cukai 3 -> 4 pulau per hari game (MhZonaN). Nilai lama '3' dinaikkan sekali;
--     nilai lain (diatur GM) tidak disentuh.
--   * MkBatasHari  : maks percobaan per hari game untuk tempa Yaptob (langkah 15) dan balapan wajib menang
--                    lawan Pariopelan/KapalMber (langkah 16-17). Gagal sebanyak batas = tunggu hari game berikutnya. 0 = tanpa batas.
--   * MkOlehSutra  : oleh-oleh untuk Nenek Ulin sebelum teka-teki (langkah 20), default 10 Sutra.
-- Logika ada di api_mahkota (0079) dan daftar langkah (0093). Aman diulang.
-- =====================================================================
insert into game.config(key, value) values ('MkBatasHari', '2'), ('MkOlehSutra', '10')
on conflict (key) do nothing;

update game.config set value = '4' where key = 'MhZonaN' and value = '3';

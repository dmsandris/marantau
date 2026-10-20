-- =====================================================================
-- Marantau (Supabase) - 0029 BUKU LAUT JAUH (Tide v33)
-- 9 buku Tier VI, hanya dijual di Otoland, Gading Island, FreeYork. Harga 78.000-500.000.
-- Konsep: dokumen project claude/KONSEP-Buku-Laut-Jauh.md (v1.1)
--
-- Efek khusus dipasang di fungsi aslinya (semua lewat game.has_effect / game.ship_book_effect):
--   oto_angin   decay kondisi -30% (batas total 60%)        0003 voy_decay_red
--   oto_jaring  jatah mancing 30, pulih 45 dtk                0013 fish_qmax_p / fish_qsec_p
--   oto_kincir  waktu tempuh x0,9                             0003 ship_json TravelMul
--   gd_ramuan   reparasi -25%, +5% kondisi tiap merapat       0003/0028 voy_repair_quote, 0003 voy_complete_arrival
--   gd_lampion  jarahan bajak laut acak +30%                  0003 api_resolveCombat
--   gd_fajar    misi gubernur: gold +25%, Standing tujuan +2  0004 api_completeMission
--   fy_ukir     kondisi maksimum +30                          0003 voy_max_cond
--   fy_tungku   +8% tembak kena, +1 amunisi (PvE saja)        0003 api_resolveCombat / voy_enc_book
--   fy_rantai   tenggelam vs bajak laut acak: gold aman, muatan -20%   0003 api_resolveCombat
-- Efek kapal (angin, kincir, ramuan, ukir, tungku) tidak berlaku untuk Black Pearl.
-- Aman diulang.
-- =====================================================================

insert into game.book_catalog(book_id, name, tier, stat_effects, special_effect, price, source, sort) values
  -- Otoland - Rumah Juru Tulis (Pak Wiryo)
  ('bk_oto_angin',   'Catatan Angin Tanjung',        'VI', '{"Sailing":8,"Navigation":4}',                    'oto_angin',   78000, 'otoland',       60),
  ('bk_oto_jaring',  'Kitab Jaring Tujuh Simpul',    'VI', '{"Luck":6,"Knowledge":4}',                        'oto_jaring', 145000, 'otoland',       61),
  ('bk_oto_kincir',  'Hikayat Kincir Tua',           'VI', '{"Navigation":12,"Sailing":8}',                   'oto_kincir', 260000, 'otoland',       62),
  -- Gading Island - Toko Obat (Sinshe Tan)
  ('bk_gd_ramuan',   'Resep Ramuan Sinshe Tan',      'VI', '{"Knowledge":6,"Sailing":4}',                     'gd_ramuan',   95000, 'gading_island', 63),
  ('bk_gd_lampion',  'Lampion yang Tak Dibuang',     'VI', '{"Luck":10}',                                     'gd_lampion', 180000, 'gading_island', 64),
  ('bk_gd_fajar',    'Pintu Sebelum Matahari',       'VI', '{"Trading":12,"Negotiation":10}',                 'gd_fajar',   340000, 'gading_island', 65),
  -- FreeYork - Rumah Ukir (Pak Sapto)
  ('bk_fy_ukir',     'Buku Ukir Nama Kapal',         'VI', '{"Combat":6,"Sailing":4}',                        'fy_ukir',    120000, 'freeyork',      66),
  ('bk_fy_tungku',   'Kitab Tungku Dua Puluh Tahun', 'VI', '{"Combat":15}',                                   'fy_tungku',  230000, 'freeyork',      67),
  ('bk_fy_rantai',   'Rantai yang Dilepas',          'VI', '{"Combat":10,"Negotiation":10,"Luck":5}',         'fy_rantai',  500000, 'freeyork',      68)
on conflict (book_id) do update set name = excluded.name, tier = excluded.tier, stat_effects = excluded.stat_effects,
  special_effect = excluded.special_effect, price = excluded.price, source = excluded.source, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Rak Dalam: buku ketiga tiap pulau butuh dua buku Laut Jauh lain dari pulau yang sama
-- ---------------------------------------------------------------------
create or replace function game.blj_deep_books() returns text[]
language sql immutable as $$ select array['bk_oto_kincir', 'bk_gd_fajar', 'bk_fy_rantai'] $$;

create or replace function game.book_buy_block(p_pid uuid, p_book text) returns text
language plpgsql stable as $$
declare v_src text; v_need int; v_have int;
begin
  if not (p_book = any (game.blj_deep_books())) then return null; end if;
  select source into v_src from game.book_catalog where book_id = p_book;
  select count(*) into v_need from game.book_catalog
   where tier = 'VI' and source = v_src and book_id <> p_book;
  select count(*) into v_have from game.player_books pb join game.book_catalog c on c.book_id = pb.book_id
   where pb.player_id = p_pid and c.tier = 'VI' and c.source = v_src and c.book_id <> p_book;
  if v_have >= v_need then return null; end if;
  return case v_src
    when 'otoland' then 'Pak Wiryo menggeleng: "Yang ini untuk kapten yang sudah membaca dua buku lain di rak ini." (Rak Dalam: ' || v_have || '/' || v_need || ')'
    when 'gading_island' then 'Sinshe Tan menutup lemari: "Obat yang kuat diminum setelah dua yang ringan." (Rak Dalam: ' || v_have || '/' || v_need || ')'
    when 'freeyork' then 'Pak Sapto menahan buku itu: "Baca dulu dua yang lain di rak ini, Kapten." (Rak Dalam: ' || v_have || '/' || v_need || ')'
    else 'Buku ini masih di Rak Dalam. (' || v_have || '/' || v_need || ')' end;
end $$;

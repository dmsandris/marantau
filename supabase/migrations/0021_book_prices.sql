-- =====================================================================
-- Marantau (Supabase) - 0021 HARGA BUKU (Tide v24)
-- Rentang per tier:  I 300-1.500 | II 2.000-9.000 | III 10.000-35.000 | IV 40.000-70.000 | V 80.000-160.000
-- Urutan harga di dalam tier mengikuti harga lama (dipetakan linear). Nilai tetap -> aman diulang.
-- =====================================================================
update game.book_catalog c set price = v.price
from (values
  -- Tier I (lama 375-600)
  ('bk_knowledge_1', 300), ('bk_trading_1', 700), ('bk_negotiation_1', 700), ('bk_navigation_1', 700), ('bk_sailing_1', 700),
  ('bk_jj_harvest', 700), ('bk_su_etiquette', 850), ('bk_bj_ulin', 850), ('bk_sk_rantau', 850),
  ('bk_combat_1', 1100), ('bk_luck_1', 1500),
  -- Tier II (lama 1.350-1.650)
  ('bk_trading_2', 2000), ('bk_navigation_2', 2000), ('bk_negotiation_2', 2000), ('bk_combat_2', 3750),
  ('bk_su_ledger', 5500), ('bk_jj_monsoon', 5500), ('bk_bj_hunter', 5500), ('bk_sk_lapau', 5500), ('bk_ikn_archive', 5500),
  ('bk_treasure_decoder_1', 9000), ('bk_tg_dice', 9000), ('bk_tg_alley', 9000),
  -- Tier III (lama 2.400-3.750)
  ('bk_deep_hold', 10000), ('bk_black_market', 15500), ('bk_sea_lore', 21000),
  ('bk_treasure_decoder_2', 32000), ('bk_su_currency', 32000), ('bk_jj_stars', 32000),
  ('bk_bj_cannon', 35000), ('bk_sk_saudagar', 35000),
  -- Tier IV Paradiso (lama 10.500-15.000)
  ('bk_pd_fortune', 40000), ('bk_pd_tides', 50000), ('bk_pd_war', 50000), ('bk_pd_gold', 60000), ('bk_pd_sage', 70000),
  -- Tier V teknologi Marie Regal (lama 25.000-60.000)
  ('bk_mr_speech', 80000), ('bk_mr_plasma', 91000), ('bk_mr_quantum', 91000), ('bk_mr_hull', 137000), ('bk_mr_engine', 160000)
) as v(book_id, price)
where c.book_id = v.book_id;

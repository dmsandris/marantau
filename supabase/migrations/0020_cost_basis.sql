-- =====================================================================
-- Marantau (Supabase) - 0020 MODAL RATA-RATA (Tide v21)
-- * game.inventory.cost / game.warehouse.cost = total modal untuk qty yang
--   sedang dipegang (gold). NULL = tidak diketahui (barang lama sebelum v21).
-- * Keluar dari palka (jual, rampas, serah, titip) mengurangi modal secara
--   proporsional -> modal rata-rata per unit tetap sama.
-- * Pembelian (pasar, Bursa, pesanan yang dibatalkan) menambah modal.
-- * Titip/ambil gudang memindahkan modal bersama barangnya.
-- Aman diulang.
-- =====================================================================
-- Kolom, adjust_inventory, inv_add_cost dan inv_avg_cost ada di 0001b (dipakai modul awal); kolom paid di 0004.

create or replace function game.cargo_json(p_pid uuid) returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('commodityId', i.item_id, 'name', c.name, 'qty', i.qty, 'size', c.size,
      'avgCost', case when i.cost is not null then round(i.cost / i.qty, 2) end,
      'costTotal', case when i.cost is not null then round(i.cost) end)
    order by c.sort, c.id), '[]'::jsonb)
  from game.inventory i join game.commodities c on c.id = i.item_id
  where i.player_id = p_pid and i.qty > 0
$$;

create or replace function game.warehouse_json(p_pid uuid, p_city text) returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('commodityId', w.commodity_id,
      'name', coalesce(c.name, w.commodity_id), 'qty', w.qty, 'size', coalesce(c.size, 1),
      'avgCost', case when w.cost is not null then round(w.cost / w.qty, 2) end) order by c.sort nulls last, w.commodity_id), '[]'::jsonb)
  from game.warehouse w left join game.commodities c on c.id = w.commodity_id
  where w.player_id = p_pid and w.city_id = p_city and w.qty > 0
$$;

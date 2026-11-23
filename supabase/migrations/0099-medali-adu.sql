-- =====================================================================
-- 0099 · MEDALI ADU KAPTEN
--   Juara Adu Kapten (Selat Lurus / Sirkuit Zentul) mendapat 1 Medali.
--   Medali bisa ditukar (di lobi Adu):
--     25 Medali = 1 Gigi Jaring    (bahan Warlord)
--     35 Medali = 1 Rantai Biru    (bahan Warlord)
--     10 Medali = 1 Oli Hitam
--   Medali hanya diberikan bila kedua catatan masuk (bukan menang WO) dan
--   hanya sekali per adu. Angka-angka bisa diubah lewat game.config.
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('MedaliAdu', '1'), ('MedaliGigi', '25'), ('MedaliRantai', '35'), ('MedaliOli', '10')
on conflict (key) do nothing;

create table if not exists game.medali (
  player_id uuid primary key references game.players(player_id) on update cascade on delete cascade,
  jumlah    int not null default 0 check (jumlah >= 0),
  total     int not null default 0
);
alter table game.medali enable row level security;

-- Hadiah medali dipasang di atas penghitung adu: hanya saat transisi active -> done
-- dengan dua catatan masuk dan ada pemenang.
do $$
begin
  drop function if exists game.trek_adu_hitung_md(text);
  alter function game.trek_adu_hitung(text) rename to trek_adu_hitung_md;
end $$;
create or replace function game.trek_adu_hitung(p_id text) returns game.trek_duels
language plpgsql as $$
declare d game.trek_duels; v_awal text; v_n int := greatest(0, game.cfg_num('MedaliAdu', 1))::int; v_w uuid;
begin
  select status into v_awal from game.trek_duels where id = p_id;
  d := game.trek_adu_hitung_md(p_id);
  begin
    if v_awal = 'active' and d.status = 'done' and d.menang in ('a', 'b')
       and d.log_a is not null and d.log_b is not null and v_n > 0 then
      v_w := case when d.menang = 'a' then d.a_id else d.b_id end;
      insert into game.medali(player_id, jumlah, total) values (v_w, v_n, v_n)
        on conflict (player_id) do update set jumlah = game.medali.jumlah + v_n, total = game.medali.total + v_n;
    end if;
  exception when others then null;
  end;
  return d;
end $$;

create or replace function game.medali_jml(p_pid uuid) returns int
language sql stable as $$ select coalesce((select jumlah from game.medali where player_id = p_pid), 0) $$;

-- Lobi ikut membawa jumlah medali dan daftar tukar.
do $$
begin
  drop function if exists game.trek_adu_lobi_md(uuid);
  alter function game.trek_adu_lobi(uuid) rename to trek_adu_lobi_md;
end $$;
create or replace function game.trek_adu_lobi(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v jsonb;
begin
  v := game.trek_adu_lobi_md(p_pid);
  if v is null then return null; end if;
  return v || jsonb_build_object('medali', game.medali_jml(p_pid),
    'tukar', jsonb_build_object('gigi', game.cfg_num('MedaliGigi', 25)::int,
                                'rantai', game.cfg_num('MedaliRantai', 35)::int,
                                'oli', game.cfg_num('MedaliOli', 10)::int),
    'warlord', game.wl_buka(p_pid));
end $$;

-- ---------------------------------------------------------------------
-- api_medali(['tukar', 'gigi'|'rantai'|'oli', jumlah=1])
-- ---------------------------------------------------------------------
create or replace function public.api_medali(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_act text := coalesce(game.arg(a, 0), 'tukar'); v_what text := game.arg(a, 1);
  v_n int; v_harga int; v_cost int; v_item text; v_max int; v_muat numeric; v_sisa int;
begin
  if not game.trek_adu_boleh(v_id) then raise exception 'Medali baru terbuka bagi yang sudah menamatkan Mahkota Selat.'; end if;
  if v_act <> 'tukar' then raise exception 'Aksi tidak dikenal.'; end if;
  v_n := coalesce(nullif(game.arg(a, 2), '')::int, 1);
  if v_n < 1 or v_n > 20 then raise exception 'Jumlah tukar tidak wajar.'; end if;
  if v_what not in ('gigi', 'rantai', 'oli') then raise exception 'Barang itu tidak ditukar dengan medali.'; end if;
  v_harga := greatest(1, game.cfg_num(case v_what when 'gigi' then 'MedaliGigi' when 'rantai' then 'MedaliRantai' else 'MedaliOli' end,
                                      case v_what when 'gigi' then 25 when 'rantai' then 35 else 10 end))::int;
  v_cost := v_harga * v_n;

  insert into game.medali(player_id) values (v_id) on conflict do nothing;
  perform 1 from game.medali where player_id = v_id for update;
  if game.medali_jml(v_id) < v_cost then
    raise exception 'Medalimu kurang: butuh % medali, kau punya %.', v_cost, game.medali_jml(v_id);
  end if;

  if v_what in ('gigi', 'rantai') then
    if not game.wl_buka(v_id) then raise exception 'Bahan Warlord belum diperlukan: selesaikan Mahkota Selat sampai tahap Warlord dulu.'; end if;
    v_item := case v_what when 'gigi' then 'qi_mk_gigi' else 'qi_mk_rantai' end;
    v_max := greatest(0, game.cfg_num('WarlordDropMax', 12))::int;
    if game.item_qty(v_id, v_item) + v_n > v_max then
      raise exception 'Kau hanya boleh menyimpan % % sekaligus.', v_max, case v_what when 'gigi' then 'Gigi Jaring' else 'Rantai Biru' end;
    end if;
    if game.cargo_free(v_id) < v_n then raise exception 'Muatan kapal penuh. Kosongkan ruang dulu.'; end if;
    perform game.item_adjust(v_id, v_item, v_n);
  else
    v_muat := coalesce((select size from game.commodities where id = 'oli_hitam'), 1);
    if game.cargo_free(v_id) < v_n * v_muat then raise exception 'Muatan kapal penuh. Kosongkan ruang dulu.'; end if;
    perform game.adjust_inventory(v_id, 'oli_hitam', v_n);
  end if;

  update game.medali set jumlah = jumlah - v_cost where player_id = v_id;
  v_sisa := game.medali_jml(v_id);
  return jsonb_build_object('ok', true, 'barang', v_what, 'jumlah', v_n, 'medali', v_sisa);
end $$;
select game.expose('api_medali');

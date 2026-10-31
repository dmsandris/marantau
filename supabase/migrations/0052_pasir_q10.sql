-- =====================================================================
-- 0052 — Pasir · Batch 2: Quest 10 "Penumpang Bergaun Putih" (Tide v41)
-- Skenario: claude/SKENARIO-Saga3-Dark.md bagian 8.
--
-- Langkah (game.player_quests, quest_id = 'ps10'):
--   1  Festival di Bawah Menara (merapat di IKN saat malam). Mata Pesta -> 'pesta'; titipan -> 'terima'
--   2  Titipan Penumpang diterima: bawa Nyonya Z. ke Pulau em pe'er de pe'er
--   3  Berlayar bersama (pelayaran ditutup sinematik geladak; 'jawab' = riak jawab_malam)
--   4  Tiba di em pe'er de pe'er: bayaran 20.000 gold; perpisahan -> 'pisah'
--   5  Bebas di pulau. Set sail berikutnya (ke mana pun) -> 'jam' (klien), server menolak berangkat
--   6  Lonceng Jam Agung: sinematik 999 anak tangga -> 'curi' = pv_ambil (harta ke potret, era keadilan)
--   7  Benang yang Putus (tayangan wajib) -> 'paham'
--   8  Hari Pertama, Sekali Lagi (Sunda Empire) -> 'catatan' (Catatan Pelayaran di kabin)
--   9  Tur Bukti: Skitraw, TooGood, IKN + kapal putih di laut (pelayaran pertama setelah 2 bukti)
--  10  Bukti lengkap: Paman Ocid di Pustaka Sunda -> 'ocid'
--  11  Selesai
--
-- Selama era bukan 'kini' (Zaman Keadilan dst.) kisah lama tidak pernah terjadi untuk pemain ini:
--   * key quest lama + gotong + pacu di api_getGameState dikirim null (0010)
--   * endpoint quest lama & Pacu Dagang ditolak di gerbang pre-request (mt_pre_request)
--   * kait quest lama (berlayar, bos, kedatangan) dilewati; TooGood tidak merdeka; kota pemulih mati
--
-- ⚠️ quest_on_sail, quest_boss_encounter, quest_arrival_redirect, heal_city, toogood_freed,
--    hr_hook, mt_pre_request di sini adalah SALINAN versi terakhir + penjaga Pasir.
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values ('PasirQ10Bayar', '20000') on conflict (key) do nothing;

create or replace function game.ps_kini(p_pid uuid) returns boolean
language sql stable as $$ select game.pasir_era(p_pid) = 'kini' $$;

-- ---------------------------------------------------------------------
-- Kisah lama dimatikan selama era bukan 'kini'
-- ---------------------------------------------------------------------
create or replace function game.toogood_freed(p_pid uuid) returns boolean
language sql stable as $$ select game.ps_kini(p_pid) and game.tg_step(p_pid) >= 10 $$;

-- salinan 0032 + penjaga
create or replace function game.heal_city(p_pid uuid, p_city text) returns boolean
language sql stable as $$
  select game.ps_kini(p_pid) and (p_city = 'paradiso' or (p_city = 'toogood' and game.toogood_freed(p_pid))
      or (p_city = 'pusaran' and game.bx_step(p_pid) between 7 and 15)
      or (p_city = 'ikn' and exists (select 1 from game.gr_projects where id = 'ikn' and done_at is not null)))
$$;

-- ---------------------------------------------------------------------
-- Pemicu Quest 10: merapat di IKN saat malam (dipanggil saat tiba & saat state dibaca)
-- ---------------------------------------------------------------------
create or replace function game.ps10_try_start(p_pid uuid) returns void
language plpgsql as $$
begin
  if game.ps_step(p_pid, 'ps10') > 0 then return; end if;
  if not game.pasir_aktif(p_pid) or game.in_transit(p_pid) then return; end if;
  if game.current_city(p_pid) is distinct from 'ikn' or not game.fish_is_night() then return; end if;
  perform game.pasir_ensure(p_pid);
  perform game.ps_set(p_pid, 'ps10', 1, '{}'::jsonb);
end $$;

-- Tiba di pelabuhan (dari hr_hook 'arrive')
create or replace function game.ps_on_arrive(p_pid uuid, p_city text) returns void
language plpgsql as $$
declare s int; d jsonb; b jsonb; n int; v_pay bigint;
begin
  perform game.ps10_try_start(p_pid);
  s := game.ps_step(p_pid, 'ps10');
  if s = 3 then
    if p_city = 'empeer_depeer' then
      v_pay := game.cfg_num('PasirQ10Bayar', 20000)::bigint;
      update game.players set gold = gold + v_pay where player_id = p_pid;
      perform game.ps_set(p_pid, 'ps10', 4, jsonb_build_object('bayar', v_pay));
      perform game.log(p_pid, 'Nyonya Z. tiba di Pulau em pe''er de pe''er dan membayar ' || v_pay || ' gold.');
    else
      perform game.ps_set(p_pid, 'ps10', 2, '{}'::jsonb);   -- penumpang masih di kapal
    end if;
  elsif s = 9 then
    d := game.ps_data(p_pid, 'ps10');
    b := coalesce(d -> 'bukti', '{}'::jsonb);
    select count(*) into n from jsonb_object_keys(b) k where k in ('skitraw', 'toogood', 'ikn');
    if n >= 2 and not (b ? 'laut') then b := b || jsonb_build_object('laut', game.now_ms()); end if;
    if p_city in ('skitraw', 'toogood', 'ikn') and not (b ? p_city) then b := b || jsonb_build_object(p_city, game.now_ms()); end if;
    perform game.ps_set(p_pid, 'ps10', 9, jsonb_build_object('bukti', b));
    if (b ? 'skitraw') and (b ? 'toogood') and (b ? 'ikn') and (b ? 'laut') then
      perform game.ps_set(p_pid, 'ps10', 10, '{}'::jsonb);
    end if;
  end if;
end $$;

-- Berangkat
create or replace function game.ps_on_sail(p_pid uuid, p_origin text, p_dest text) returns void
language plpgsql as $$
declare s int := game.ps_step(p_pid, 'ps10');
begin
  if s = 5 and p_origin = 'empeer_depeer' then
    raise exception 'Lonceng Jam Agung berdentang sumbang di puncak bukit. Burung-burung terbang ke arah yang salah.';
  end if;
  if s = 6 then raise exception 'Jam Agung masih berdentang. Kau belum boleh pergi.'; end if;
  if s = 2 and p_dest = 'empeer_depeer' then perform game.ps_set(p_pid, 'ps10', 3, '{}'::jsonb); end if;
end $$;

-- Kedatangan dibelokkan/diam: pelayaran bersama Nyonya Z. & bukti TooGood tanpa bajak laut
create or replace function game.ps_arrival_redirect(p_pid uuid, p_origin text, p_dest text) returns jsonb
language plpgsql as $$
declare s int := game.ps_step(p_pid, 'ps10'); d jsonb;
begin
  if s = 3 and p_dest = 'empeer_depeer' then
    return jsonb_build_object('city', p_dest, 'quiet', true, 'kind', 'ps_geladak');
  end if;
  if s = 9 and p_dest = 'toogood' then
    d := game.ps_data(p_pid, 'ps10');
    if not coalesce(d -> 'bukti', '{}'::jsonb) ? 'toogood' then
      return jsonb_build_object('city', p_dest, 'quiet', true, 'kind', 'ps_gap',
        'message', 'Kapal merah-hitam berukir emas memotong haluanmu, lalu melambat. Dari geladaknya seseorang tertawa: "Kapal sekecil itu? Rampas apanya. Lewat sana, Kapten Gagak."');
    end if;
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------------
-- Kait inti (salinan 0028 + Pasir)
-- ---------------------------------------------------------------------
create or replace function game.quest_on_sail(p_pid uuid, p_origin text, p_dest text) returns void
language plpgsql as $$
begin
  perform game.mp_sail_guard(p_pid);
  perform game.ps_on_sail(p_pid, p_origin, p_dest);
  if not game.ps_kini(p_pid) then return; end if;
  perform game.ww_on_sail(p_pid, p_origin, p_dest);
  perform game.bx_on_sail(p_pid, p_origin, p_dest);
  perform game.kp_on_sail(p_pid, p_origin, p_dest);
  perform game.ts_on_sail(p_pid, p_origin, p_dest);
  perform game.lt_on_sail(p_pid, p_origin, p_dest);
end $$;

create or replace function game.quest_arrival_redirect(p_pid uuid, p_origin text, p_dest text) returns jsonb
language plpgsql as $$
declare r jsonb := game.ps_arrival_redirect(p_pid, p_origin, p_dest);
begin
  if r is not null or not game.ps_kini(p_pid) then return r; end if;
  return coalesce(game.kp_arrival_redirect(p_pid, p_origin, p_dest), game.lt_arrival_redirect(p_pid, p_origin, p_dest));
end $$;

create or replace function game.quest_boss_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql as $$
begin
  if not game.ps_kini(p_pid) then return null; end if;
  return coalesce(game.gala_boss_encounter(p_pid, p_dest), game.tg_hunter_encounter(p_pid, p_dest),
                  game.ww_encounter(p_pid, p_dest), game.bx_encounter(p_pid, p_dest),
                  game.ts_hunter_encounter(p_pid, p_dest), game.lt_encounter(p_pid, p_dest));
end $$;

-- salinan 0051 + kedatangan Pasir
create or replace function game.hr_hook(p_pid uuid, p_kind text, p_amount numeric, p_ctx jsonb) returns void
language plpgsql as $$
begin
  if p_pid is null then return; end if;
  if game.fitur_on(p_pid, 'HarianOpen') then
    begin
      perform game.hr_event(p_pid, p_kind, p_amount, coalesce(p_ctx, '{}'::jsonb));
    exception when others then raise warning '[harian] % %: %', p_kind, p_pid, sqlerrm;
    end;
  end if;
  if p_kind = 'sell' and game.fitur_on(p_pid, 'PacuOpen') and game.pasir_era(p_pid) = 'kini' then
    begin
      perform game.pd_on_sell(p_pid, p_amount, coalesce(p_ctx, '{}'::jsonb));
    exception when others then raise warning '[pacu] %: %', p_pid, sqlerrm;
    end;
  end if;
  if p_kind = 'arrive' then
    begin
      perform game.ks_on_event(p_pid, p_kind, coalesce(p_ctx, '{}'::jsonb));
    exception when others then raise warning '[kisah] %: %', p_pid, sqlerrm;
    end;
    begin
      perform game.ps_on_arrive(p_pid, p_ctx ->> 'city');
    exception when others then raise warning '[pasir] tiba %: %', p_pid, sqlerrm;
    end;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Gerbang pre-request (salinan 0039_reset_sandi + Pasir): kisah lama & Pacu Dagang tertutup di era lain
-- ---------------------------------------------------------------------
create or replace function game.ps_blocked_path(p_path text) returns text
language plpgsql stable as $$
begin
  if coalesce(p_path, '') ~ 'rpc/api_pacu$' then
    return 'Pacu Dagang kini diselenggarakan Dewan Pajak Keadilan. Hanya saudagar terdaftar yang boleh ikut. Nama Kapten tidak ada di daftar.';
  end if;
  if coalesce(p_path, '') ~ 'rpc/(api_galaquest|api_toogoodquest|api_warwerwor|api_barsati|api_kompas|api_cocoepan|api_tigasilang|api_limatangan|api_duatangan|api_dtraid)$' then
    return 'Tak seorang pun di sini mengenal kisah itu, Kapten.';
  end if;
  return null;
end $$;

create or replace function public.mt_pre_request() returns void
language plpgsql security definer set search_path = game, public as $$
declare v_block text; v_path text; v_info jsonb; v_u text; v_msg text; v_pid uuid;
begin
  begin
    v_path := lower(coalesce(current_setting('request.path', true), ''));
    if game.maint_active() then
      if v_path ~ 'rpc/(api_ping|api_gmstatus)$' then return; end if;
      if not game.is_gm(auth.uid()) then v_info := game.maint_info(); v_block := 'maint'; end if;
    end if;
    if v_block is null and auth.uid() is not null then
      v_u := lower(split_part(coalesce(auth.email(), ''), '@', 1));
      if v_u <> '' and exists (select 1 from game.pw_must_change where username = v_u)
         and v_path !~ 'rpc/(api_ping|api_gmstatus|api_pwstatus|api_pwchanged|api_authwhoami|api_legacyclaim|api_legacycheck)$' then
        v_block := 'pw';
      end if;
    end if;
  exception when others then
    return;   -- gagal-terbuka: jangan pernah mematikan game karena gerbang ini error
  end;
  if v_block = 'maint' then
    raise sqlstate 'PGRST' using
      message = json_build_object('code', 'MT_MAINT', 'message', 'Maintenis dulu ya gaes, kembali sebentar lagi.',
                                  'details', coalesce(v_info, '{}'::jsonb)::text)::text,
      detail = json_build_object('status', 503, 'status_text', 'Maintenance')::text;
  elsif v_block = 'pw' then
    raise sqlstate 'PGRST' using
      message = json_build_object('code', 'MT_PWCHANGE', 'message', 'Pasang sandi baru dulu, Kapten.', 'details', '{}')::text,
      detail = json_build_object('status', 403, 'status_text', 'Password change required')::text;
  end if;
  -- Pasir: hanya diperiksa untuk endpoint kisah lama / Pacu Dagang (satu baris pasir_state)
  begin
    v_msg := game.ps_blocked_path(v_path);
    if v_msg is not null then
      v_pid := auth.uid();
      if v_pid is null or game.pasir_era(v_pid) = 'kini' then v_msg := null; end if;
    end if;
  exception when others then
    v_msg := null;
  end;
  if v_msg is not null then raise exception '%', v_msg; end if;
end $$;
revoke all on function public.mt_pre_request() from public;
grant execute on function public.mt_pre_request() to anon, authenticated;

-- ---------------------------------------------------------------------
-- Status untuk klien: + langkah & data quest (tanpa angka harta apa pun)
-- ---------------------------------------------------------------------
create or replace function game.ps_q_json(p_pid uuid, p_q text) returns jsonb
language sql stable as $$
  select case when q.player_id is null then null else jsonb_build_object('step', q.step, 'done', q.done_at is not null,
    'd', q.data - 'bayar') end
  from (select 1) x left join game.player_quests q on q.player_id = p_pid and q.quest_id = p_q
$$;

create or replace function game.pasir_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare r game.pasir_state; v_gm boolean; s int;
begin
  if not game.pasir_aktif(p_pid) then return null; end if;
  perform game.ps10_try_start(p_pid);
  -- cadangan bila kait kedatangan terlewat
  s := game.ps_step(p_pid, 'ps10');
  if s = 3 and not game.in_transit(p_pid) then perform game.ps_on_arrive(p_pid, game.current_city(p_pid)); end if;
  select * into r from game.pasir_state where player_id = p_pid;
  v_gm := game.is_gm(p_pid);
  if not found and not v_gm then return null; end if;
  return jsonb_build_object(
    'era', coalesce(r.era, 'kini'),
    'tone', game.pasir_tone(coalesce(r.era, 'kini')),
    'retak', coalesce(r.retak, 0),
    'kaca', coalesce(r.kaca, 0),
    'kacaMax', game.cfg_num('PasirKaca', 7)::int,
    'riak', coalesce(r.riak, '{}'::jsonb),
    'night', game.fish_is_night(),
    'q', jsonb_build_object('10', game.ps_step(p_pid, 'ps10'), '11', game.ps_step(p_pid, 'ps11'),
      '12', game.ps_step(p_pid, 'ps12'), '13', game.ps_step(p_pid, 'ps13'), '14', game.ps_step(p_pid, 'ps14')),
    'q10', game.ps_q_json(p_pid, 'ps10')
  ) || case when v_gm then jsonb_build_object('gm', true,
          'eras', (select jsonb_agg(jsonb_build_object('era', e, 'tone', game.pasir_tone(e))) from unnest(game.pasir_eras()) e))
        else '{}'::jsonb end;
end $$;

-- ---------------------------------------------------------------------
-- Endpoint: api_pasir(aksi, ...)
-- ---------------------------------------------------------------------
create or replace function public.api_pasir(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_act text := lower(coalesce(game.arg(a, 0), 'status')); v_arg text := game.arg(a, 1);
  v_me game.players; v_pid uuid; v_res jsonb; s int; d jsonb; v_city text;
begin
  v_me := game.me(v_act not in ('status'));
  v_pid := v_me.player_id;
  if coalesce(v_me.archetype, '') = '' or not game.pasir_aktif(v_pid) then raise exception 'Aksi tidak dikenal.'; end if;

  if v_act = 'status' then
    return jsonb_build_object('pasir', game.pasir_state(v_pid));
  elsif v_act = 'gm' then
    if not game.is_gm(v_pid) then raise exception 'Aksi tidak dikenal.'; end if;
    v_res := game.pasir_admin(v_pid, game.arg(a, 1), game.arg(a, 2), game.arg(a, 3));
    return jsonb_build_object('gm', v_res, 'pasir', game.pasir_state(v_pid));
  end if;

  s := game.ps_step(v_pid, 'ps10');
  d := game.ps_data(v_pid, 'ps10');
  v_city := game.current_city(v_pid);
  if v_act = 'pesta' then
    if s <> 1 then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.ps_set(v_pid, 'ps10', 1, jsonb_build_object('pesta', true));
  elsif v_act = 'terima' then
    if s <> 1 or not coalesce((d ->> 'pesta')::boolean, false) then raise exception 'Aksi tidak dikenal.'; end if;
    if game.in_transit(v_pid) or v_city <> 'ikn' then raise exception 'Nyonya Z. menunggu di dermaga IKN.'; end if;
    perform game.ps_set(v_pid, 'ps10', 2, '{}'::jsonb);
    perform game.log(v_pid, 'Menerima titipan penumpang: Nyonya Z., pelukis peta, ke Pulau em pe''er de pe''er.');
  elsif v_act = 'jawab' then
    if s not in (3, 4) or coalesce(v_arg, '') not in ('pernah', 'tidak') then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.pasir_ensure(v_pid);
    update game.pasir_state set riak = riak || jsonb_build_object('jawab_malam', v_arg), updated_at = now() where player_id = v_pid;
    perform game.ps_set(v_pid, 'ps10', s, jsonb_build_object('jawab', v_arg));
  elsif v_act = 'pisah' then
    if s <> 4 or not (d ? 'jawab') then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.ps_set(v_pid, 'ps10', 5, jsonb_build_object('pisah', coalesce(v_arg, '')));
  elsif v_act = 'jam' then
    if s <> 5 or game.in_transit(v_pid) or v_city <> 'empeer_depeer' then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.ps_set(v_pid, 'ps10', 6, '{}'::jsonb);
  elsif v_act = 'curi' then
    if s <> 6 then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.pv_ambil(v_pid, 'sunda_empire');
    update game.pasir_state set data = data || jsonb_build_object('buka', '[]'::jsonb), kaca = greatest(kaca, 1), updated_at = now()
     where player_id = v_pid;
    perform game.ps_set(v_pid, 'ps10', 7, '{}'::jsonb);
  elsif v_act = 'paham' then
    if s <> 7 then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.ps_set(v_pid, 'ps10', 8, '{}'::jsonb);
  elsif v_act = 'catatan' then
    if s <> 8 then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.ps_set(v_pid, 'ps10', 9, jsonb_build_object('bukti', '{}'::jsonb));
  elsif v_act = 'ocid' then
    if s <> 10 then raise exception 'Aksi tidak dikenal.'; end if;
    if game.in_transit(v_pid) or v_city <> 'sunda_empire' then raise exception 'Lelaki tua itu menunggu di Pustaka Sunda.'; end if;
    perform game.ps_set(v_pid, 'ps10', 11, '{}'::jsonb, true);
    perform game.log(v_pid, 'Bertemu Paman Ocid di Pustaka Sunda. Seorang penjaga jam tanpa jam, seorang kapten tanpa kisah.');
  else
    raise exception 'Aksi tidak dikenal.';
  end if;
  return jsonb_build_object('pasir', game.pasir_state(v_pid), 'newGold', (select gold from game.players where player_id = v_pid));
end $$;
select game.expose('api_pasir');

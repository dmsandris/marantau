-- =====================================================================
-- Marantau - 0088 BUKU ADEGAN (penanda "adegan sudah dilihat" dicadangkan di server)
-- ---------------------------------------------------------------------
-- Konsep: claude/KONSEP-Penanda-Adegan-di-Server.md
-- Masalah: penanda adegan hanya di localStorage. Hapus data situs / ganti browser -> sinematik & dialog
-- otomatis tampil ulang. Progres quest tidak pernah hilang (ada di server); yang hilang penanda tampilan.
--
-- Lapis 1 (server, file ini):
--   game.player_seen (player_id, k, v)  k = kunci localStorage APA ADANYA (sudah memuat username / nama kapten)
--                                       v = nilainya ('1' untuk penanda; beberapa modul menyimpan angka/JSON kecil)
--   api_seenMark([[k, v] | k, ...], [k hapus, ...])   upsert berkelompok, idempotent
--   api_getGameState(..., 'seen')        -> kunci 'seen' = { k: {kunci: nilai}, g: penjaga boot } (0010)
-- Lapis 2-3 (klien): web/mt-supabase.js
--
-- Batas: hanya pola yang diizinkan (game.seen_ok), kunci <= 96, nilai <= 2000 karakter,
--        maks 3.000 kunci per pemain, maks 200 kunci per panggilan.
-- Rahasia: hanya kunci milik pemain itu sendiri yang dikirim balik (Saga 3 tetap tertutup).
-- Pola kunci modul baru WAJIB ditambahkan ke game.seen_ok DAN ke SEEN_RE di web/mt-supabase.js.
-- =====================================================================

create table if not exists game.player_seen (
  player_id uuid not null references game.players(player_id) on delete cascade on update cascade,
  k         text not null,
  v         text not null default '1',
  at        timestamptz not null default now(),
  primary key (player_id, k)
);
revoke all on game.player_seen from public, anon, authenticated;

-- Penjaga boot (Lapis 3) hanya untuk kapten yang sudah ada sebelum Buku Adegan rilis.
-- Kapten baru selalu mulai dengan penanda yang langsung tercadang, jadi tidak butuh penjaga.
insert into game.config(key, value) values
  ('SeenGuardSebelum', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
  ('SeenMaksKunci', '3000')
on conflict (key) do nothing;

create or replace function game.seen_ok(p_k text) returns boolean
language sql immutable as $$
  select p_k is not null and length(p_k) between 3 and 96
     and p_k ~ '^((bx|ww|kp|cb|ts|lt|dt|ps|pd):|th_|mt_pr_|mt_trek_|mt_seen_)'
$$;

-- Status untuk api_getGameState: semua penanda milik pemain + penjaga boot.
-- g = true bila server belum punya cadangan apa pun DAN kapten dibuat sebelum rilis.
create or replace function game.seen_state(p_pid uuid) returns jsonb
language plpgsql stable security definer set search_path = game, public as $$
declare v_k jsonb; v_cut timestamptz; v_created timestamptz;
begin
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) into v_k from game.player_seen where player_id = p_pid;
  if v_k <> '{}'::jsonb then return jsonb_build_object('k', v_k, 'g', false); end if;
  begin v_cut := game.cfg('SeenGuardSebelum')::timestamptz; exception when others then v_cut := null; end;
  select created_at into v_created from game.players where player_id = p_pid;
  return jsonb_build_object('k', v_k, 'g', coalesce(v_created < v_cut, false));
end $$;

create or replace function public.api_seenMark(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_pid uuid := (game.me()).player_id;
  v_set jsonb := game.arg_json(a, 0);
  v_del jsonb := game.arg_json(a, 1);
  v_max int := coalesce(nullif(game.cfg('SeenMaksKunci'), '')::int, 3000);
  v_have int; e jsonb; v_k text; v_v text; v_n int := 0; v_skip int := 0; v_hapus int := 0;
begin
  if v_pid is null then raise exception 'Kapten belum dibuat.'; end if;
  if v_set is null or jsonb_typeof(v_set) <> 'array' then v_set := '[]'::jsonb; end if;
  if v_del is null or jsonb_typeof(v_del) <> 'array' then v_del := '[]'::jsonb; end if;
  if jsonb_array_length(v_set) + jsonb_array_length(v_del) > 200 then
    raise exception 'Terlalu banyak penanda sekaligus (maks 200).';
  end if;

  -- hapus dulu (mis. GM mengosongkan data uji modulnya)
  for e in select * from jsonb_array_elements(v_del) loop
    if jsonb_typeof(e) = 'string' and game.seen_ok(e #>> '{}') then
      delete from game.player_seen where player_id = v_pid and k = e #>> '{}';
      if found then v_hapus := v_hapus + 1; end if;
    end if;
  end loop;

  select count(*) into v_have from game.player_seen where player_id = v_pid;
  for e in select * from jsonb_array_elements(v_set) loop
    if jsonb_typeof(e) = 'string' then v_k := e #>> '{}'; v_v := '1';
    elsif jsonb_typeof(e) = 'array' and jsonb_typeof(e -> 0) = 'string' then
      v_k := e ->> 0; v_v := coalesce(e ->> 1, '1');
    else v_skip := v_skip + 1; continue;
    end if;
    if not game.seen_ok(v_k) or length(v_v) > 2000 then v_skip := v_skip + 1; continue; end if;
    update game.player_seen set v = v_v, at = now() where player_id = v_pid and k = v_k and v is distinct from v_v;
    if found then v_n := v_n + 1; continue; end if;
    if exists (select 1 from game.player_seen where player_id = v_pid and k = v_k) then continue; end if;
    if v_have >= v_max then v_skip := v_skip + 1; continue; end if;
    insert into game.player_seen(player_id, k, v) values (v_pid, v_k, v_v) on conflict (player_id, k) do nothing;
    if found then v_have := v_have + 1; v_n := v_n + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'n', v_n, 'hapus', v_hapus, 'lewat', v_skip);
end $$;
select game.expose('api_seenmark');

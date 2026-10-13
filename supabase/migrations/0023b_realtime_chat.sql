-- =====================================================================
-- Marantau (Supabase) - 0023b REALTIME CHAT
-- Server sudah menyiarkan pesan lewat realtime.send(..., private = true) (0005 mp_rt):
--   chat:global · chat:city:<cityId> · player:<pub> (kotak masuk & duel)
-- Kanal privat butuh izin baca di realtime.messages (Realtime Authorization).
-- Pemain login boleh mendengar chat dunia & chat pelabuhan, dan HANYA kanal player:<pub> miliknya.
-- Aman diulang. Di lingkungan tanpa skema realtime.messages (tes lokal) bagian kebijakan dilewati.
-- =====================================================================

create or replace function public.mt_rt_can_read(p_topic text) returns boolean
language plpgsql stable security definer set search_path = game, public as $$
declare v_pub text;
begin
  if auth.uid() is null or p_topic is null then return false; end if;
  if p_topic = 'chat:global' or p_topic like 'chat:city:%' then return true; end if;
  if p_topic like 'player:%' then
    select pub into v_pub from game.mp_presence where player_id = auth.uid();
    return v_pub is not null and p_topic = 'player:' || v_pub;
  end if;
  return false;
end $$;
revoke all on function public.mt_rt_can_read(text) from public;
revoke all on function public.mt_rt_can_read(text) from anon;
grant execute on function public.mt_rt_can_read(text) to authenticated;

do $$
begin
  if to_regclass('realtime.messages') is not null then
    execute 'drop policy if exists "marantau baca siaran" on realtime.messages';
    execute 'create policy "marantau baca siaran" on realtime.messages for select to authenticated '
         || 'using (realtime.messages.extension = ''broadcast'' and public.mt_rt_can_read(realtime.topic()))';
  end if;
exception when others then
  -- Jangan gagalkan deploy: tanpa kebijakan ini klien tetap jalan lewat pulse (polling) sebagai cadangan.
  raise warning 'Kebijakan realtime.messages tidak terpasang: %', sqlerrm;
end $$;

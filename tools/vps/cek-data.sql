-- Sidik data untuk Fase 3: dijalankan di Supabase DAN VM, hasilnya harus sama persis.
-- Hanya angka (jumlah baris, total), tidak ada data pribadi -> aman tampil di log repo publik.
with t(nama) as (values
  ('auth.users'), ('auth.identities'), ('auth.sessions'), ('auth.refresh_tokens'),
  ('game.players'), ('game.ships'), ('game.inventory'), ('game.warehouse'), ('game.player_location'),
  ('game.player_quests'), ('game.player_missions'), ('game.kongsi'), ('game.kd_owned'), ('game.mp_chat'),
  ('game.mp_inbox'), ('game.pasir_state'))
select nama, (xpath('/row/c/text()', query_to_xml('select count(*) as c from ' || nama, false, true, '')))[1]::text
from t where to_regclass(nama) is not null
union all select 'sum gold', coalesce(sum(gold), 0)::text from game.players
union all select 'sum bank', coalesce(sum(bank_balance), 0)::text from game.players
union all select 'sum utang', coalesce(sum(debt_balance), 0)::text from game.players
union all select 'sum keping', coalesce(sum(keping), 0)::text from game.players
order by 1;

-- 1. Lihat struktur tabel lobi/race Pacu Selat
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_schema = 'game' 
  AND table_name ILIKE '%pacu%' OR table_name ILIKE '%race%' OR table_name ILIKE '%selat%'
ORDER BY table_name, ordinal_position;

# Porting Marantau: Apps Script → Supabase (Postgres)

## Tujuan
Server game lama (Google Apps Script, file `.gs` di `legacy-gs/`) dipindah ke Postgres (Supabase)
sebagai fungsi SQL/plpgsql. Browser (client lama `JavaScript.html`, di `/home/claude/mt/`) TIDAK
diubah logikanya: setiap panggilan `google.script.run.api_xxx(arg0, arg1, ...)` akan dialihkan oleh
shim ke `supabase.rpc('api_xxx', { a: [arg0, arg1, ...] })`.

**Maka: nama fungsi, urutan argumen, perilaku, pesan error (bahasa Indonesia), dan BENTUK JSON jawaban
harus sama persis dengan versi `.gs`.** Cek cara client memakai jawaban di `/home/claude/mt/JavaScript.html`
(grep nama `api_xxx`) bila ragu soal bentuk.

## Struktur
- `supabase/migrations/0001_foundation.sql` — schema `game`, tabel inti, helper, seed kota/pasar/config. (JANGAN DIUBAH)
- `supabase/migrations/0001b_interfaces.sql` — fungsi kontrak antar-modul (versi stub). (JANGAN DIUBAH)
- `supabase/migrations/0002_economy.sql`   — Modul A
- `supabase/migrations/0003_voyage.sql`    — Modul B
- `supabase/migrations/0004_missions_items.sql` — Modul C
- `supabase/migrations/0005_multiplayer.sql` — Modul D
- `supabase/migrations/0010_state.sql` — (koordinator) api_getGameState, api_pollVoyage, api_getCityBundle
- `test/harness.js` — Postgres lokal (PGlite) + tiruan Supabase Auth. Baca komentarnya.
- `test/000X_*.test.js` — tes per modul. Jalankan: `node test/0002_economy.test.js`

Setiap modul HANYA menulis file migrasinya sendiri + file tesnya sendiri. Jangan ubah file lain.
Kalau butuh sesuatu dari modul lain yang belum ada di `0001b_interfaces.sql`, tulis versi minimal
di file SENDIRI dengan nama berawalan modulmu (mis. `game.eco_...`) atau laporkan ke koordinator.

## Konvensi wajib
1. Tabel & helper di schema `game`. Endpoint di `public`:
   ```sql
   create or replace function public.api_buy(a jsonb default '[]'::jsonb) returns jsonb
   language plpgsql security definer set search_path = game, public as $$
   declare v_city text := game.arg(a, 0); v_comm text := game.arg(a, 1); v_qty bigint := game.arg_int(a, 2);
   ...
   $$;
   select game.expose('api_buy');          -- true sebagai arg ke-2 = boleh tanpa login
   ```
   Nama fungsi di Postgres otomatis huruf kecil (`api_buy`, `api_getmarket`) — shim menurunkan huruf.
   Panggil `game.expose('<nama huruf kecil>')` untuk setiap endpoint.
2. Identitas pemain: `v_me game.players := game.me(true);` (true = kunci baris pemain FOR UPDATE —
   pakai untuk aksi yang mengubah gold/cargo supaya tidak balapan). `v_me.player_id` = uuid.
   Error tanpa login otomatis: `AUTH_REQUIRED: ...`.
3. Error untuk pemain: `raise exception 'Gold tidak cukup. Butuh %, kamu punya %.', x, y;` — pesan sama dengan `.gs`.
4. Gunakan `plpgsql` (bukan `language sql`) untuk fungsi yang menyentuh tabel modul lain.
5. Semua fungsi transaksi berjalan dalam 1 transaksi Postgres → `LockService` diganti `select ... for update`.
   CacheService/PropertiesService diganti tabel biasa.
6. Waktu: `game.game_day()`, `game.minutes_to_next_day()`, `now()`, `game.iso(ts)` untuk string ISO.
7. Acak: `random()`, `game.rand_int(lo, hi)`. Deterministik per string: `game.seeded(seed, n)` (0..1).
8. Konfigurasi: `game.cfg_num('Key', fallback)`, `game.cfg('Key')`. Tambah default config baru dengan
   `insert into game.config ... on conflict do nothing`.
9. Log pemain: `perform game.log(pid, 'pesan');`
10. Gold: ubah lewat `update game.players set gold = ... where player_id = ...` (dalam transaksi terkunci).
11. Inventory (komoditas & item): `game.inventory(player_id, item_id, qty)`; ubah via `game.adjust_inventory(pid, item, delta)`
    (error "Jumlah cargo tidak boleh negatif." bila minus).
12. Kota: `game.city(id)` → JSON bentuk lama (`CityId, Name, Type, ...`), `game.city_name(id)`, `game.cities_json()`.
13. Idempoten: migrasi harus bisa dijalankan ulang (`create table if not exists`, `create or replace`,
    `insert ... on conflict do nothing`). Aktifkan RLS untuk tabel baru:
    `alter table game.x enable row level security;` (tanpa policy = tertutup untuk browser).
14. Angka di JSON: pakai tipe angka (bukan string). Tanggal: string ISO seperti `.gs` (`game.iso`).

## Kontrak antar-modul (0001b) — pemilik wajib menimpa dengan implementasi asli
| fungsi | pemilik | arti |
|---|---|---|
| `game.adjust_inventory(pid, item, delta)` | A | (sudah final) |
| `game.cargo_total(pid)` | A | total unit komoditas di palka + `game.mission_load(pid)` |
| `game.reputation_for(pid, city)` | A | standing pemain di kota |
| `game.stats_json(pid)` | A | objek stat `{Trading,...}` atau null |
| `game.quote_buy(pid, city, commodity)` | A | harga beli per unit untuk pemain ini (0 = tidak dijual) |
| `game.bank_state(pid)` | A | sama dengan `BankService.getState` (termasuk proses bunga) |
| `game.current_city(pid)`, `game.in_transit(pid)` | B | lokasi |
| `game.effective_cargo(pid)` | B | kapasitas palka efektif (buku/artifact/upgrade) |
| `game.ship_json(pid)` | B | sama dengan `ShipService.getShip` (termasuk field efektif) |
| `game.voyage_state(pid)` | B | sama dengan `LocationService.getVoyageState` |
| `game.resolve_arrival_if_due(pid)` | B | sama dengan `LocationService.resolveArrivalIfDue` |
| `game.apply_condition_delta(pid, delta)` | B | ubah kondisi kapal (dibatasi max efektif) |
| `game.city_event(city)` | B | event kota aktif (bentuk `WorldEventService.getActiveEventForCity`) atau null |
| `game.mission_load(pid)`, `game.mission_state(pid)` | C | muatan misi terkunci / state misi (v8) |
| `game.has_effect(pid, effect)` | C | buku special effect ATAU artifact terpasang |
| `game.treasure_drop(pid, enemy_level)` | C | kemungkinan drop peta harta saat menang combat; kembalikan objek loot (`{name,...}` seperti `.gs`) atau null |
| `game.mp_touch(pid)`, `game.mp_mark_sea(pid, dest)` | D | kehadiran pemain |

## Pembagian modul
- **A — Economy (0002)**: CharacterService (create/delete character, stats), ArchetypeData (data + `api_getArchetypes`,
  `api_createCharacter` dengan nama unik & appearance), MarketService (v8 overstock: tabel `game.market_glut`,
  `api_getMarket`, `api_buy`, `api_sell`), CargoService (`api_getCargo`, `api_getCargoState` dengan `missionLoad`),
  WarehouseService, BankService, BookService + seed BookCatalog (`api_getLibrary`, `api_buyBook`),
  `api_getCharacterStats`, `api_getLeaderboard`, AppearanceStore (`api_saveAppearance`, kolom `players.appearance`),
  MetaStore (`api_saveMeta`, kolom `players.meta`), `api_deleteCharacter`.
- **B — Ship, Voyage, Combat, World Events (0003)**: ShipService (efektif), ShipUpgradeService (katalog, upgrade,
  repair, decay), LocationService (sail options, set sail, voyage state, arrival + voyage event + decay + world event roll),
  CombatService (encounter roll, multi-round `api_resolveCombat`), WorldEventService, `api_getShipState`,
  `api_getShipUpgrades`, `api_shipUpgrade`, `api_getRepairQuote`, `api_repairShip`, `api_getSailOptions`, `api_setSail`.
- **C — Missions v8 + Items + Treasure (0004)**: MissionService (versi TERBARU v8 di `legacy-gs/MissionService.gs`:
  Titipan/Pesanan, muatan terkunci, `api_buyForMission`), ItemService (katalog + seed, artifact 2 slot, toko peta,
  jual item), TreasureService + TreasureData, `api_getItems`, `api_getMissionState`, dll.
- **D — Multiplayer (0005)**: `legacy-gs/MultiplayerService.gs` + endpoint `api_mp*`/`api_mg*` di `legacy-gs/Code.gs`.
  Ganti CacheService dengan tabel (kehadiran, chat, inbox, duel, rekor PvP, order Bursa, cooldown mancing/dadu).
  Id publik pemain untuk client: jangan bocorkan uuid mentah ke pemain lain (pakai kode acak per pemain, mis. kolom
  `pub` di tabel kehadiran). Pertahankan semua aturan (escrow taruhan, timeout AFK 25s/60s, 3x diam = kalah,
  undangan 60s, batas 6 order, dll.).

## Tes
- Pakai `test/harness.js`. Contoh ada di `test/0001_foundation.test.js`.
- Muat hanya migrasi yang diperlukan supaya tidak terganggu modul lain yang sedang dikerjakan:
  `create({ only: f => /^(0001|0002)/.test(f) })`.
- Porting skenario dari tes lama di `/home/claude/gasemu/test_mp.js`, `test_timeout.js`, `test_v8.js` yang relevan.
- Tes harus mencetak `... TESTS PASSED` di akhir dan keluar dengan kode 0.
- Untuk waktu (voyage/timeout): `H.shiftTime(ms)` menggeser jam dunia & timestamp voyage; untuk kasus lain
  update kolom timestamp langsung lewat `H.sql(...)`.

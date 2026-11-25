// S5 fondasi (0105): gerbang, aturan titian, pagar dunia seberang, presence, harian, pencegatan, kerangka mg_session.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  // fraksi hari (dari awal hari 0)
  const clock = f => H.sql(`select game.cfg_set('WorldStartTimestamp', (game.now_ms() - ($1::numeric * game.cfg_num('GameDayLengthRealMinutes', 60) * 60000)::bigint)::text)`, [f]);

  await H.sql(`select game.cfg_set('GmUsernames', 's5_gm'), game.cfg_set('S5MgJedaMs', '0')`);
  const G = await H.user('s5_gm'); await G.call('api_createCharacter', ['Juru Uji', 'merchant']);
  const A = await H.user('s5_ana'); await A.call('api_createCharacter', ['Kapten Ana', 'merchant']);
  const B = await H.user('s5_budi'); await B.call('api_createCharacter', ['Kapten Budi', 'merchant']);
  const seberang = (u, on) => H.sql(`insert into game.s5_state(player_id, dunia) values ($1, $2) on conflict (player_id) do update set dunia = excluded.dunia`, [u.id, on ? 'seberang' : 'mare']);

  // ---------- Gerbang ----------
  await H.expectError(() => G.call('api_mg_start', ['uji', 'quest', 'satu']), /Aksi tidak dikenal/);
  await H.sql(`select game.cfg_set('FiturPenguji', 's5_gm,s5_ana')`);
  ok((await one(`select game.s5_on($1) v`, [G.id])).v === true, 'penguji GM terbuka');
  ok((await one(`select game.s5_on($1) v`, [B.id])).v === false, 'Budi belum');
  ok((await one(`select game.s5_dunia($1) v`, [A.id])).v === 'mare', 'dunia bawaan mare');
  ok((await one(`select game.s5_city('s5_p1') a, game.s5_city('bjorneo') b, game.s5_city(null) c`)).a === true, 's5_city');

  // ---------- Aturan titian (K3/K4) ----------
  await clock(10.5);   // hari 10, siang
  let r = (await one(`select game.s5_bisa_seberang($1) v`, [A.id])).v;
  ok(r.ok === true, 'belum pernah menyeberang -> boleh');
  await H.sql(`select game.s5_catat_seberang($1, 'seberang')`, [A.id]);
  ok((await one(`select game.s5_dunia($1) v`, [A.id])).v === 'seberang', 'catat -> seberang');
  r = (await one(`select game.s5_bisa_seberang($1) v`, [A.id])).v;
  ok(r.ok === false && r.alasan === 'hari' && r.menit > 0 && /hari berikutnya/.test(r.pesan), 'pulang di hari yang sama ditolak: ' + JSON.stringify(r));
  ok((await one(`select (game.s5_bisa_seberang($1, true)) ->> 'ok' v`, [A.id])).v === 'true', 'pengecualian langkah pulang terakhir');
  await clock(10.97);  // menit terakhir hari 10
  ok((await one(`select (game.s5_bisa_seberang($1)) ->> 'ok' v`, [A.id])).v === 'false', 'masih hari yang sama');
  await clock(11.01);  // menit pertama hari 11
  ok((await one(`select (game.s5_bisa_seberang($1)) ->> 'ok' v`, [A.id])).v === 'true', 'hari berikutnya boleh (kapan saja)');
  await H.sql(`select game.s5_catat_seberang($1, 'mare')`, [A.id]);
  ok((await one(`select game.s5_dunia($1) v, cross_n from game.s5_state where player_id = $1`, [A.id])).cross_n === 2, 'hitungan penyeberangan');
  await H.expectError(() => H.sql(`select game.s5_catat_seberang($1, 'bulan')`, [A.id]), /tidak dikenal/);
  ok((await one(`select game.s5_menit_label(130) a, game.s5_menit_label(25) b, game.s5_menit_label(60) c`)).a === '2 jam 10 menit', 'label menit');

  // Tiket titian berlaku hari itu sampai dipakai
  ok((await one(`select game.s5_tiket_berlaku($1) v`, [A.id])).v === false, 'tanpa tiket');
  await H.sql(`update game.s5_state set tiket_day = game.game_day() where player_id = $1`, [A.id]);
  ok((await one(`select game.s5_tiket_berlaku($1) v`, [A.id])).v === true, 'tiket hari ini');
  await H.sql(`select game.s5_catat_seberang($1, 'seberang')`, [A.id]);
  ok((await one(`select game.s5_tiket_berlaku($1) v`, [A.id])).v === false, 'tiket habis setelah berhasil menyeberang');
  await H.sql(`update game.s5_state set tiket_day = game.game_day() - 1 where player_id = $1`, [A.id]);
  ok((await one(`select game.s5_tiket_berlaku($1) v`, [A.id])).v === false, 'tiket kemarin hangus');

  // ---------- Pagar dunia seberang (pre-request) ----------
  const pre = async (u, fn) => {
    await H.sql(`select set_config('request.jwt.claim.sub', $1, false), set_config('request.jwt.claim.email', $2, false), set_config('request.path', $3, false)`,
      [u ? u.id : '', u ? u.email : '', '/rpc/' + fn]);
    return H.sql(`select public.mt_pre_request()`);
  };
  await seberang(A, false);
  await pre(A, 'api_buy');   // di Mare semua jalan
  await seberang(A, true);
  const tolak = ['api_buy', 'api_sell', 'api_bankDeposit', 'api_bankWithdraw', 'api_bankBorrow', 'api_bankRepay', 'api_warehouseStore',
    'api_warehouseWithdraw', 'api_mpBuyOrder', 'api_mpPostOrder', 'api_mpGift', 'api_sellItem', 'api_buyBook', 'api_mgFishCast',
    'api_mpDuelChallenge', 'api_mpDuelRespond', 'api_trekDuel', 'api_trek', 'api_tonyHunt', 'api_tonyRaid', 'api_kongsi', 'api_kasino',
    'api_digTreasure', 'api_buyTreasureMap', 'api_acceptMission', 'api_getMissionBoard', 'api_completeMission', 'api_pacu',
    'api_harian', 'api_kedai', 'api_getMarket', 'api_resolveCombat', 'api_mahkota', 'api_pasir', 'api_peregrin', 'api_gotong',
    'api_sembarang_baru_2027'];
  for (const fn of tolak) await H.expectError(() => pre(A, fn.toLowerCase()), /di seberang titian/);
  const izin = ['api_ping', 'api_getgamestate', 'api_getcitybundle', 'api_mppulse', 'api_mpchat', 'api_mppm', 'api_setsail', 'api_pollvoyage',
    'api_repairship', 'api_shipupgrade', 'api_mg_start', 'api_mg_finish', 'api_s5', 'api_gmstatus'];
  for (const fn of izin) await pre(A, fn);
  await pre(null, 'api_buy');                                    // tanpa login: bukan urusan pagar ini
  await H.sql(`select set_config('request.path', '/', false)`); await H.sql(`select public.mt_pre_request()`);
  await pre(B, 'api_buy');                                       // pemain lain di Mare tidak tersentuh
  await seberang(G, true); await H.expectError(() => pre(G, 'api_buy'), /di seberang titian/);   // GM tetap dipagari
  await seberang(G, false);
  // pagar lama tetap jalan: pemeliharaan
  await H.sql(`select game.cfg_set('MaintenanceMode', '1')`);
  await H.expectError(() => pre(B, 'api_buy'), /MT_MAINT|Maintenis/);
  await H.sql(`select game.cfg_set('MaintenanceMode', '0')`);
  // Sapu: setiap api_* yang ada di database & tidak ada di daftar izin ditolak
  const semua = (await H.sql(`select distinct lower(proname) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
                              where s.nspname = 'public' and proname ilike 'api\\_%'`)).map(x => x.n);
  let nTolak = 0;
  for (const fn of semua) {
    const boleh = (await one(`select game.s5_rpc_izin($1) v`, [fn])).v;
    if (boleh) { await pre(A, fn); continue; }
    await H.expectError(() => pre(A, fn), /di seberang titian/); nTolak++;
  }
  ok(nTolak >= 85, 'sapu RPC: ' + nTolak + ' dari ' + semua.length + ' ditolak');

  // ---------- Presence tersamar ----------
  await H.sql(`update game.player_location set city_id = 'bjorneo', destination_city_id = null, depart_at = null, arrive_at = null where player_id = $1`, [A.id]);
  await A.call('api_mpPulse', []);
  let p = await one(`select c, sea, dest from game.mp_presence where player_id = $1`, [A.id]);
  ok(p && p.c === '' && p.sea === true && p.dest === '', 'presence di seberang tersamar: ' + JSON.stringify(p));
  await B.call('api_mpPulse', []);
  p = await one(`select c from game.mp_presence where player_id = $1`, [B.id]);
  ok(p && p.c !== '', 'presence pemain Mare normal');
  await seberang(A, false); await A.call('api_mpPulse', []);
  ok((await one(`select c from game.mp_presence where player_id = $1`, [A.id])).c === 'bjorneo', 'kembali ke Mare -> presence normal');

  // ---------- Harian & pencegatan (fungsi dalam diganti penghitung) ----------
  await H.sql(`create table if not exists public.t_hit(nama text)`);
  await H.sql(`create or replace function game.hr_hook_s5(p_pid uuid, p_kind text, p_amount numeric, p_ctx jsonb) returns void language sql as $$ insert into public.t_hit values ('hr') $$`);
  await H.sql(`create or replace function game.kd_enc_s5(p_pid uuid, p_enc jsonb) returns jsonb language plpgsql as $$ begin insert into public.t_hit values ('kd'); return p_enc; end $$`);
  await H.sql(`create or replace function game.voy_roll_encounter_s5(p_pid uuid, p_dest text) returns jsonb language plpgsql as $$ begin insert into public.t_hit values ('roll'); return '{"kind":"pirate"}'::jsonb; end $$`);
  const hits = async (n) => num((await one(`select count(*) c from public.t_hit where nama = $1`, [n])).c);
  const num = v => Number(v);
  await H.sql(`select game.hr_hook($1, 'arrive', 1, '{}'::jsonb)`, [A.id]);
  ok(await hits('hr') === 1, 'harian di Mare dihitung');
  await seberang(A, true);
  await H.sql(`select game.hr_hook($1, 'arrive', 1, '{}'::jsonb)`, [A.id]);
  ok(await hits('hr') === 1, 'K9: harian di seberang tidak dihitung');
  // pelayaran di seberang
  await H.sql(`update game.player_location set destination_city_id = 's5_p2' where player_id = $1`, [A.id]);
  ok((await one(`select game.voy_roll_encounter($1, 's5_p2') v`, [A.id])).v === null && await hits('roll') === 0, 'tanpa bajak laut acak di seberang');
  ok((await one(`select game.kd_enc($1, '{"kind":"pirate","level":3}'::jsonb) v`, [A.id])).v === null && await hits('kd') === 0, 'rantai Tony/Navy/Cukai tidak disentuh');
  const enc = (await one(`select game.kd_enc($1, '{"kind":"monster","s5":"kraken_muda"}'::jsonb) v`, [A.id])).v;
  ok(enc && enc.s5 === 'kraken_muda', 'pencegatan S5 lolos');
  // tujuan seberang walau status dunia belum tercatat (kapal di titian)
  await seberang(A, false);
  ok((await one(`select game.kd_enc($1, '{"kind":"pirate"}'::jsonb) v`, [A.id])).v === null, 'tujuan s5_* cukup untuk memagari');
  await H.sql(`update game.player_location set destination_city_id = 'joungjava' where player_id = $1`, [A.id]);
  ok((await one(`select game.kd_enc($1, '{"kind":"pirate"}'::jsonb) v`, [A.id])).v !== null && await hits('kd') === 1, 'Mare normal');
  ok((await one(`select game.voy_roll_encounter($1, 'joungjava') v`, [A.id])).v !== null && await hits('roll') === 1, 'roll Mare normal');
  await H.sql(`update game.player_location set destination_city_id = null where player_id = $1`, [A.id]);

  // ---------- Kerangka mg_session ----------
  await H.expectError(() => A.call('api_mg_start', ['uji', 'quest', 'satu']), /Belum ada yang menunggu/);     // uji hanya GM
  await H.expectError(() => G.call('api_mg_start', ['hantu', 'quest', 'satu']), /Aksi tidak dikenal/);
  await H.expectError(() => G.call('api_mg_start', ['uji', 'pasar', 'satu']), /Aksi tidak dikenal/);
  await H.expectError(() => G.call('api_mg_start', ['uji', 'quest', 'Satu Dua!']), /Aksi tidak dikenal/);
  let s1 = await G.call('api_mg_start', ['uji', 'quest', 'satu']);
  ok(s1.session_id && s1.params.target >= 1 && s1.params.assist === 0, 'start: sesi + params');
  const s2 = await G.call('api_mg_start', ['uji', 'quest', 'satu']);
  ok((await one(`select status from game.mg_session where id = $1`, [s1.session_id])).status === 'expired', 'start baru -> sesi lama gugur');
  ok(num((await one(`select count(*) c from game.mg_session where player_id = $1 and status = 'open'`, [G.id])).c) === 1, 'satu sesi open');
  let f = await G.call('api_mg_finish', [s1.session_id, { n: s1.params.target }]);
  ok(f.status === 'expired' && f.replay === true, 'sesi gugur tidak bisa dimenangkan');
  await H.expectError(() => A.call('api_mg_finish', [s2.session_id, { n: 1 }]), /Sesi tidak dikenal/);   // sesi orang lain
  await H.expectError(() => G.call('api_mg_finish', ['bukan-uuid', {}]), /Sesi tidak dikenal/);
  await H.expectError(() => G.call('api_mg_finish', [s2.session_id, { x: 1 }]), /tidak sah/);
  ok((await one(`select status from game.mg_session where id = $1`, [s2.session_id])).status === 'open', 'log tidak sah: sesi tetap open');
  const salah = s2.params.target === 9 ? 1 : s2.params.target + 1;
  f = await G.call('api_mg_finish', [s2.session_id, { n: salah }]);
  ok(f.status === 'lost' && f.result.won === false, 'kalah');
  const f2 = await G.call('api_mg_finish', [s2.session_id, { n: s2.params.target }]);
  ok(f2.status === 'lost' && f2.replay === true, 'finish ganda -> hasil sama');
  // bantuan: 2 kalah -> 15, 4 kalah -> 30, menang -> 0
  const kalahSekali = async () => { const s = await G.call('api_mg_start', ['uji', 'quest', 'satu']); await G.call('api_mg_finish', [s.session_id, { n: s.params.target === 9 ? 1 : s.params.target + 1 }]); return s; };
  let s3 = await kalahSekali();   // 2 kalah
  s3 = await G.call('api_mg_start', ['uji', 'quest', 'satu']);
  ok(s3.params.assist === 15, 'bantuan tingkat 1 setelah 2 kalah');
  await G.call('api_mg_finish', [s3.session_id, { n: s3.params.target === 9 ? 1 : s3.params.target + 1 }]);   // 3
  await kalahSekali();                                                                                        // 4
  s3 = await G.call('api_mg_start', ['uji', 'quest', 'satu']);
  ok(s3.params.assist === 30, 'bantuan tingkat 2 setelah 4 kalah');
  ok((await G.call('api_mg_start', ['uji', 'quest', 'dua'])).params.assist === 0, 'bantuan per preset');
  s3 = await G.call('api_mg_start', ['uji', 'quest', 'satu']);
  f = await G.call('api_mg_finish', [s3.session_id, { n: s3.params.target }]);
  ok(f.status === 'won', 'menang');
  ok((await G.call('api_mg_start', ['uji', 'quest', 'satu'])).params.assist === 0, 'reset setelah menang');
  // kedaluwarsa
  const s4 = await G.call('api_mg_start', ['uji', 'quest', 'satu']);
  await H.sql(`update game.mg_session set expires_at = now() - interval '10 seconds' where id = $1`, [s4.session_id]);
  f = await G.call('api_mg_finish', [s4.session_id, { n: s4.params.target }]);
  ok(f.status === 'expired' && /Kesempatan berlalu/.test(f.pesan), 'kedaluwarsa');
  // min_total_ms: selesai terlalu cepat ditolak
  await H.sql(`create or replace function game.mg_uji_build(p_pid uuid, p_ctx text, p_preset text, p_assist int) returns jsonb language sql volatile as $$ select jsonb_build_object('max_ms', 5000, 'min_total_ms', 20000, 'target', 3, 'assist', p_assist) $$`);
  const s5 = await G.call('api_mg_start', ['uji', 'quest', 'satu']);
  await H.expectError(() => G.call('api_mg_finish', [s5.session_id, { n: 3 }]), /tidak sah/);
  await H.sql(`update game.mg_session set issued_ms = issued_ms - 18000 where id = $1`, [s5.session_id]);
  ok((await G.call('api_mg_finish', [s5.session_id, { n: 3 }])).status === 'won', 'cukup lama (toleransi 3 dtk) -> sah');
  // batas laju
  await H.sql(`select game.cfg_set('S5MgJedaMs', '60000')`);
  await H.expectError(() => G.call('api_mg_start', ['uji', 'quest', 'satu']), /Pelan-pelan/);
  await H.sql(`select game.cfg_set('S5MgJedaMs', '0'), game.cfg_set('S5MgPerJam', '3')`);
  await H.expectError(() => G.call('api_mg_start', ['uji', 'quest', 'satu']), /kelelahan/);
  await H.sql(`select game.cfg_set('S5MgPerJam', '30')`);

  // ---------- Alat uji GM (api_s5 gm_*) ----------
  await H.sql(`select game.cfg_set('FiturPenguji', '')`);
  await H.expectError(() => B.call('api_s5', ['gm_dunia', 'seberang']), /Aksi tidak dikenal/);
  await H.expectError(() => B.call('api_s5', ['status']), /Aksi tidak dikenal/);
  let g = await G.call('api_s5', ['gm_status']);
  ok(g.gm.dunia === 'mare' && g.gm.gerbang.a === '0', 'status GM');
  g = await G.call('api_s5', ['gm_dunia', 'seberang']);
  ok(g.gm.dunia === 'seberang', 'GM pindah ke seberang (tanpa gerbang terbuka)');
  ok((await one(`select c, sea from game.mp_presence where player_id = $1`, [G.id])).sea === true, 'presence GM langsung tersamar');
  await H.expectError(() => pre(G, 'api_buy'), /di seberang titian/);
  await pre(G, 'api_s5'); await pre(G, 'api_gmcommand');
  ok((await one(`select cross_day from game.s5_state where player_id = $1`, [G.id])).cross_day === null, 'uji pagar tidak mencatat hari titian');
  g = await G.call('api_s5', ['gm_dunia', 'mare']);
  ok(g.gm.dunia === 'mare', 'GM kembali ke Mare');
  await pre(G, 'api_buy');
  await H.expectError(() => G.call('api_s5', ['gm_dunia', 'bulan']), /mare atau seberang/);
  await H.sql(`select game.s5_catat_seberang($1, 'seberang')`, [G.id]);
  ok((await G.call('api_s5', ['gm_status'])).gm.bisa.ok === false, 'hari titian tercatat');
  ok((await G.call('api_s5', ['gm_reset_hari'])).gm.bisa.ok === true, 'GM reset hari titian');
  await G.call('api_s5', ['gm_dunia', 'mare']);
  // gerbang ditutup lagi -> rahasia
  await H.sql(`select game.cfg_set('FiturPenguji', '')`);
  await H.expectError(() => G.call('api_mg_finish', [s5.session_id, { n: 3 }]), /Aksi tidak dikenal/);

  console.log('OK 0105-s5-dasar: gerbang, titian 1/hari, pagar seberang (' + nTolak + ' RPC ditolak), presence, harian, pencegatan, mg_session');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });

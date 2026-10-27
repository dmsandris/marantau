// Tide v38: pengumuman GM, mode pemeliharaan (langsung & terjadwal), gerbang pre-request, data di pulse.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const mk = async (u, name) => { const c = await H.user(u); await c.call('api_createCharacter', [name, 'merchant']); return c; };
  const GM = await mk('abuy', 'OBH Chombi Sachet');
  const P = await mk('gm_pemain', 'Kapten Biasa');
  const anon = await H.anon();

  // Gerbang pre-request: jalankan seperti PostgREST (path + sesi), kembalikan null bila lolos, kode error bila ditolak
  const gate = async (client, fn) => {
    await H.sql(`select set_config('request.path', $1, false), set_config('request.jwt.claim.sub', $2, false)`, ['/rpc/' + fn, client && client.id ? client.id : '']);
    try { await H.sql('select public.mt_pre_request()'); return null; }
    catch (e) { return e.message; }
  };

  // --- keadaan normal -------------------------------------------------------
  let pulse = await P.call('api_mpPulse', [{}]);
  ok(pulse.gm === null, 'pulse tanpa apa-apa: gm null');
  ok(await gate(P, 'api_getgamestate') === null, 'normal: lolos');
  const s0 = await anon.call('api_gmStatus', []);
  ok(s0 && !s0.m && !s0.a, 'status publik kosong');
  pulse = await GM.call('api_mpPulse', [{}]);
  ok(pulse.gm && pulse.gm.gm === true, 'GM ditandai di pulse');

  // --- hanya GM ----------------------------------------------------------------
  await H.expectError(() => P.call('api_gmCommand', ['say', 'halo semua']), /khusus GM/);
  await H.expectError(() => P.call('api_gmCommand', ['maint_on', '']), /khusus GM/);
  await H.expectError(() => GM.call('api_gmCommand', ['say', '   ']), /kosong/);
  await H.expectError(() => GM.call('api_gmCommand', ['terbang', 'x']), /tidak dikenal/);

  // --- pengumuman --------------------------------------------------------------
  const now = Number((await one('select game.now_ms() t')).t);
  const sentBefore = Number((await one(`select count(*) n from realtime.sent where topic = 'chat:global' and event = 'gm'`)).n);
  let r = await GM.call('api_gmCommand', ['say', 'Server reset pukul 14.00 ya Kapten', { lvl: 'warn', at: now + 3600000 }]);
  ok(r.ok, 'say ok');
  pulse = await P.call('api_mpPulse', [{}]);
  ok(pulse.gm && pulse.gm.a && pulse.gm.a.length === 1, 'pengumuman muncul di pulse pemain');
  ok(pulse.gm.a[0].lvl === 'warn' && Number(pulse.gm.a[0].at) === now + 3600000, 'level & hitung mundur ikut');
  ok(!pulse.gm.gm, 'pemain biasa bukan GM');
  const chat = pulse.chat.g.filter(m => m.p === 'gm');
  ok(chat.length === 1 && chat[0].n === 'GM abuy' && /14\.00/.test(chat[0].tx), 'tercatat di chat Dunia dengan label GM');
  const sentAfter = Number((await one(`select count(*) n from realtime.sent where topic = 'chat:global' and event = 'gm'`)).n);
  ok(sentAfter === sentBefore + 1, 'bel realtime gm dikirim');
  const s1 = await anon.call('api_gmStatus', []);
  ok(s1.a && s1.a.length === 1, 'layar judul (tanpa login) juga melihat pengumuman');
  await H.expectError(() => GM.call('api_gmCommand', ['say', 'kejauhan', { at: now + 5 * 86400000 }]), /48 jam/);
  r = await GM.call('api_gmCommand', ['say', 'Darurat!', { lvl: 'urgent', min: 5 }]);
  pulse = await P.call('api_mpPulse', [{}]);
  ok(pulse.gm.a.length === 2 && pulse.gm.a[1].lvl === 'urgent', 'pengumuman darurat');
  // kedaluwarsa
  await H.sql(`update game.gm_announce set until = now() - interval '1 second' where lvl = 'urgent'`);
  pulse = await P.call('api_mpPulse', [{}]);
  ok(pulse.gm.a.length === 1, 'pengumuman kedaluwarsa hilang');
  await GM.call('api_gmCommand', ['clear', '']);
  pulse = await P.call('api_mpPulse', [{}]);
  ok(pulse.gm === null, 'clear: semua pengumuman hilang');

  // --- pemeliharaan langsung ---------------------------------------------------
  await GM.call('api_gmCommand', ['maint_on', 'Tambah pulau baru', { endAt: now + 20 * 60000 }]);
  ok(await gate(P, 'api_getgamestate') !== null, 'pemain biasa ditolak');
  const msg = await gate(P, 'api_buy');
  const j = JSON.parse(msg);
  ok(j.code === 'MT_MAINT' && /Maintenis dulu ya gaes/.test(j.message), 'pesan pemeliharaan');
  const det = JSON.parse(j.details);
  ok(det.on === true && det.tx === 'Tambah pulau baru' && Number(det.endAt) === now + 20 * 60000, 'detail pemeliharaan');
  ok(await gate(anon, 'api_gettitlescreenconfig') !== null, 'layar judul tanpa login juga ditolak');
  ok(await gate(anon, 'api_usernameavailable') !== null, 'daftar akun ditolak');
  ok(await gate(P, 'api_gmstatus') === null && await gate(anon, 'api_ping') === null, 'cek status & ping tetap boleh');
  ok(await gate(GM, 'api_getgamestate') === null && await gate(GM, 'api_buy') === null, 'GM tetap bisa main');
  pulse = await GM.call('api_mpPulse', [{}]);
  ok(pulse.gm.m && pulse.gm.m.on === true, 'GM melihat status pemeliharaan');
  const st = await anon.call('api_gmStatus', []);
  ok(st.m && st.m.on === true, 'status publik: aktif');

  // --- deploy ulang tidak mereset status --------------------------------------
  const fs = require('fs'), path = require('path');
  for (const f of ['0001b_interfaces.sql', '0005_multiplayer.sql', '0036_gm_pemeliharaan.sql'])
    await H.db.exec(fs.readFileSync(path.join(require('./harness').MIG_DIR, f), 'utf8'));
  ok(await gate(P, 'api_getgamestate') !== null, 'setelah deploy ulang: masih pemeliharaan');

  // --- selesai -------------------------------------------------------------------
  await GM.call('api_gmCommand', ['maint_off', '']);
  ok(await gate(P, 'api_getgamestate') === null, 'selesai: pemain lolos lagi');
  pulse = await P.call('api_mpPulse', [{}]);
  ok(pulse.gm === null, 'tidak ada sisa status');
  ok(pulse.chat.g.some(m => m.p === 'gm' && /dibuka kembali/.test(m.tx)), 'ucapan buka kembali di chat');

  // --- pemeliharaan terjadwal ----------------------------------------------------
  await H.expectError(() => GM.call('api_gmCommand', ['maint_at', '', { startAt: now - 1000 }]), /masa depan/);
  await GM.call('api_gmCommand', ['maint_at', '', { startAt: now + 15 * 60000, endAt: now + 45 * 60000 }]);
  ok(await gate(P, 'api_getgamestate') === null, 'terjadwal: belum ditutup');
  pulse = await P.call('api_mpPulse', [{}]);
  ok(pulse.gm.m && pulse.gm.m.on === false && Number(pulse.gm.m.startAt) === now + 15 * 60000, 'terjadwal terlihat pemain');
  ok(pulse.gm.a.length === 1 && pulse.gm.a[0].kind === 'maint' && Number(pulse.gm.a[0].at) === now + 15 * 60000, 'pengumuman hitung mundur otomatis');
  await H.sql(`update game.config set value = $1 where key = 'MaintenanceStartAt'`, [String(now - 1000)]);   // jam tiba
  ok(await gate(P, 'api_getgamestate') !== null, 'jam tiba: otomatis ditutup');
  pulse = await GM.call('api_mpPulse', [{}]);
  ok(pulse.gm.m.on === true, 'status: aktif');
  await GM.call('api_gmCommand', ['maint_off', 'Sudah beres!']);
  ok(await gate(P, 'api_getgamestate') === null, 'buka lagi');
  ok((await P.call('api_mpPulse', [{}])).gm === null, 'bersih setelah terjadwal');

  // --- gagal-terbuka -------------------------------------------------------------
  await H.sql(`update game.config set value = 'on' where key = 'MaintenanceMode'`);
  await H.sql(`update game.config set value = 'bukan,list' where key = 'GmUsernames'`);
  ok(await gate(GM, 'api_getgamestate') !== null, 'GM dicabut -> ikut ditolak');
  await H.sql(`update game.config set value = 'abuy' where key = 'GmUsernames'`);
  await H.sql(`update game.config set value = 'off' where key = 'MaintenanceMode'`);

  console.log('GM & PEMELIHARAAN TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });

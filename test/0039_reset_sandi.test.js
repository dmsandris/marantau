// Tide v43: reset sandi oleh GM, sandi sementara, wajib ganti sandi (gerbang MT_PWCHANGE), kapten lama.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const mk = async (u, name) => { const c = await H.user(u); await c.call('api_createCharacter', [name, 'merchant']); return c; };
  const setPw = async (c, pw) => H.sql(`update auth.users set encrypted_password = extensions.crypt($2, extensions.gen_salt('bf', 4)) where id = $1`, [c.id, pw]);
  const pwOk = async (c, pw) => (await one(`select encrypted_password = extensions.crypt($2, encrypted_password) ok from auth.users where id = $1`, [c.id, pw])).ok;
  const gate = async (client, fn) => {
    await H.sql(`select set_config('request.path', $1, false), set_config('request.jwt.claim.sub', $2, false), set_config('request.jwt.claim.email', $3, false)`,
      ['/rpc/' + fn, client && client.id ? client.id : '', client && client.email ? client.email : '']);
    try { await H.sql('select public.mt_pre_request()'); return null; } catch (e) { return e.message; }
  };

  const GM = await mk('abuy', 'OBH Chombi Sachet');
  const P = await mk('lupasandi', 'Kapten Pelupa');
  const Q = await mk('pemainlain', 'Kapten Lain');
  await setPw(P, 'sandiLama123');
  await H.sql(`insert into auth.sessions(user_id) values ($1), ($1)`, [P.id]);
  await H.sql(`insert into auth.refresh_tokens(user_id, token) values ($1, 'x')`, [P.id]);

  // --- hanya GM ---
  await H.expectError(() => P.call('api_gmPassword', ['lookup', 'pemainlain']), /khusus GM/);
  await H.expectError(() => Q.call('api_gmPassword', ['reset', 'lupasandi']), /khusus GM/);
  await H.expectError(() => GM.call('api_gmPassword', ['lookup', 'tidakada']), /tidak ditemukan/);
  await H.expectError(() => GM.call('api_gmPassword', ['lookup', 'A B']), /tidak valid/);
  await H.expectError(() => GM.call('api_gmPassword', ['reset', 'abuy']), /Pengaturan/);

  // --- kartu verifikasi ---
  let r = await GM.call('api_gmPassword', ['lookup', 'LupaSandi']);
  ok(r.card.name === 'Kapten Pelupa' && r.card.arch === 'merchant', 'kartu: nama & archetype');
  ok(r.card.ship && r.card.city, 'kartu: kapal & kota');
  ok(r.card.pending === false && Number(r.card.resets) === 0 && r.card.legacy === false, 'kartu: belum pernah reset');

  // --- reset ---
  ok(await gate(P, 'api_getgamestate') === null, 'sebelum reset: lolos');
  r = await GM.call('api_gmPassword', ['reset', 'lupasandi']);
  ok(/^[a-z]+-\d{4}$/.test(r.temp), 'sandi sementara berbentuk kata-angka: ' + r.temp);
  const temp = r.temp;
  ok(await pwOk(P, temp), 'sandi Auth = sandi sementara');
  ok(!(await pwOk(P, 'sandiLama123')), 'sandi lama tidak berlaku');
  ok(Number((await one(`select count(*) n from auth.sessions where user_id = $1`, [P.id])).n) === 0, 'sesi lama dihapus');
  ok(Number((await one(`select count(*) n from auth.refresh_tokens where user_id = $1`, [P.id])).n) === 0, 'refresh token dihapus');
  ok(!JSON.stringify(await H.sql('select * from game.pw_must_change')).includes(temp), 'sandi sementara tidak tersimpan');
  ok(!JSON.stringify(await H.sql('select * from game.pw_reset_log')).includes(temp), 'sandi sementara tidak di log');

  // --- gerbang wajib ganti sandi ---
  const g = await gate(P, 'api_getgamestate');
  ok(g && /MT_PWCHANGE/.test(g), 'setelah reset: endpoint game ditolak');
  for (const fn of ['api_pwstatus', 'api_pwchanged', 'api_authwhoami', 'api_ping', 'api_gmstatus']) ok(await gate(P, fn) === null, 'boleh: ' + fn);
  ok(await gate(Q, 'api_getgamestate') === null, 'pemain lain tidak terdampak');
  ok(await gate(GM, 'api_getgamestate') === null, 'GM tidak terdampak');
  ok((await P.call('api_pwStatus', [])).must === true, 'pwStatus: must');
  ok((await Q.call('api_pwStatus', [])).must === false, 'pwStatus pemain lain: tidak');

  // belum ganti sandi -> tidak bisa mencabut tanda
  await H.expectError(() => P.call('api_pwChanged', []), /belum berganti/);
  ok(/MT_PWCHANGE/.test(await gate(P, 'api_getgamestate')), 'masih terkunci');

  r = await GM.call('api_gmPassword', ['lookup', 'lupasandi']);
  ok(r.card.pending === true && Number(r.card.resets) === 1, 'kartu: menunggu ganti, 1 reset');

  // pemain memasang sandi baru (lewat Supabase Auth), lalu lapor
  await setPw(P, 'sandiBaruKu99');
  r = await P.call('api_pwChanged', []);
  ok(r.ok && r.must === false, 'pwChanged ok');
  ok(await gate(P, 'api_getgamestate') === null, 'setelah ganti: lolos lagi');
  ok((await P.call('api_pwStatus', [])).must === false, 'pwStatus bersih');
  const st = await P.call('api_getGameState', []);
  ok(st, 'bisa main lagi');

  // --- log ---
  r = await GM.call('api_gmPassword', ['log']);
  ok(r.log.length === 2 && r.log[0].k === 'changed' && r.log[1].k === 'reset' && r.log[1].by === 'abuy', 'log reset & ganti');
  ok(r.pending.length === 0, 'tidak ada yang menunggu');
  await H.expectError(() => GM.call('api_gmPassword', ['hapus', 'x']), /tidak dikenal/);

  // --- gerbang pemeliharaan tetap jalan ---
  await GM.call('api_gmCommand', ['maint_on', '']);
  ok(/MT_MAINT/.test(await gate(Q, 'api_getgamestate')), 'pemeliharaan tetap menutup');
  ok(await gate(GM, 'api_getgamestate') === null, 'GM tetap lolos saat pemeliharaan');
  await GM.call('api_gmCommand', ['maint_off', '']);
  ok(await gate(Q, 'api_getgamestate') === null, 'buka lagi');

  // --- kapten lama (Google Sheets, belum diklaim) ---
  const legacyPid = '00000000-0000-4000-8000-00000000a11e';
  await H.sql(`insert into game.players(player_id, username, character_name, archetype, gold) values ($1, 'kaptenlama', 'Kapten Sheets', 'navigator', 7777)`, [legacyPid]);
  await H.sql(`insert into game.legacy_accounts(username, pass_hash, salt, player_id, legacy_id, failed)
    values ('kaptenlama', game.legacy_hash('lupa', 'garam'), 'garam', $1, 'acc:kaptenlama', 10)`, [legacyPid]);
  r = await GM.call('api_gmPassword', ['lookup', 'kaptenlama']);
  ok(r.card.legacy === true && r.card.name === 'Kapten Sheets' && Number(r.card.gold) === 7777, 'kartu kapten lama');
  r = await GM.call('api_gmPassword', ['reset', 'kaptenlama']);
  const ltemp = r.temp;
  const anon = await H.anon();
  ok((await anon.call('api_legacyCheck', ['kaptenlama', ltemp])).ok === true, 'sandi sementara berlaku untuk kapten lama (kunci gagal dibuka)');
  // klien membuat akun Auth dengan sandi sementara, lalu klaim
  const L = await H.user('kaptenlama');
  await setPw(L, ltemp);
  ok(await gate(L, 'api_legacyclaim') === null, 'klaim boleh saat wajib ganti');
  await L.call('api_legacyClaim', [ltemp]);
  ok(/MT_PWCHANGE/.test(await gate(L, 'api_getgamestate')), 'kapten lama: wajib ganti setelah klaim');
  ok((await L.call('api_pwStatus', [])).must === true, 'kapten lama: must');
  await H.expectError(() => L.call('api_pwChanged', []), /belum berganti/);
  await setPw(L, 'sandiBaruLama1');
  await L.call('api_pwChanged', []);
  ok(await gate(L, 'api_getgamestate') === null, 'kapten lama: lolos setelah ganti');
  ok((await L.call('api_getGameState', [])), 'kapten lama bisa main');

  console.log('Reset sandi GM: semua cek lulus.');
})().catch(e => { console.error(e); process.exit(1); });

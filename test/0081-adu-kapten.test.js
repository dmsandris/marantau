// 0081 Adu Kapten: tantang-terima, setor catatan, re-simulasi server, batas pasangan per hari.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const { human, SKILL } = require('./trek-sim');
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const siap = async (u, uname, nama) => {
    await u.call('api_createCharacter', [nama, 'merchant']);
    await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1,'ps14',6,'{}', now() - interval '2 hours')
      on conflict (player_id, quest_id) do update set step = 6, done_at = now() - interval '2 hours'`, [u.id]);
    await one(`select game.admin_mahkota($1, 40) s`, [uname]);
    await H.sql(`update game.player_location set city_id = 'zentul', destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id]);
    await u.call('api_mpPulse', []);
  };
  await H.sql(`update game.config set value = '1' where key = 'MahkotaOpen'`);
  const a = await H.user('adu_a'), b = await H.user('adu_b');
  await siap(a, 'adu_a', 'Kapten Alif'); await siap(b, 'adu_b', 'Kapten Bima');
  const pub = async (u) => (await one(`select game.mp_pub_of($1) p`, [u.id])).p;

  // lobi saling melihat
  let lob = (await a.call('api_trekDuel', ['lobi'])).adu;
  assert(lob.siap === true && lob.kapten.length === 1 && lob.kapten[0].nama === 'Kapten Bima' && lob.kapten[0].sisa === 3, 'lobi: ' + JSON.stringify(lob.kapten));
  assert(lob.duel === null && lob.maks === 3, 'belum ada adu berjalan');

  // pemain yang belum tamat tidak boleh
  const c = await H.user('adu_c'); await c.call('api_createCharacter', ['Kapten Cawan', 'merchant']);
  assert(await H.expectError(() => c.call('api_trekDuel', ['lobi'])), 'belum tamat ditolak');
  lob = (await a.call('api_trekDuel', ['lobi'])).adu;
  assert(lob.kapten.length === 1, 'yang belum tamat tidak muncul di lobi');

  // tantang + tolak
  let d = (await a.call('api_trekDuel', ['tantang', await pub(b)])).duel;
  assert(d.status === 'invited' && d.lawan === 'Kapten Bima' && d.aku === 'a', 'tantangan terkirim');
  assert(Number((await one(`select count(*) n from game.mp_inbox where player_id = $1 and item ->> 'type' = 'trek_adu_invite'`, [b.id])).n) === 1, 'undangan masuk inbox');
  assert(await H.expectError(() => a.call('api_trekDuel', ['jawab', d.id, true])), 'penantang tidak bisa menjawab sendiri');
  let r = (await b.call('api_trekDuel', ['jawab', d.id, false])).duel;
  assert(r.status === 'declined', 'tolak');
  assert(((await a.call('api_trekDuel', ['lobi'])).adu).duel === null, 'slot bebas lagi setelah ditolak');

  // tantang + terima + balapan
  d = (await a.call('api_trekDuel', ['tantang', await pub(b)])).duel;
  const pubA = await pub(a), pubB = await pub(b);
  assert(await H.expectError(() => b.call('api_trekDuel', ['tantang', pubA])), 'tak bisa menantang saat ada undangan');
  r = (await b.call('api_trekDuel', ['jawab', d.id, true])).duel;
  assert(r.status === 'active' && r.seed === d.seed && r.kapalku && r.kapalLawan, 'adu dimulai dengan benih sama');

  const kapal = (await one(`select game.trek_ships() -> $1 s`, [d.kapalku])).s;
  const logA = human(kapal, d.seed, SKILL.jago).log;     // jago
  const logB = human(kapal, d.seed, SKILL.pemula).log;   // pemula
  r = (await a.call('api_trekDuel', ['log', d.id, logA])).duel;
  assert(r.status === 'active' && r.logKu === true && r.logLawan === false, 'menunggu lawan');
  r = (await b.call('api_trekDuel', ['log', d.id, logB])).duel;
  assert(r.status === 'done' && r.usKu > 0 && r.usLawan > 0, 'kedua catatan masuk: ' + JSON.stringify(r));
  assert(r.menang === 'lawan' && r.usLawan < r.usKu, 'yang lebih cepat menang (dari sisi B): ' + r.menang);
  const ra = (await a.call('api_trekDuel', ['lihat', d.id])).duel;
  assert(ra.menang === 'aku' && ra.usKu === r.usLawan, 'sisi A konsisten');
  assert(Number((await one(`select count(*) n from game.mp_inbox where player_id = $1 and item ->> 'type' = 'trek_adu_hasil'`, [a.id])).n) === 1, 'kabar hasil masuk');

  // catatan palsu ditolak
  d = (await a.call('api_trekDuel', ['tantang', await pub(b)])).duel;
  await b.call('api_trekDuel', ['jawab', d.id, true]);
  assert(await H.expectError(() => a.call('api_trekDuel', ['log', d.id, [[1, 2]]])), 'catatan tak terbaca ditolak');
  assert(await H.expectError(() => a.call('api_trekDuel', ['log', d.id, [[900, 1], [100, 0]]])), 'urutan waktu mundur ditolak');
  // yang diam melewati tenggat dianggap kalah
  await a.call('api_trekDuel', ['log', d.id, logA]);
  await H.sql(`update game.trek_duels set started = started - 120000 where id = $1`, [d.id]);
  r = (await a.call('api_trekDuel', ['lihat', d.id])).duel;
  assert(r.status === 'done' && r.menang === 'aku' && r.usLawan === null, 'lawan tidak menyetor: kalah');

  // keduanya diam: batal
  d = (await a.call('api_trekDuel', ['tantang', await pub(b)])).duel;
  await b.call('api_trekDuel', ['jawab', d.id, true]);
  await H.sql(`update game.trek_duels set started = started - 120000 where id = $1`, [d.id]);
  r = (await a.call('api_trekDuel', ['lihat', d.id])).duel;
  assert(r.status === 'cancelled' && r.menang === null, 'keduanya diam: adu dibatalkan');

  // adu yang batal tidak memakan jatah
  assert((await one(`select game.trek_adu_jml($1, $2) n`, [a.id, b.id])).n === 2, 'adu batal tidak terhitung');
  // batas 3 per pasangan per hari game (yang terhitung: active + done)
  d = (await a.call('api_trekDuel', ['tantang', pubB])).duel;
  await b.call('api_trekDuel', ['jawab', d.id, true]);
  await a.call('api_trekDuel', ['log', d.id, logA]); await b.call('api_trekDuel', ['log', d.id, logB]);
  assert((await one(`select game.trek_adu_jml($1, $2) n`, [a.id, b.id])).n === 3, 'tiga adu tercatat hari ini');
  assert(await H.expectError(() => a.call('api_trekDuel', ['tantang', pubB])), 'adu keempat ditolak');
  lob = (await a.call('api_trekDuel', ['lobi'])).adu;
  assert(lob.kapten[0].sisa === 0, 'sisa jatah 0');
  // hari game berikutnya: jatah pulih
  await H.sql(`update game.trek_duels set game_day = game_day - 1`);
  lob = (await a.call('api_trekDuel', ['lobi'])).adu;
  assert(lob.kapten[0].sisa === 3, 'jatah pulih hari berikutnya');

  // undangan kedaluwarsa 60 detik
  d = (await a.call('api_trekDuel', ['tantang', await pub(b)])).duel;
  await H.sql(`update game.trek_duels set created = created - 90000 where id = $1`, [d.id]);
  assert(await H.expectError(() => b.call('api_trekDuel', ['jawab', d.id, true])), 'undangan kedaluwarsa');
  assert(((await a.call('api_trekDuel', ['lobi'])).adu).duel === null, 'slot bebas setelah kedaluwarsa');

  // tidak merapat di Zentul: tidak bisa menantang & tidak muncul di lobi
  await H.sql(`update game.player_location set city_id = 'ikn' where player_id = $1`, [b.id]);
  await b.call('api_mpPulse', []);
  lob = (await a.call('api_trekDuel', ['lobi'])).adu;
  assert(lob.kapten.length === 0, 'lawan yang berlayar tidak muncul');
  assert(await H.expectError(() => a.call('api_trekDuel', ['tantang', pubB])), 'lawan di luar Zentul ditolak');

  // papan adu
  const papan = (await one(`select game.trek_adu_papan() p`)).p;
  assert(papan.length >= 1 && papan[0].nama === 'Kapten Alif' && papan[0].menang >= 2, 'papan adu: ' + JSON.stringify(papan));

  // gerbang mati
  await H.sql(`update game.config set value = '0' where key = 'TrekAduOpen'`);
  assert(await H.expectError(() => a.call('api_trekDuel', ['lobi'])), 'gerbang TrekAduOpen mati');
  const st = (await a.call('api_trek', ['status'])).trek;
  assert(st.adu === null, 'status Sirkuit: adu null saat gerbang mati');
  await H.sql(`update game.config set value = '1' where key = 'TrekAduOpen'`);
  const st2 = (await a.call('api_trek', ['status'])).trek;
  assert(st2.adu && st2.adu.maks === 3, 'status Sirkuit membawa ringkasan adu');

  console.log('0081 adu kapten: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });

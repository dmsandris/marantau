/* =====================================================================
 * mt-supabase.js - jembatan client lama (google.script.run) -> Supabase.
 * Semua google.script.run.api_xxx(a, b, ...) menjadi
 *   supabase.rpc('api_xxx', { a: [a, b, ...] })
 * Login/daftar memakai Supabase Auth (username -> <username>@marantau.game).
 * ===================================================================== */
(function () {
  var C = window.MT_CONFIG;
  var sb = window.supabase.createClient(C.supabaseUrl, C.supabaseKey, {
    auth: { persistSession: true, autoRefreshToken: true, storageKey: 'mt_sb_auth_v1' }
  });
  window.MTSB = sb;
  var AUTH_MSG = 'AUTH_REQUIRED: Silakan masuk dengan akun Marantau-mu.';
  function email(u) { return String(u || '').trim().toLowerCase() + '@' + C.emailDomain; }
  function err(msg) { var e = new Error(msg); return e; }
  function mapError(e) {
    var m = (e && (e.message || e.error_description || e.msg)) || String(e);
    var code = e && e.code;
    if (code === '42501' || /^PGRST30\d$/.test(String(code || '')) ||
        /permission denied|JWT expired|invalid JWT|jwt|JWS|wrong key|no suitable key/i.test(m)) return err(AUTH_MSG);
    if (/Failed to fetch|NetworkError|Load failed/i.test(m)) return err('Koneksi ke server terputus. Periksa internet lalu coba lagi.');
    return err(m.replace(/^Error:\s*/, ''));
  }
  function validate(u, p) {
    if (!/^[a-z0-9_]{3,16}$/.test(u)) throw err('Username 3-16 karakter: huruf kecil, angka, atau garis bawah (_).');
    if (String(p || '').length < 6) throw err('Password minimal 6 karakter.');
    if (String(p).length > 72) throw err('Password terlalu panjang.');
  }
  // Endpoint yang boleh dipanggil tanpa login (sisanya butuh sesi)
  var PUBLIC = { api_ping: 1, api_gettitlescreenconfig: 1, api_getsailingbackgroundurl: 1, api_getcities: 1,
    api_getarchetypes: 1, api_authwhoami: 1, api_usernameavailable: 1, api_legacycheck: 1, api_gmstatus: 1 };
  // Pindah server (rencana 1.4): sesi tersimpan bisa berisi token dari server lama (JWT ditandatangani kunci lain,
  // `iss` beda). Tukar sekali lewat refresh token (ikut pindah bersama database) -> pemain tidak perlu login ulang.
  var ISS = String(C.supabaseUrl).replace(/\/+$/, '') + '/auth/v1';
  function jwtIss(t) {
    try { var p = String(t).split('.')[1].replace(/-/g, '+').replace(/_/g, '/'); return JSON.parse(atob(p)).iss || ''; }
    catch (e) { return ''; }
  }
  var swapP = null;
  function withTimeout(p, ms) {
    return Promise.race([p, new Promise(function (_, no) { setTimeout(function () { no(new Error('timeout')); }, ms); })]);
  }
  // Sesi yang tidak bisa ditukar (refresh token tidak dikenal server ini) -> buang sesi lokal saja, supaya
  // layar login muncul. Hanya kunci login yang dihapus; penanda adegan/setelan pemain tetap.
  function purgeSession() {
    try { localStorage.removeItem('mt_sb_auth_v1'); localStorage.removeItem('mt_token_v1'); localStorage.removeItem('mt_user_v1'); } catch (e) {}
    return withTimeout(sb.auth.signOut({ scope: 'local' }), 3000).catch(function () {}).then(function () {
      try { localStorage.removeItem('mt_sb_auth_v1'); } catch (e) {}
    });
  }
  function swapToken(force) {
    if (swapP && !force) return swapP;
    swapP = withTimeout(sb.auth.getSession(), 8000).then(function (s) {
      var ses = s.data && s.data.session;
      if (!ses) return false;
      if (!force && jwtIss(ses.access_token) === ISS) return true;
      return withTimeout(sb.auth.refreshSession(), 10000).then(function (r) {
        if (!r.error && r.data && r.data.session) return true;
        return purgeSession().then(function () { return false; });
      });
    }).catch(function () { return purgeSession().then(function () { return false; }); });
    return swapP;
  }
  function badJwt(e) {
    var m = (e && (e.message || '')) + ' ' + (e && e.code || '');
    return /PGRST30[0-3]|JWS|JWT|invalid signature|wrong key/i.test(m);
  }
  /* ===================================================================
   * BUKU ADEGAN (0088) - penanda "adegan sudah dilihat" dicadangkan di server.
   * Modul quest tetap memakai localStorage seperti biasa; semua kerja di sini:
   *  1. Pulihkan : respons getGameState pertama membawa 'seen' -> kunci yang belum ada ditulis ke
   *                localStorage SEBELUM data diteruskan ke game (scenes() langsung melihat penanda).
   *  2. Rekam    : Storage.setItem/removeItem dibungkus; kunci berpola -> antre -> api_seenMark
   *                (jeda 3 dtk; saat tab disembunyikan/ditutup dikirim dengan fetch keepalive).
   *  3. Unggah   : penanda lama di browser yang belum ada di server ikut diantre (unggah pertama).
   *  4. Penjaga  : kapten lama yang belum punya cadangan dan browsernya kosong -> selama pemuatan
   *                pertama, sinematik layar penuh yang muncul sendiri langsung "Lewati" (alur & pilihan
   *                tetap jalan, penanda tetap tercatat). Selesai saat pemain beraksi / 30 dtk / sekali saja.
   * Pola kunci modul baru WAJIB ditambah di sini DAN di game.seen_ok (0088).
   * =================================================================== */
  var SEEN_RE = /^((bx|ww|kp|cb|ts|lt|dt|ps|pd):|th_|mt_pr_|mt_trek_|mt_seen_)/;
  var SP = window.Storage && Storage.prototype, LS = null;
  try { LS = window.localStorage; } catch (e) {}
  var nGet = SP && SP.getItem, nSet = SP && SP.setItem, nDel = SP && SP.removeItem;
  var SEEN = { me: null, uid: null, synced: null, token: null, qs: {}, qd: {}, t: 0, busy: false, guard: null };
  function seenKeyOk(k) { return typeof k === 'string' && k.length >= 3 && k.length <= 96 && SEEN_RE.test(k); }
  // Kunci milik kapten yang sedang masuk (browser bisa dipakai bergantian beberapa akun)
  function seenOwn(k) {
    var me = SEEN.me; if (!me) return false;
    var m = /^(kp|cb|ts|lt|dt|ps|pd):([^:]*):/.exec(k);
    if (m) return m[2] === me.u;
    if (/^(bx|ww):/.test(k) || /^mt_pr_/.test(k)) return !!me.c && k.slice(-(me.c.length + 1)) === ':' + me.c;
    if (/^mt_seen_/.test(k)) return k.slice(-(me.u.length + 1)) === ':' + me.u;
    return /^(th_|mt_trek_)/.test(k);
  }
  function seenLocalKeys() {
    var out = [];
    try { for (var i = 0; i < LS.length; i++) { var k = LS.key(i); if (seenKeyOk(k) && seenOwn(k)) out.push(k); } } catch (e) {}
    return out;
  }
  function seenQueue(k, v) { delete SEEN.qd[k]; SEEN.qs[k] = v; seenSchedule(); }
  function seenSchedule() { if (!SEEN.t) SEEN.t = setTimeout(function () { SEEN.t = 0; seenFlush(); }, 3000); }
  function seenBatch() {
    var sets = [], dels = [], bytes = 0, k;
    for (k in SEEN.qd) { if (sets.length + dels.length >= 200 || bytes > 50000) break; if (seenOwn(k)) { dels.push(k); bytes += k.length + 4; } delete SEEN.qd[k]; }
    for (k in SEEN.qs) {
      if (sets.length + dels.length >= 200 || bytes > 50000) break;
      var v = SEEN.qs[k]; delete SEEN.qs[k];
      if (!seenOwn(k) || v.length > 2000) continue;
      sets.push(v === '1' ? k : [k, v]); bytes += k.length + v.length + 8;
    }
    return sets.length || dels.length ? [sets, dels] : null;
  }
  function seenRequeue(b) {
    b[0].forEach(function (e) { var k = typeof e === 'string' ? e : e[0]; if (!(k in SEEN.qs) && !(k in SEEN.qd)) SEEN.qs[k] = typeof e === 'string' ? '1' : e[1]; });
    b[1].forEach(function (k) { if (!(k in SEEN.qs) && !(k in SEEN.qd)) SEEN.qd[k] = 1; });
  }
  function seenFlush() {
    if (SEEN.busy || !SEEN.synced || !SEEN.me) return;
    var b = seenBatch(); if (!b) return;
    SEEN.busy = true;
    rpc('api_seenMark', b).then(function () {
      SEEN.busy = false;
      if (Object.keys(SEEN.qs).length || Object.keys(SEEN.qd).length) seenFlush();
    }, function () { SEEN.busy = false; seenRequeue(b); setTimeout(seenSchedule, 15000); });
  }
  // Tab disembunyikan/ditutup: kirim sisa antrean tanpa menunggu (fetch keepalive, token terakhir)
  function seenFlushNow() {
    if (!SEEN.synced || !SEEN.token || !window.fetch) return;
    clearTimeout(SEEN.t); SEEN.t = 0;
    var b; while ((b = seenBatch())) {
      try {
        fetch(String(C.supabaseUrl).replace(/\/+$/, '') + '/rest/v1/rpc/api_seenmark', {
          method: 'POST', keepalive: true,
          headers: { 'Content-Type': 'application/json', apikey: C.supabaseKey, Authorization: 'Bearer ' + SEEN.token },
          body: JSON.stringify({ a: b })
        }).catch(function () {});
      } catch (e) { seenRequeue(b); break; }
    }
  }
  if (SP && LS && nSet) {
    SP.setItem = function (k, v) {
      nSet.call(this, k, v);
      if (this === LS && seenKeyOk(String(k))) { try { seenQueue(String(k), String(v)); } catch (e) {} }
    };
    SP.removeItem = function (k) {
      nDel.call(this, k);
      if (this === LS && seenKeyOk(String(k))) { try { k = String(k); delete SEEN.qs[k]; SEEN.qd[k] = 1; seenSchedule(); } catch (e) {} }
    };
    document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'hidden') seenFlushNow(); });
    window.addEventListener('pagehide', seenFlushNow);
  }
  // Respons getGameState: pulihkan penanda, antre yang belum tercadang, nyalakan penjaga bila perlu.
  function seenApply(d) {
    if (!d || !d.player || !LS || !nGet) return;
    SEEN.me = { u: String(d.username || d.player.characterName || 'x'), c: String(d.player.characterName || '') };
    var sv = d.seen; if (!sv || typeof sv !== 'object') return;
    delete d.seen;
    var srv = sv.k || {}, own = seenLocalKeys(), k;
    for (k in srv) {
      if (!seenKeyOk(k) || !seenOwn(k)) continue;
      try { if (nGet.call(LS, k) === null) nSet.call(LS, k, String(srv[k])); } catch (e) {}
    }
    own.forEach(function (k) { var v = nGet.call(LS, k); if (v !== null && srv[k] !== v) SEEN.qs[k] = v; });
    SEEN.synced = SEEN.uid;
    // th_/mt_trek_ tidak bernama kapten -> tidak dihitung sebagai "browser ini sudah punya penanda kapten ini"
    if (sv.g && !own.some(function (k) { return !/^(th_|mt_trek_)/.test(k); })) seenGuardOn();
    if (Object.keys(SEEN.qs).length) seenSchedule();
  }
  // Lapis 3: tekan "Lewati" pada sinematik layar penuh yang muncul sendiri saat pemuatan pertama.
  // Hanya modul yang penandanya di localStorage; hk/ks (penanda server) & pr (sambutan kapten baru) dikecualikan.
  var SKIP_NO = /(^|\s)(hk-cine|ks-cine|pr-cine)(\s|$)/;
  function seenGuardOn() {
    if (SEEN.guard || !window.MutationObserver) return;
    var g = SEEN.guard = { mo: null, to: 0 };
    function press(el, n) {
      if (!SEEN.guard || !el.isConnected || el.classList.contains('out')) return;
      var b = el.querySelector('button[class*="skip"]');
      if (b) { try { b.click(); } catch (e) {} }
      if (n < 2) setTimeout(function () { press(el, n + 1); }, 700);
    }
    function look(el) {
      if (!el || el.nodeType !== 1 || SKIP_NO.test(String(el.className || ''))) return;
      if (!el.querySelector('button[class*="skip"]') && !/cine|credits|crd/.test(String(el.className || ''))) return;
      setTimeout(function () { press(el, 0); }, 80);
    }
    function start() {
      if (SEEN.guard !== g) return;
      g.mo = new MutationObserver(function (ms) { ms.forEach(function (m) { Array.prototype.forEach.call(m.addedNodes, look); }); });
      g.mo.observe(document.body, { childList: true });
    }
    if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
    g.to = setTimeout(seenGuardOff, 30000);
    document.addEventListener('click', g.onClick = function (e) {
      // Pemain sengaja memutar ulang dari Tanda Jasa -> jangan dilewati
      if (e.target && e.target.closest && e.target.closest('[class*="replay"]')) seenGuardOff();
    }, true);
    console.info('[Marantau] Buku Adegan: penanda dipulihkan untuk browser ini.');
  }
  function seenGuardOff() {
    var g = SEEN.guard; if (!g) return;
    SEEN.guard = null; clearTimeout(g.to);
    try { if (g.mo) g.mo.disconnect(); } catch (e) {}
    document.removeEventListener('click', g.onClick, true);
    // Sekali saja per kapten: tanda ini membuat server tidak menyalakan penjaga lagi
    try { if (SEEN.me) localStorage.setItem('mt_seen_guard:' + SEEN.me.u, '1'); } catch (e) {}
  }
  // Panggilan yang tidak mengubah langkah quest; selain ini = pemain beraksi -> penjaga selesai
  var PASSIVE = /^api_(get|mppulse|gmstatus|ping|seenmark|pwstatus|authwhoami|usernameavailable|pollvoyage)/;
  window.MTSeen = { flush: seenFlushNow, _s: SEEN, guardOff: seenGuardOff };

  async function rpc(name, args, retried) {
    var fn = String(name).toLowerCase();
    await swapToken(false);
    if (!PUBLIC[fn]) {
      // Tunggu sesi tersimpan selesai dimuat; tanpa sesi -> minta login tanpa buang panggilan jaringan
      var s = await sb.auth.getSession();
      if (!s.data || !s.data.session) throw err(AUTH_MSG);
      SEEN.token = s.data.session.access_token;
      var uid = s.data.session.user && s.data.session.user.id;
      if (uid !== SEEN.uid) { SEEN.uid = uid; SEEN.synced = null; SEEN.me = null; }
    }
    if (SEEN.guard && !PASSIVE.test(fn)) seenGuardOff();
    // Buku Adegan: minta penanda dari server sekali per muat halaman (per akun)
    var wantSeen = fn === 'api_getgamestate' && SEEN.uid && SEEN.synced !== SEEN.uid && args && args.length === 1;
    if (wantSeen) args = [args[0], 'seen'];
    var r = await sb.rpc(fn, { a: args || [] });
    // Token ditolak server (kunci beda / kedaluwarsa) -> refresh sekali, ulangi panggilan.
    // Refresh gagal -> sesi lokal sudah dibuang (purgeSession) -> AUTH_REQUIRED -> layar login.
    if (r.error && badJwt(r.error)) {
      if (!retried && await swapToken(true)) return rpc(name, args, true);
      throw err(AUTH_MSG);
    }
    if (r.error) {
      // Tide v38: server sedang pemeliharaan -> tampilkan layar maintenis, panggilan ini dibiarkan menggantung
      // (tidak memunculkan pesan error di game; halaman dimuat ulang saat pelabuhan dibuka).
      if (r.error.code === 'MT_MAINT' && window.MTGM) { MTGM.blocked(r.error.details); return new Promise(function () {}); }
      // Tide v43: sandi direset GM -> wajib pasang sandi baru dulu (halaman dimuat ulang setelahnya)
      if (r.error.code === 'MT_PWCHANGE' && window.MTPW) { MTPW.require(); return new Promise(function () {}); }
      throw mapError(r.error);
    }
    if (fn === 'api_mppulse' && r.data && window.MTGM) { try { MTGM.onPulse(r.data.gm); } catch (e) {} }
    if (fn === 'api_getgamestate' && r.data) { try { seenApply(r.data); } catch (e) { console.warn('[Marantau] Buku Adegan', e); } }
    return r.data;
  }
  async function legacyMove(u, p) {
    var chk = await rpc('api_legacyCheck', [u, p]);
    if (!chk || !chk.ok) return false;
    var su = await sb.auth.signUp({ email: email(u), password: p, options: { data: { username: u } } });
    if (su.error) throw err('Username atau password salah.');
    if (!su.data.session) {
      var s = await sb.auth.signInWithPassword({ email: email(u), password: p });
      if (s.error) throw mapError(s.error);
    }
    await rpc('api_legacyClaim', [p]);
    return true;
  }
  var LOCAL = {
    api_authRegister: async function (u, p) {
      u = String(u || '').trim().toLowerCase(); validate(u, p);
      var av = await rpc('api_usernameAvailable', [u]);
      if (!av.available) throw err('Username "' + u + '" sudah dipakai. Pilih yang lain, atau masuk kalau itu akunmu.');
      var r = await sb.auth.signUp({ email: email(u), password: p, options: { data: { username: u } } });
      if (r.error) {
        if (/already registered|already exists/i.test(r.error.message)) throw err('Username "' + u + '" sudah dipakai. Pilih yang lain, atau masuk kalau itu akunmu.');
        throw mapError(r.error);
      }
      if (!r.data.session) {
        var s = await sb.auth.signInWithPassword({ email: email(u), password: p });
        if (s.error) throw err('Akun dibuat, tapi belum bisa masuk: ' + s.error.message + ' (pastikan "Confirm email" dimatikan di Supabase).');
      }
      return { token: 'sb', username: u, hasCharacter: false };
    },
    api_authLogin: async function (u, p) {
      u = String(u || '').trim().toLowerCase();
      if (!/^[a-z0-9_]{3,16}$/.test(u)) throw err('Username atau password salah.');
      var r = await sb.auth.signInWithPassword({ email: email(u), password: p });
      if (r.error && /invalid login|invalid credentials/i.test(r.error.message)) {
        // Pemain dari versi lama (Google Sheets)? Pindahkan kaptennya ke akun baru sekali saja.
        if (await legacyMove(u, p)) r = { error: null };
      }
      if (r.error) {
        if (/invalid login|invalid credentials/i.test(r.error.message)) throw err('Username atau password salah.');
        if (/rate limit|too many/i.test(r.error.message)) throw err('Terlalu banyak percobaan gagal. Coba lagi beberapa menit lagi.');
        throw mapError(r.error);
      }
      // Tide v43: masuk dengan sandi sementara dari GM -> pasang sandi baru sebelum lanjut
      var ps = null; try { ps = await rpc('api_pwStatus', []); } catch (e) {}
      if (ps && ps.must && window.MTPW) await MTPW.force(p);
      var who = await rpc('api_authWhoAmI', []);
      if (!who.hasCharacter) {
        // Pindah akun lama sempat terputus? Coba selesaikan klaimnya (diam-diam kalau tidak ada).
        try { await rpc('api_legacyClaim', [p]); who = await rpc('api_authWhoAmI', []); } catch (e) {}
      }
      return { token: 'sb', username: u, hasCharacter: !!who.hasCharacter };
    },
    api_authChangePassword: async function (oldPass, newPass) {
      var s = await sb.auth.getSession();
      var em = s.data.session && s.data.session.user.email;
      if (!em) throw err(AUTH_MSG);
      if (String(newPass || '').length < 6) throw err('Password minimal 6 karakter.');
      var chk = await sb.auth.signInWithPassword({ email: em, password: oldPass });
      if (chk.error) throw err('Password lama salah.');
      var up = await sb.auth.updateUser({ password: newPass });
      if (up.error) throw mapError(up.error);
      return { ok: true };
    },
    // Tide v43: ganti sandi wajib setelah reset GM (sandi lama = sandi sementara)
    api_pwForceChange: async function (oldPass, newPass) {
      var s = await sb.auth.getSession();
      var em = s.data.session && s.data.session.user.email;
      if (!em) throw err(AUTH_MSG);
      newPass = String(newPass || '');
      if (newPass.length < 6) throw err('Password minimal 6 karakter.');
      if (newPass.length > 72) throw err('Password terlalu panjang.');
      if (newPass === String(oldPass || '')) throw err('Sandi baru harus berbeda dari sandi sementara.');
      var chk = await sb.auth.signInWithPassword({ email: em, password: String(oldPass || '') });
      if (chk.error) throw err('Sandi sementara salah.');
      var up = await sb.auth.updateUser({ password: newPass });
      if (up.error) {
        if (/different from the old|same/i.test(up.error.message)) throw err('Sandi baru harus berbeda dari sandi sementara.');
        if (/weak|short|characters/i.test(up.error.message)) throw err('Sandi terlalu lemah. Pakai minimal 6 karakter, campur huruf dan angka.');
        throw mapError(up.error);
      }
      await rpc('api_pwChanged', []);
      return { ok: true };
    },
    api_rpc: function (name, args) { return call(name, args || []); }
  };
  function call(name, args) {
    // Perintah GM di kotak chat: "/gm pesan", "/gm! pesan", "/panel"
    if (name === 'api_mpChat' && window.MTGM && /^\s*\//.test(String(args && args[1] || ''))) return MTGM.chatCommand(args[1]);
    if (LOCAL[name]) return Promise.resolve().then(function () { return LOCAL[name].apply(null, args); });
    return rpc(name, args);
  }
  function runner(o) {
    return new Proxy({}, {
      get: function (_, prop) {
        if (prop === 'withSuccessHandler') return function (f) { return runner(Object.assign({}, o, { ok: f })); };
        if (prop === 'withFailureHandler') return function (f) { return runner(Object.assign({}, o, { fail: f })); };
        if (prop === 'withUserObject') return function (u) { return runner(Object.assign({}, o, { user: u })); };
        if (typeof prop !== 'string' || prop === 'then') return undefined;
        return function () {
          var args = Array.prototype.slice.call(arguments);
          call(prop, args).then(function (res) { if (o.ok) o.ok(res, o.user); },
            function (e) { var m = e instanceof Error ? e : mapError(e); if (window.console && !/^AUTH_REQUIRED/.test(m.message)) console.warn('[Marantau]', prop, m.message); if (o.fail) o.fail(m, o.user); });
        };
      }
    });
  }
  window.google = { script: { run: runner({}) } };

  // Sesi login tersimpan -> beri tahu lapisan MTNet (dipakai layar judul)
  var restored = null;
  try { var raw = localStorage.getItem('mt_sb_auth_v1'); if (raw) { var j = JSON.parse(raw); restored = j && j.user && j.user.email; } } catch (e) {}
  if (restored) {
    try { localStorage.setItem('mt_token_v1', 'sb'); localStorage.setItem('mt_user_v1', restored.split('@')[0]); } catch (e) {}
  } else {
    try { localStorage.removeItem('mt_token_v1'); localStorage.removeItem('mt_user_v1'); } catch (e) {}
  }
  // Keluar = hapus sesi Supabase juga
  document.addEventListener('DOMContentLoaded', function () {
    if (window.MTNet && MTNet.setToken && !MTNet._sbWrapped) {
      var orig = MTNet.setToken; MTNet._sbWrapped = true;
      MTNet.setToken = function (t, u) { orig(t, u); if (!t) sb.auth.signOut().catch(function () {}); };
    }
  });
})();

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
    if (code === '42501' || /permission denied|JWT expired|invalid JWT|jwt/i.test(m)) return err(AUTH_MSG);
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
    api_getarchetypes: 1, api_authwhoami: 1, api_usernameavailable: 1, api_legacycheck: 1 };
  async function rpc(name, args) {
    var fn = String(name).toLowerCase();
    if (!PUBLIC[fn]) {
      // Tunggu sesi tersimpan selesai dimuat; tanpa sesi -> minta login tanpa buang panggilan jaringan
      var s = await sb.auth.getSession();
      if (!s.data || !s.data.session) throw err(AUTH_MSG);
    }
    var r = await sb.rpc(fn, { a: args || [] });
    if (r.error) throw mapError(r.error);
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
    api_rpc: function (name, args) { return call(name, args || []); }
  };
  function call(name, args) {
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

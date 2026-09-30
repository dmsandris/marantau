/**
 * AuthService.gs  (Tide v6 - Multiplayer)
 * ------------------------------------------------------------------
 * Login berbasis AKUN GAME (username + password), bukan akun Google.
 *
 * Tujuannya: web app bisa di-deploy "Execute as: Me" + "Who has access:
 * Anyone", sehingga teman-teman TIDAK perlu memberi izin (OAuth) ke
 * Apps Script lagi. Semua eksekusi berjalan sebagai pemilik script.
 *
 * - Sheet "Accounts" dibuat otomatis: Username | PassHash | Salt |
 *   PlayerId | CreatedAt | LastLogin | Status
 * - Password disimpan sebagai hash SHA-256 bergaram, diulang
 *   HASH_ROUNDS kali (tidak pernah plaintext).
 * - Token sesi = payload.base64 + "." + HMAC-SHA256(secret) - stateless,
 *   berlaku TOKEN_DAYS hari. Secret di ScriptProperties "auth_secret".
 * - Percobaan login gagal dibatasi (CacheService) per username.
 * - Pemilik script yang sudah punya karakter lama (berbasis email)
 *   otomatis tersambung saat mendaftar akun pertama kali.
 * ------------------------------------------------------------------
 */

var AUTH_CTX_ = null;   // diisi api_rpc() selama satu eksekusi

var AuthService = (function () {
  var SHEET = 'Accounts';
  var HEADERS = ['Username', 'PassHash', 'Salt', 'PlayerId', 'CreatedAt', 'LastLogin', 'Status'];
  var HASH_ROUNDS = 250;
  var TOKEN_DAYS = 30;
  var MAX_FAILS = 8;

  function sheet_() {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sh = ss.getSheetByName(SHEET);
    if (!sh) {
      sh = ss.insertSheet(SHEET);
      sh.getRange(1, 1, 1, HEADERS.length).setValues([HEADERS]);
      sh.setFrozenRows(1);
    }
    return sh;
  }
  function rows_() { return sheet_().getDataRange().getValues(); }

  function hex_(bytes) {
    return bytes.map(function (b) { var v = (b < 0 ? b + 256 : b).toString(16); return v.length === 1 ? '0' + v : v; }).join('');
  }
  function hash_(password, salt) {
    var h = salt + '|' + password;
    for (var i = 0; i < HASH_ROUNDS; i++) {
      h = hex_(Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, h + '|' + salt, Utilities.Charset.UTF_8));
    }
    return h;
  }
  function secret_() {
    var props = PropertiesService.getScriptProperties();
    var s = props.getProperty('auth_secret');
    if (!s) { s = Utilities.getUuid() + Utilities.getUuid(); props.setProperty('auth_secret', s); }
    return s;
  }
  function b64_(s) { return Utilities.base64EncodeWebSafe(s, Utilities.Charset.UTF_8).replace(/=+$/, ''); }
  function unb64_(s) { while (s.length % 4) s += '='; return Utilities.newBlob(Utilities.base64DecodeWebSafe(s, Utilities.Charset.UTF_8)).getDataAsString(); }
  function sign_(payload) { return b64_(hex_(Utilities.computeHmacSha256Signature(payload, secret_(), Utilities.Charset.UTF_8))); }

  function makeToken_(playerId, username) {
    var payload = b64_(JSON.stringify({ p: playerId, u: username, e: Date.now() + TOKEN_DAYS * 864e5 }));
    return payload + '.' + sign_(payload);
  }

  /** @return {{playerId, username}|null} */
  function verify(token) {
    if (!token || typeof token !== 'string' || token.length > 2000) return null;
    var parts = token.split('.');
    if (parts.length !== 2) return null;
    if (sign_(parts[0]) !== parts[1]) return null;
    try {
      var o = JSON.parse(unb64_(parts[0]));
      if (!o.p || !o.e || o.e < Date.now()) return null;
      return { playerId: String(o.p), username: String(o.u || '') };
    } catch (e) { return null; }
  }

  function normUser_(u) { return String(u || '').trim().toLowerCase(); }
  function validate_(username, password) {
    if (!/^[a-z0-9_]{3,16}$/.test(username)) throw new Error('Username 3-16 karakter: huruf kecil, angka, atau garis bawah (_).');
    if (String(password || '').length < 6) throw new Error('Password minimal 6 karakter.');
    if (String(password).length > 72) throw new Error('Password terlalu panjang.');
  }
  function findRow_(data, username) {
    for (var i = 1; i < data.length; i++) if (normUser_(data[i][0]) === username) return i;
    return -1;
  }

  function register(username, password) {
    username = normUser_(username);
    validate_(username, password);
    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var sh = sheet_(), data = sh.getDataRange().getValues();
      if (findRow_(data, username) > 0) throw new Error('Username "' + username + '" sudah dipakai. Pilih yang lain, atau masuk kalau itu akunmu.');
      var playerId = 'acc:' + username;
      // Pemilik script / pemain lama berbasis email: sambungkan karakter lamanya.
      var email = '';
      try { email = String(Session.getActiveUser().getEmail() || '').trim().toLowerCase(); } catch (e) {}
      if (email) {
        var linked = false;
        for (var j = 1; j < data.length; j++) if (String(data[j][3]) === email) linked = true;
        if (!linked && PlayerService.getPlayerById(email)) playerId = email;
      }
      var salt = Utilities.getUuid();
      sh.appendRow([username, hash_(password, salt), salt, playerId, new Date(), new Date(), 'active']);
      PlayerService.ensurePlayerRow(playerId);
      return { token: makeToken_(playerId, username), username: username, linkedLegacy: playerId === email };
    } finally {
      lock.releaseLock();
    }
  }

  function login(username, password) {
    username = normUser_(username);
    var cache = CacheService.getScriptCache(), key = 'lf:' + username;
    var fails = Number(cache.get(key) || 0);
    if (fails >= MAX_FAILS) throw new Error('Terlalu banyak percobaan gagal. Coba lagi 10 menit lagi.');
    var sh = sheet_(), data = sh.getDataRange().getValues(), i = findRow_(data, username);
    if (i < 0 || hash_(String(password || ''), String(data[i][2])) !== String(data[i][1])) {
      cache.put(key, String(fails + 1), 600);
      throw new Error('Username atau password salah.');
    }
    if (String(data[i][6] || 'active') === 'banned') throw new Error('Akun ini dinonaktifkan admin.');
    cache.remove(key);
    try { sh.getRange(i + 1, 6).setValue(new Date()); } catch (e) {}
    var playerId = String(data[i][3]);
    PlayerService.ensurePlayerRow(playerId);
    return { token: makeToken_(playerId, username), username: username };
  }

  function changePassword(ctx, oldPass, newPass) {
    if (!ctx) throw new Error('AUTH_REQUIRED: Silakan masuk dulu.');
    validate_(ctx.username, newPass);
    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var sh = sheet_(), data = sh.getDataRange().getValues(), i = findRow_(data, ctx.username);
      if (i < 0) throw new Error('Akun tidak ditemukan.');
      if (hash_(String(oldPass || ''), String(data[i][2])) !== String(data[i][1])) throw new Error('Password lama salah.');
      var salt = Utilities.getUuid();
      sh.getRange(i + 1, 2, 1, 2).setValues([[hash_(newPass, salt), salt]]);
      return { ok: true };
    } finally {
      lock.releaseLock();
    }
  }

  /** Admin (jalankan dari editor): reset password pemain yang lupa. */
  function adminResetPassword(username, newPass) {
    username = normUser_(username);
    validate_(username, newPass);
    var sh = sheet_(), data = sh.getDataRange().getValues(), i = findRow_(data, username);
    if (i < 0) throw new Error('Akun tidak ditemukan: ' + username);
    var salt = Utilities.getUuid();
    sh.getRange(i + 1, 2, 1, 2).setValues([[hash_(newPass, salt), salt]]);
    return 'Password ' + username + ' direset.';
  }

  /** Admin: sambungkan akun ke karakter lama berbasis email (migrasi). */
  function adminLinkAccountToPlayer(username, playerId) {
    username = normUser_(username);
    var sh = sheet_(), data = sh.getDataRange().getValues(), i = findRow_(data, username);
    if (i < 0) throw new Error('Akun tidak ditemukan: ' + username);
    if (!PlayerService.getPlayerById(playerId)) throw new Error('PlayerId tidak ditemukan di sheet Players: ' + playerId);
    sh.getRange(i + 1, 4).setValue(playerId);
    return username + ' sekarang memakai karakter ' + playerId;
  }

  return { verify: verify, register: register, login: login, changePassword: changePassword, adminResetPassword: adminResetPassword, adminLinkAccountToPlayer: adminLinkAccountToPlayer };
})();

/* ---- fungsi admin yang bisa di-Run dari editor Apps Script ---- */
function adminResetPassword(username, newPass) { requireOwner_(); return AuthService.adminResetPassword(username, newPass); }
function adminLinkAccountToPlayer(username, playerId) { requireOwner_(); return AuthService.adminLinkAccountToPlayer(username, playerId); }

// Tes unit tanpa database/jaringan: penjagaan jalur & rahasia PR, pengaturan profil. Jalankan: node --test test/unit.test.js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
process.env.OPS_PG_HOST = '127.0.0.1';
const tools = require('../tools');
const settings = require('../settings');

test('checkFiles menolak jalur dan isi berbahaya', () => {
  const bad = [
    { path: '.github/workflows/x.yml', content: 'a' }, { path: 'a/.env', content: 'a' }, { path: '../x.sql', content: 'a' },
    { path: 'a.sql', content: 'ghp_' + 'a'.repeat(36) }, { path: 'a.sql', content: '-----BEGIN PRIVATE KEY-----' }, { path: 'a.exe', content: 'a' },
    { path: 'deploy/selfhost/volumes/x.sql', content: 'a' },
  ];
  for (const f of bad) assert.throws(() => tools.checkFiles([f]), undefined, f.path);
  assert.throws(() => tools.checkFiles([]));
  assert.throws(() => tools.checkFiles(Array.from({ length: 13 }, (_, i) => ({ path: `a${i}.sql`, content: 'x' }))));
  assert.throws(() => tools.checkFiles([{ path: 'a.sql', content: 'x' }, { path: 'a.sql', content: 'y' }]));
});
test('checkFiles menerima migrasi biasa', () => {
  const r = tools.checkFiles([{ path: 'supabase/migrations/0108-hadiah.sql', content: 'select 1;' }]);
  assert.strictEqual(r[0].path, 'supabase/migrations/0108-hadiah.sql');
});
test('safePath menolak traversal dan .git', () => {
  assert.throws(() => tools.safePath('../a')); assert.throws(() => tools.safePath('a/.git/config'));
  assert.strictEqual(tools.safePath('/a/b/'), 'a/b');
});
test('pengaturan: kunci tak pernah keluar utuh, kunci lama dipertahankan, peran dibersihkan', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wb-'));
  const s = settings.create(dir, {});
  s.ubah({ profiles: [{ id: 'a', label: 'A', provider: 'anthropic', model: 'claude-opus-5-5', key: 'sk-ant-SECRETSECRETSECRET1234' }, { id: 'b', label: 'B', provider: 'gemini', model: 'gemini-2.5-pro', key: 'AIzaSECRET' }], roles: { orkestrator: 'a', gambar: 'b' } });
  assert.ok(!JSON.stringify(s.publik()).includes('SECRET'));
  s.ubah({ profiles: [{ id: 'a', label: 'A2', provider: 'anthropic', model: 'claude-opus-5-5' }] });
  assert.strictEqual(s.profile('a').key, 'sk-ant-SECRETSECRETSECRET1234');
  assert.strictEqual(s.get().roles.gambar, '');           // profil b dihapus -> peran dikosongkan
  assert.strictEqual(s.forRole('coder').id, 'a');           // peran kosong -> ikut orkestrator
  assert.strictEqual(s.forRole('gambar'), null);            // gambar tidak jatuh ke orkestrator
  assert.strictEqual(fs.statSync(path.join(dir, 'wb-settings.json')).mode & 0o777, 0o600);
  s.ubah({ profiles: [{ id: 'x', label: 'X', provider: 'openai', model: 'm1', baseUrl: 'http://evil', key: 'k' }] });
  assert.strictEqual(s.profile('x').baseUrl, '');           // hanya https
});

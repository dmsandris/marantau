// Jalankan semua tes (test/0*.test.js) berurutan. Keluar kode 1 bila ada yang gagal.
const { execFileSync } = require('child_process'), fs = require('fs'), path = require('path');
const dir = path.join(__dirname, '..', 'test');
let bad = 0;
for (const f of fs.readdirSync(dir).filter(f => /^0.*\.test\.js$/.test(f)).sort()) {
  process.stdout.write(f.padEnd(34));
  const run = () => execFileSync('node', [path.join(dir, f)], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  try { console.log('OK  ' + run().trim().split('\n').pop()); }
  catch (e) {
    // Tes combat memakai angka acak: ulang sekali sebelum dianggap gagal (dicatat sebagai flaky)
    try { console.log('OK  (percobaan ke-2, flaky) ' + run().trim().split('\n').pop()); console.log((e.stdout || '').split('\n').slice(-3).join('\n') + (e.stderr || '').slice(0, 600)); }
    catch (e2) { bad++; console.log('GAGAL'); console.log((e2.stdout || '') + (e2.stderr || '')); }
  }
}
if (bad) { console.error(bad + ' tes gagal.'); process.exit(1); }
console.log('Semua tes lulus.');

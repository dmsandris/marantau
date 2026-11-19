-- =====================================================================
-- 0093 · UX Saga 4: kabut menuju Zentul dibaca saat sauh diangkat
--   Dulu langkah 10 adalah langkah KEDATANGAN: pemain sudah merapat di Zentul,
--   baru disuruh "mencari arah" lewat Jaring Angin, lalu sinematik kabut terbuka.
--   Urutannya terbalik. Sekarang:
--     langkah 10  = di laut, saat haluan diarahkan ke Zentul (tanpa syarat kota)
--     langkah 11  = Lapau Oli, dengan sinematik mk_zentul diputar saat merapat
--   Aturan lain tidak berubah.
-- Aman diulang.
-- =====================================================================

create or replace function game.mk_steps() returns jsonb
language sql immutable as $$
  select '[
    {"n":1,"q":15,"p":"kota","b":"surat"},
    {"n":2,"q":15,"c":"ikn","p":"monumen","b":"dekret","g":"pantun","krisis":true},
    {"n":3,"q":15,"c":"ikn","p":"kamp","b":"jurutulis","g":"warga"},
    {"n":4,"q":15,"c":"joungjava","p":"syahbandar","b":"antrean","g":"syahbandar"},
    {"n":5,"q":15,"c":"joungjava","p":"warung","b":"dekretsalin"},
    {"n":6,"q":15,"c":"toogood","p":"dok","b":"blackpearl","cine":"mk_pantul"},
    {"n":7,"q":15,"c":"toogood","p":"alley","t":"malam","b":"hasiolan","g":"kuli","gold":"MkGoldQ15"},
    {"n":8,"q":16,"c":"paradiso","p":"vip","t":"malam","b":"rimba","g":"dadu"},
    {"n":9,"q":16,"c":"paradiso","p":"vip","b":"peta","g":"tercecer","zentul":true},
    {"n":10,"q":16,"p":"laut","b":"kabut","g":"angin"},
    {"n":11,"q":16,"c":"zentul","p":"lapau","b":"daftar","cine":"mk_zentul"},
    {"n":12,"q":16,"c":"zentul","p":"sirkuit","b":"babak1","race":"pariopelan","garasi":true},
    {"n":13,"q":16,"c":"zentul","p":"garasi","b":"kencang"},
    {"n":14,"q":16,"c":"zentul","p":"pasar","b":"sukucadang","g":"manifest"},
    {"n":15,"q":16,"c":"zentul","p":"garasi","b":"katup","g":"tempa","jolt":true,"gold":"MkGoldQ16"},
    {"n":16,"q":17,"c":"zentul","p":"sirkuit","b":"babak1ulang","race":"pariopelan","win":true,"hint":3},
    {"n":17,"q":17,"c":"zentul","p":"sirkuit","b":"semifinal","race":"kapalmber","win":true,"kiat":3},
    {"n":18,"q":17,"c":"zentul","p":"garasi","b":"lapor"},
    {"n":19,"q":17,"c":"skitraw","p":"galangan","b":"polarantai","g":"sandi"},
    {"n":20,"q":17,"c":"bjorneo","p":"mercusuar","b":"nenekulin","teka":true,"flags":{"tembus":true,"paksa":true,"aman":true}},
    {"n":21,"q":17,"p":"tembus","b":"tembus","arr":true,"zona":true},
    {"n":22,"q":17,"p":"pasar","b":"agen","g":"timbang","zonaHere":true,"flags":{"gelap":true,"paksa":false,"aman":false}},
    {"n":23,"q":17,"c":"paradiso","p":"vip","t":"malam","b":"lapor2","gold":"MkGoldQ17","tanda":"duadetik"},
    {"n":24,"q":18,"c":"marie_regal","p":"lab","t":"malam","b":"rakbatu","g":"warga"},
    {"n":25,"q":18,"c":"marie_regal","p":"istana","t":"malam","b":"marlya","pilih":["maafkan","kabarkan"]},
    {"n":26,"q":18,"c":"zentul","p":"tiba","b":"selam","g":"selam","arr":true},
    {"n":27,"q":18,"c":"zentul","p":"garasi","b":"batubaterai","penuh":true,"warlord":true},
    {"n":28,"q":18,"c":"zentul","p":"sirkuit","b":"gerbang","race":"pariopelan","targetUs":"MkGerbangUs"},
    {"n":29,"q":18,"c":"zentul","p":"sirkuit","b":"final","race":"cangcimen_final","win":true,"kiat":3,"juara":true},
    {"n":30,"q":18,"c":"zentul","p":"dermaga","b":"barisan","g":"susun","flags":{"paksa":true,"aman":true}},
    {"n":31,"q":18,"p":"banjir","b":"banjir1","g":"pesta","zona":true,"setor":true},
    {"n":32,"q":18,"p":"banjir","b":"banjir2","g":"jejak","zona":true,"setor":true},
    {"n":33,"q":18,"p":"banjir","b":"banjir3","g":"kas","zona":true,"setor":true,"gold":"MkGoldQ18","tanda":"banjirsutra","flags":{"paksa":false,"aman":false}},
    {"n":34,"q":19,"c":"ikn","p":"monumen","b":"hadapi","cine":"mk_benteng"},
    {"n":35,"q":19,"c":"toogood","p":"dok","b":"pengalih","setorBahan":true},
    {"n":36,"q":19,"c":"paradiso","p":"dermaga","b":"genderang","g":"genderang","ulang":true},
    {"n":37,"q":19,"c":"ikn","p":"heat","b":"heat1","race":"patroli_kuat","win":true,"heat":true,"arr":true},
    {"n":38,"q":19,"c":"ikn","p":"heat","b":"heat2","race":"patroli_kuat","win":true,"heat":true,"lewatiBila":"kabarkan"},
    {"n":39,"q":19,"c":"ikn","p":"heat","b":"heat3","race":"cangcimen_final","win":true,"heat":true,"lebarBila":"maafkan","cine":"mk_rantai"},
    {"n":40,"q":19,"c":"ikn","p":"dermaga","b":"stempel","pilih":["patahkan","dewan","marlya"],"gold":"MkGoldQ19","tanda":"sagakeempat","tamat":true}
  ]'::jsonb
$$;

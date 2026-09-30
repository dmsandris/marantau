/**
 * BankService.gs
 * ------------------------------------------------------------------
 * Disadur dari Tradewinds 2: Bank (simpan uang, bunga majemuk kecil)
 * dan Moneylender (pinjam uang, bunga majemuk besar) - lihat
 * TRADEWINDS2_RESEARCH.md. Digabung jadi satu service & satu panel UI
 * ("Bank") supaya sidebar tidak terlalu ramai tombol.
 *
 * Bunga dihitung LAZY (baru di-apply saat state dibaca/diubah), bukan
 * lewat trigger terjadwal - konsisten dengan filosofi TimeService.gs
 * (hari-game dihitung ulang dari timestamp, bukan counter yang bisa
 * telat/di-skip). Setiap kali accrue_() dipanggil, bunga dihitung dari
 * selisih hari-game sejak accrual terakhir, lalu ditulis balik.
 *
 * Data disimpan langsung di sheet Players (4 kolom tambahan):
 *   BankBalance, BankLastInterestGameDay, DebtBalance, DebtLastInterestGameDay
 * ------------------------------------------------------------------
 */

var BankService = (function () {

  function getPlayersSheet_() {
    return SheetCache.getSheet('Players');
  }

  /** Hitung & terapkan bunga majemuk sejak accrual terakhir, kembalikan state terbaru. */
  function accrue_(playerId) {
    var sheet = getPlayersSheet_();
    var data = SheetCache.getData('Players');
    var headers = data[0];

    var bankCol = headers.indexOf('BankBalance');
    var bankDayCol = headers.indexOf('BankLastInterestGameDay');
    var debtCol = headers.indexOf('DebtBalance');
    var debtDayCol = headers.indexOf('DebtLastInterestGameDay');

    if (bankCol === -1 || debtCol === -1) {
      // Kolom belum ada = admin belum jalankan migrateTW2Improvements().
      // Jangan lempar error di sini - fungsi ini dipanggil dari
      // api_getGameState() setiap load, kalau throw maka SELURUH game
      // ikut rusak padahal cuma fitur Bank yang belum siap. Kembalikan
      // state kosong yang aman, tandai belum siap lewat `migrated: false`.
      return {
        bankBalance: 0, debtBalance: 0, bankRatePercent: 0, debtRatePercent: 0,
        maxDebt: 0, migrated: false
      };
    }

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId) {
        var gameDay = TimeService.getCurrentGameDay();

        var bankBalance = Number(data[i][bankCol]) || 0;
        var bankLastDay = Number(data[i][bankDayCol]) || gameDay;
        var debtBalance = Number(data[i][debtCol]) || 0;
        var debtLastDay = Number(data[i][debtDayCol]) || gameDay;

        var bankRatePercent = getGameConfigNumber_('BankInterestRatePercent', 0.5);
        var debtRatePercent = getGameConfigNumber_('DebtInterestRatePercent', 2);

        var bankDays = Math.max(0, gameDay - bankLastDay);
        var debtDays = Math.max(0, gameDay - debtLastDay);
        var wroteAnything = false;

        if (bankDays > 0) {
          if (bankBalance > 0) {
            bankBalance = bankBalance * Math.pow(1 + bankRatePercent / 100, bankDays);
            sheet.getRange(i + 1, bankCol + 1).setValue(Math.round(bankBalance));
          }
          sheet.getRange(i + 1, bankDayCol + 1).setValue(gameDay);
          wroteAnything = true;
        }

        if (debtDays > 0) {
          if (debtBalance > 0) {
            debtBalance = debtBalance * Math.pow(1 + debtRatePercent / 100, debtDays);
            sheet.getRange(i + 1, debtCol + 1).setValue(Math.round(debtBalance));
          }
          sheet.getRange(i + 1, debtDayCol + 1).setValue(gameDay);
          wroteAnything = true;
        }

        if (wroteAnything) SheetCache.invalidate('Players');

        return {
          bankBalance: Math.round(bankBalance),
          debtBalance: Math.round(debtBalance),
          bankRatePercent: bankRatePercent,
          debtRatePercent: debtRatePercent,
          maxDebt: getGameConfigNumber_('MaxDebtAmount', 5000),
          migrated: true
        };
      }
    }
    throw new Error('Player ' + playerId + ' tidak ditemukan.');
  }

  function setColumn_(playerId, colName, value) {
    var sheet = getPlayersSheet_();
    var data = SheetCache.getData('Players');
    var headers = data[0];
    var col = headers.indexOf(colName);
    if (col === -1) throw new Error('Kolom ' + colName + ' tidak ditemukan.');

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === playerId) {
        sheet.getRange(i + 1, col + 1).setValue(value);
        SheetCache.invalidate('Players');
        return;
      }
    }
    throw new Error('Player ' + playerId + ' tidak ditemukan.');
  }

  function getState(playerId) {
    return accrue_(playerId);
  }

  function deposit(amount) {
    amount = Math.floor(Number(amount));
    if (!amount || amount <= 0) throw new Error('Jumlah setor tidak valid.');

    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var state = accrue_(playerId);
      if (!state.migrated) throw new Error('Fitur Bank belum siap - admin perlu menjalankan migrateTW2Improvements() dulu.');
      var player = PlayerService.getOrCreatePlayer();
      if (player.gold < amount) throw new Error('Gold tidak cukup.');

      setColumn_(playerId, 'BankBalance', state.bankBalance + amount);
      PlayerService.updatePlayerRow(playerId, { Gold: player.gold - amount });
      LogService.addLog(playerId, 'Deposited ' + amount + ' gold at the Bank.');

      var result = getState(playerId);
      result.newGold = player.gold - amount;
      return result;
    } finally {
      lock.releaseLock();
    }
  }

  function withdraw(amount) {
    amount = Math.floor(Number(amount));
    if (!amount || amount <= 0) throw new Error('Jumlah tarik tidak valid.');

    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var state = accrue_(playerId);
      if (!state.migrated) throw new Error('Fitur Bank belum siap - admin perlu menjalankan migrateTW2Improvements() dulu.');
      if (state.bankBalance < amount) throw new Error('Saldo Bank tidak cukup.');

      setColumn_(playerId, 'BankBalance', state.bankBalance - amount);
      var player = PlayerService.getOrCreatePlayer();
      PlayerService.updatePlayerRow(playerId, { Gold: player.gold + amount });
      LogService.addLog(playerId, 'Withdrew ' + amount + ' gold from the Bank.');

      var result = getState(playerId);
      result.newGold = player.gold + amount;
      return result;
    } finally {
      lock.releaseLock();
    }
  }

  function borrow(amount) {
    amount = Math.floor(Number(amount));
    if (!amount || amount <= 0) throw new Error('Jumlah pinjam tidak valid.');

    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var state = accrue_(playerId);
      if (!state.migrated) throw new Error('Fitur Moneylender belum siap - admin perlu menjalankan migrateTW2Improvements() dulu.');
      if (state.debtBalance + amount > state.maxDebt) {
        throw new Error('Melebihi batas pinjaman Moneylender (maksimum utang ' + state.maxDebt + ' gold).');
      }

      setColumn_(playerId, 'DebtBalance', state.debtBalance + amount);
      var player = PlayerService.getOrCreatePlayer();
      PlayerService.updatePlayerRow(playerId, { Gold: player.gold + amount });
      LogService.addLog(playerId, 'Borrowed ' + amount + ' gold from the Moneylender.');

      var result = getState(playerId);
      result.newGold = player.gold + amount;
      return result;
    } finally {
      lock.releaseLock();
    }
  }

  function repay(amount) {
    amount = Math.floor(Number(amount));
    if (!amount || amount <= 0) throw new Error('Jumlah bayar tidak valid.');

    var lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      var playerId = PlayerService.getCurrentPlayerId();
      var state = accrue_(playerId);
      var player = PlayerService.getOrCreatePlayer();
      var payAmount = Math.min(amount, state.debtBalance, player.gold);
      if (payAmount <= 0) throw new Error('Tidak ada yang bisa dibayar (cek gold atau utangmu).');

      setColumn_(playerId, 'DebtBalance', state.debtBalance - payAmount);
      PlayerService.updatePlayerRow(playerId, { Gold: player.gold - payAmount });
      LogService.addLog(playerId, 'Repaid ' + payAmount + ' gold to the Moneylender.');

      var result = getState(playerId);
      result.newGold = player.gold - payAmount;
      return result;
    } finally {
      lock.releaseLock();
    }
  }

  return {
    getState: getState,
    deposit: deposit,
    withdraw: withdraw,
    borrow: borrow,
    repay: repay
  };
})();

// CANLI kripto kanaryası — gerçek ağa çıkar; `supabase/tests/` DIŞINDA.
// `.github/workflows/price-canary.yml` haftalık koşar.
//
// Neyi korur: `_shared/kripto.ts` Binance yanıt BİÇİMİNE güveniyor
// (tradingDay alanları, kline dizisi, belgesiz varlık listesi `data[]`).
// Biçim değişirse kripto-fiyat HTTP 200 dönerken sıfır satır yazar —
// sessiz arıza.
//
// ⚠️ GitHub runner'ları ABD'de. Binance ABD IP'lerine 451 döner; bu durumda
// testler atlanır (uyarı basılır). Üretimdeki fonksiyon Frankfurt'ta koşar.
import { assert } from 'jsr:@std/assert@1';
import {
  binanceVarliklari,
  fiyatlariHesapla,
  gunSatirlariniCek,
  mumlariCek,
} from '../functions/_shared/kripto.ts';

async function binanceErisilebilirMi(): Promise<boolean> {
  try {
    const res = await fetch('https://data-api.binance.vision/api/v3/ping', {
      signal: AbortSignal.timeout(10_000),
    });
    await res.body?.cancel();
    if (res.status === 451 || res.status === 403) {
      console.warn(`Binance bu bölgeden erişilemez (${res.status}); Binance testi atlandı.`);
      return false;
    }
    return res.ok;
  } catch (_) {
    return false;
  }
}

Deno.test('Binance tradingDay + klines: BTCTRY ve USDTTRY fiyatlanır', async () => {
  if (!(await binanceErisilebilirMi())) return;
  const { satirlar, basarili } = await gunSatirlariniCek([['BTCTRY', 'SOLUSDT', 'USDTTRY']]);
  assert(basarili === 1, 'tradingDay yanıt vermedi');
  const fiyat = fiyatlariHesapla([
    { kod: 'BTC', parite: 'TRY', binance_sembol: 'BTCTRY' },
    { kod: 'SOL', parite: 'USDT', binance_sembol: 'SOLUSDT' },
  ], satirlar, new Date());
  assert(fiyat.length === 2, `beklenen 2 satır, gelen ${fiyat.length}`);
  for (const f of fiyat) {
    assert(f.fiyat_try > 0 && f.gun_acilis_try !== null, `${f.kod} eksik`);
  }
  // BTC ≥ 100.000 TL: birim/ölçek hatası (ör. kuruş) yakalansın.
  assert(fiyat.find((f) => f.kod === 'BTC')!.fiyat_try > 100_000);

  const simdi = Date.now();
  const mum = await mumlariCek('BTCTRY', '1h', simdi - 24 * 3600_000, simdi);
  assert(mum !== null && mum.length >= 20, 'kline serisi kısa/boş');
});

Deno.test('Binance varlık listesi: BTC adı ve https logosu', async () => {
  if (!(await binanceErisilebilirMi())) return;
  const v = await binanceVarliklari();
  const btc = v.find((x) => x.assetCode === 'BTC');
  assert(btc?.assetName, 'varlık listesinde BTC adı yok (biçim değişmiş olabilir)');
  assert(String(btc?.logoUrl ?? '').startsWith('https://'), 'BTC logosu https değil');
});

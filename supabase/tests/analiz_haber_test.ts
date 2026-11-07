// Aylık nota haber (0177) — `_shared/analiz_haber.ts` saf yardımcılarının testleri.
//
// ## Bu dosyanın kovaladığı şeyler
// 1. **Fail-closed bayrak.** Yalnız tam "1" açar.
// 2. **Kişisel veri yok.** İstek yalnız sembol, tür ve ayın tarihlerini
//    taşır; ölçüm, miktar, ad gitmez. Varlık başına en çok 2 arama.
// 3. **Kapı.** Rakamlı, alıntılı, SPK dilli, ay dışı ya da aramada dönmeyen
//    bağlantılı madde düşer; düşen madde notun geri kalanını düşürmez.
// 4. **Maliyet.** Arama (indirimsiz 0,01 $) token maliyetine eklenir;
//    tavan tahmini haber batch'ini durdurur.
//
// Çalıştır:
//   deno test --allow-all supabase/tests/analiz_haber_test.ts

import { assert, assertEquals } from 'jsr:@std/assert@1';
import { maliyetUsd, Paket } from '../functions/_shared/analiz.ts';
import {
  aramaAdresleri,
  HABER_ARACI,
  haberAcikMi,
  haberGirdisi,
  haberIstegi,
  haberKapisi,
  haberMesaji,
  haberSonucu,
  haberTavaniUygun,
} from '../functions/_shared/analiz_haber.ts';

const AY = { baslangic: '2026-10-01', bitis: '2026-10-31' };

const paket: Paket = {
  ticker: 'THYAO.IS', kod: 'THYAO', varlik: 'hisse', kategori: null, tur: 'aylik',
  baslangic: '2026-10-01', bitis: '2026-10-30', rozet: 'sakin',
  olcumler: [{ anahtar: 'fiyat_degisim', deger: 0.031, gosterim: '+%3,1', ad: 'Aylık değişim',
    kaynak: 'Yahoo Finance', tarih: '2026-10-30' }],
  olaylar: [],
};
const girdi = haberGirdisi(paket, AY);

Deno.test('bayrak: yalnız tam "1" açar', () => {
  assert(haberAcikMi('1'));
  for (const d of [undefined, null, '', '0', 'true', ' 1', '1 ', 'evet']) assert(!haberAcikMi(d));
});

Deno.test('istek: yalnız sembol + tür + ayın tarihleri; en çok 2 arama; zorunlu araç yok', () => {
  const g = haberIstegi(paket, AY, 'claude-sonnet-5-5');
  const mesaj = haberMesaji(paket, AY);
  assertEquals(mesaj, 'Varlık: THYAO (Borsa İstanbul hissesi)\nAy: 2026-10-01 – 2026-10-31 (1 Eki – 31 Eki)');
  // Ölçüm paketi (gösterimler, anahtarlar) haber isteğine gitmez.
  assert(!JSON.stringify(g.messages).includes('%3,1'));
  assert(!JSON.stringify(g.messages).includes('fiyat_degisim'));
  const tools = g.tools as Array<Record<string, unknown>>;
  assertEquals(tools[0].type, 'web_search_20260209');
  assertEquals(tools[0].max_uses, 2);
  assertEquals(tools[0].allowed_callers, ['direct']);
  assertEquals(tools[1].name, HABER_ARACI.name);
  assertEquals(tools[1].strict, true);
  // Sonnet 5.5'te zorunlu araç 400 döner; yapılandırılmış çıktı alıntılarla çakışır.
  assertEquals(g.tool_choice, { type: 'auto' });
  assertEquals((g.output_config as Record<string, unknown>).format, undefined);
  assertEquals(girdi, { ticker: 'THYAO.IS', kod: 'THYAO', baslangic: '2026-10-01', bitis: '2026-10-31' });
});

const ADRES = 'https://www.aa.com.tr/tr/ekonomi/thy-filo/123';
const adresler = new Set([ADRES]);
const iyi = {
  ozet: 'THYAO yeni geniş gövdeli uçak siparişini kesinleştirdiğini duyurdu ve teslimat takvimini paylaştı.',
  kaynak: 'Anadolu Ajansı', url: ADRES, tarih: '2026-10-14',
};

Deno.test('kapı: geçerli madde geçer; kaynak adı bozuksa alan adı yazılır', () => {
  // "kesinleştirdi" YASAK'taki "kesin" kelime sınırına takılmaz.
  const k = haberKapisi({ haberler: [iyi] }, girdi, adresler);
  assertEquals(k.red, []);
  assertEquals(k.haberler, [{ metin: iyi.ozet, kaynak: 'Anadolu Ajansı', url: ADRES, tarih: '2026-10-14' }]);
  const k2 = haberKapisi({ haberler: [{ ...iyi, kaynak: '' }] }, girdi, adresler);
  assertEquals(k2.haberler[0].kaynak, 'aa.com.tr');
  // Sondaki '/' farkı aynı sayfa.
  const k3 = haberKapisi({ haberler: [{ ...iyi, url: `${ADRES}/` }] }, girdi, adresler);
  assertEquals(k3.haberler.length, 1);
});

Deno.test('kapı: rakam, alıntı, SPK dili, ay dışı, uydurma bağlantı düşer — tek tek', () => {
  const durumlar: Array<[Record<string, unknown>, string]> = [
    [{ ...iyi, ozet: 'THYAO yüzde 12 artan yolcu sayısıyla rekor kırdığını açıkladı, yönetim memnun.' }, 'sayi'],
    [{ ...iyi, ozet: 'THYAO yönetimi “büyüme sürecek” dedi ve yeni uçak siparişlerini kamuoyuna duyurdu.' }, 'alinti'],
    [{ ...iyi, ozet: 'THYAO yeni siparişle birlikte yatırımcılar için önemli bir fırsat sunan bir adım attı.' }, 'dil'],
    [{ ...iyi, ozet: 'THYAO hissesinin volatilite düzeyi uçak siparişi haberiyle birlikte belirgin biçimde değişti.' }, 'terim'],
    [{ ...iyi, tarih: '2026-09-30' }, 'tarih'],
    [{ ...iyi, url: 'https://uydurma.example.com/haber' }, 'url: aramada'],
    [{ ...iyi, url: 'http://www.aa.com.tr/tr/ekonomi/thy-filo/123' }, 'url: https'],
    [{ ...iyi, ozet: 'kısa' }, 'yapi'],
  ];
  for (const [h, neden] of durumlar) {
    const k = haberKapisi({ haberler: [h, iyi] }, girdi, adresler);
    assert(k.red[0].startsWith(neden), `${neden} beklendi: ${k.red[0]}`);
    // Düşen madde öbürünü düşürmez.
    assertEquals(k.haberler.length, 1);
  }
});

Deno.test('kapı: kodun kendi rakamı serbest; aynı bağlantı iki kez yazılmaz; en çok 2', () => {
  const isin = haberGirdisi({ ...paket, ticker: 'EUROBOND:XS2350000000', kod: 'XS2350000000' }, AY);
  const k = haberKapisi({
    haberler: [{ ...iyi, ozet: 'XS2350000000 kodlu tahvilin ihraççısı erken itfa kararını açıkladı.' }],
  }, isin, adresler);
  assertEquals(k.haberler.length, 1);
  const iki = new Set([ADRES, 'https://a.com/x', 'https://b.com/y']);
  const k2 = haberKapisi({
    haberler: [iyi, iyi, { ...iyi, url: 'https://a.com/x' }, { ...iyi, url: 'https://b.com/y' }],
  }, girdi, iki);
  assertEquals(k2.haberler.map((h) => h.url), [ADRES, 'https://a.com/x']);
  assertEquals(k2.red, ['url: tekrar', 'fazla']);
});

const yanit = (icerik: Array<{ type: string; [k: string]: unknown }>, stop = 'tool_use', aramalar = 2) => ({
  type: 'succeeded',
  message: {
    stop_reason: stop,
    content: icerik,
    usage: { input_tokens: 20_000, output_tokens: 1_000, server_tool_use: { web_search_requests: aramalar } },
  },
});
const aramaBlogu = {
  type: 'web_search_tool_result',
  content: [{ type: 'web_search_result', url: ADRES, title: 'THY filo', encrypted_content: 'x' }],
};

Deno.test('sonuç: arama adresleri; araç çağrısı kapıdan geçer; maliyet aramayı sayar', () => {
  assertEquals(aramaAdresleri([aramaBlogu, { type: 'web_search_tool_result', content: { error_code: 'x' } }]),
    new Set(['https://www.aa.com.tr/tr/ekonomi/thy-filo/123']));
  const s = haberSonucu(girdi, 'claude-sonnet-5-5', yanit([
    { type: 'server_tool_use', name: 'web_search', input: { query: 'THYAO Ekim 2026' } },
    aramaBlogu,
    { type: 'tool_use', name: 'haberleri_kaydet', input: { haberler: [iyi] } },
  ]));
  assertEquals(s.haberler.length, 1);
  assertEquals(s.red, null);
  assertEquals(s.aramalar, 2);
  // Token: (20K×2 + 1K×10)/1e6 × 0,5 = 0,025; arama 2 × 0,01 = 0,02.
  assertEquals(s.maliyet, 0.045);
});

Deno.test('sonuç: pause_turn / ret / araçsız biter → haber yok, maliyet yine sayılır', () => {
  for (const stop of ['pause_turn', 'refusal', 'max_tokens']) {
    const s = haberSonucu(girdi, 'claude-sonnet-5-5', yanit([aramaBlogu], stop));
    assertEquals(s.haberler, []);
    assertEquals(s.red, `stop_reason: ${stop}`);
    assert((s.maliyet ?? 0) > 0);
  }
  assertEquals(haberSonucu(girdi, 'claude-sonnet-5-5', yanit([], 'end_turn', 0)).red, 'arac: cagrilmadi');
  assertEquals(haberSonucu(girdi, 'claude-sonnet-5-5', { type: 'expired' }).red, 'batch: expired');
});

Deno.test('maliyet: arama indirimsiz eklenir; aramasız eski hesap aynen', () => {
  assertEquals(maliyetUsd('claude-sonnet-5-5', { input_tokens: 1e6, output_tokens: 1e6 }), 6);
  assertEquals(maliyetUsd('claude-sonnet-5-5', { server_tool_use: { web_search_requests: 600 } }), 6);
});

Deno.test('tavan: haber tahmini tavanı aşacaksa gönderilmez; tavan 0 sınırsız', () => {
  assert(haberTavaniUygun(10, 50, 300)); // 10 + 300 × 0,06 = 28
  assert(!haberTavaniUygun(40, 50, 300)); // 40 + 18 = 58
  assert(haberTavaniUygun(999, 0, 300));
});

// Ekstre AI sütun eşleme — `_shared/ekstre_esleme.ts` testleri (0121).
//
// Kovaladığı şeyler:
// 1. **Maskesiz rakam modele gitmez.** İskelet hücrelerinde 9'dan başka
//    rakam varsa istek reddedilir.
// 2. **Model sayı uyduramaz.** Olmayan tablo/sütun, aynı sütuna iki rol,
//    sembolsüz ya da adetsiz tablo düşer.
//
// Çalıştır:
//   deno test --allow-all supabase/tests/ekstre_esleme_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  adayIzler,
  baslikIzi,
  hataOzeti,
  ILK_SATIR,
  istekGovdesi,
  iskeletiDogrula,
  izOzeti,
  METIN_ILK_SATIR,
  type Sablon,
  sablonlaEsle,
  sablonRolleri,
  tablolariAyikla,
  yanitiDogrula,
  yeniSablonlar,
} from '../functions/_shared/ekstre_esleme.ts';

const iskelet = [
  ILK_SATIR,
  'biçim: pdf',
  'anlam 1: başlık satırı 1 · güven 0.00 · adla hayır · veri 2 · atlanan 0 · roller []',
  '',
  '## tablo 1 (PDF) · 4 satır × 3 sütun',
  '0\tAaaaaa\tAaaaa Aaaaa',
  '1\tYatırım Fonu İsmi\tPay Adedi\tBakiye',
  '2\tAAA PORTFÖY FONU\t9.999,99\t99.999,99',
  '3\tAAA PORTFÖY ALTIN FONU\t999,99\t9.999,99',
  '',
  '## tablo 2 (PDF) · 2 satır × 2 sütun',
  '0\tAaaaa\tAaaa',
  '1\tAaaa\t99/99/9999',
].join('\n');

Deno.test('iskelet: geçerli olan tablo boyutlarını verir', () => {
  assertEquals(iskeletiDogrula(iskelet), {
    gecti: true,
    tablolar: [{ satir: 4, sutun: 3 }, { satir: 2, sutun: 2 }],
    surum: 'iskelet',
  });
});

Deno.test('iskelet: maskesiz rakam reddedilir (ham ekstre modele gitmez)', () => {
  const sizinti = iskelet.replace('9.999,99', '1.647,00');
  assertEquals(iskeletiDogrula(sizinti), { gecti: false, neden: 'maskesiz' });
  const tc = iskelet.replace('Aaaaa Aaaaa', '12345678901');
  assertEquals(iskeletiDogrula(tc), { gecti: false, neden: 'maskesiz' });
});

Deno.test('iskelet: sürüm, boş, uzun ve tablosuz reddedilir', () => {
  assertEquals(iskeletiDogrula(''), { gecti: false, neden: 'bos' });
  assertEquals(iskeletiDogrula(42), { gecti: false, neden: 'bos' });
  assertEquals(iskeletiDogrula('x\n' + iskelet), { gecti: false, neden: 'surum' });
  assertEquals(iskeletiDogrula(ILK_SATIR + '\n' + 'a'.repeat(40_001)), { gecti: false, neden: 'uzun' });
  assertEquals(iskeletiDogrula(ILK_SATIR + '\nbiçim: pdf'), { gecti: false, neden: 'tablo_yok' });
});

Deno.test('yanıt: geçerli eşleme kalır, uydurma düşer', () => {
  const boyut = [{ satir: 4, sutun: 3 }, { satir: 2, sutun: 2 }];
  assertEquals(
    yanitiDogrula({
      tablolar: [
        { tablo: 1, baslik_satiri: 1, roller: { sembol: 0, adet: 1, tutar: 2 } },
        // Olmayan tablo.
        { tablo: 7, baslik_satiri: 0, roller: { sembol: 0, adet: 1 } },
        // Adet yok.
        { tablo: 2, baslik_satiri: 0, roller: { sembol: 0, tarih: 1 } },
      ],
    }, boyut),
    [{ tablo: 1, baslik_satiri: 1, roller: { sembol: 0, adet: 1, tutar: 2 } }],
  );
  // Sütun aralık dışı, aynı sütuna iki rol, bozuk başlık satırı.
  assertEquals(
    yanitiDogrula({
      tablolar: [{ tablo: 1, baslik_satiri: 99, roller: { sembol: 0, isim: 0, adet: 1, fiyat: 5 } }],
    }, boyut),
    [{ tablo: 1, baslik_satiri: -1, roller: { sembol: 0, adet: 1 } }],
  );
  assertEquals(yanitiDogrula(null, boyut), []);
  assertEquals(yanitiDogrula({ tablolar: 'x' }, boyut), []);
});

Deno.test('istek: zorunlu araç seçimi yok (Sonnet 5.5 400), iskelet kullanıcı mesajı', () => {
  const g = istekGovdesi(iskelet, 'claude-sonnet-5-5') as {
    tool_choice: { type: string };
    tools: { name: string }[];
    messages: { content: string }[];
  };
  assertEquals(g.tool_choice.type, 'auto');
  assertEquals(g.tools[0].name, 'sutun_eslemesi');
  assertEquals(g.messages[0].content, iskelet);
});

Deno.test('hata özeti: API durumu ve türü, db kodu; mesaj yok', () => {
  // Anthropic SDK APIError biçimi: status + error.error.type, name "Error".
  const api = Object.assign(new Error('credit balance is too low'), {
    status: 400,
    error: { type: 'error', error: { type: 'invalid_request_error', message: 'gizli' } },
  });
  assertEquals(hataOzeti(api), 'api 400 invalid_request_error');
  assertEquals(hataOzeti({ status: 401 }), 'api 401');
  assertEquals(hataOzeti({ code: '42P01', message: 'x' }), 'db 42P01');
  assertEquals(hataOzeti(new TypeError('x')), 'TypeError');
  assertEquals(hataOzeti('x'), 'hata');
});

// ── Metin yolu ve şablon hafızası (2026-10-13, 0147) ──────────────────────

const metin = [
  METIN_ILK_SATIR,
  'biçim: pdf',
  '',
  '## tablo 1 (PDF) · 4 satır × 3 sütun',
  '0\tSayın\tAaaaa Aaaaa',
  '1\tYatırım Fonu İsmi\tNominal Miktar\tBakiye',
  '2\tİŞ PORTFÖY ALTIN FONU\t9.999,99\t99.999,99',
  '3\tYAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ\t999,99\t9.999,99',
].join('\n');

Deno.test('metin: v2 kabul edilir, rakam yine maskeli olmalı', () => {
  assertEquals(iskeletiDogrula(metin), {
    gecti: true,
    tablolar: [{ satir: 4, sutun: 3 }],
    surum: 'metin',
  });
  assertEquals(
    iskeletiDogrula(metin.replace('9.999,99', '1.647,00')),
    { gecti: false, neden: 'maskesiz' },
  );
});

Deno.test('iz: Türkçe katlanır, rakam #, başlığa benzemeyen satır yok', () => {
  assertEquals(baslikIzi(['Yatırım Fonu İsmi', 'Nominal Miktar', 'Bakiye']),
    'yatirim fonu ismi|nominal miktar|bakiye');
  assertEquals(baslikIzi(['YATIRIM FONU İSMİ', 'NOMİNAL MİKTAR', 'BAKİYE']),
    'yatirim fonu ismi|nominal miktar|bakiye');
  assertEquals(baslikIzi(['Tutar (9)', 'Adet']), 'tutar #|adet');
  assertEquals(baslikIzi(['9.999,99', '99/99/9999', 'X']), null);
});

Deno.test('şablon: model eşlemesi saklanır, aynı başlık modelsiz eşlenir', async () => {
  const t = tablolariAyikla(metin);
  assertEquals(t.length, 1);
  assertEquals(t[0][1], ['Yatırım Fonu İsmi', 'Nominal Miktar', 'Bakiye']);
  const yeni = yeniSablonlar(t, [{ tablo: 1, baslik_satiri: 1, roller: { sembol: 0, adet: 1, tutar: 2 } }]);
  assertEquals(yeni.length, 1);
  const depo = new Map<string, Sablon>([[await izOzeti(yeni[0].iz), yeni[0].sablon]]);

  // Aynı banka, başka kullanıcı, başka satırlar: künye bir satır uzun.
  const baska = tablolariAyikla(metin.replace('0\tSayın\tAaaaa Aaaaa', '0\tSayın\tAaaaa\n9\tAaaaa Aaaaa'));
  const adaylar = await Promise.all(adayIzler(baska).map(async (a) => ({ ...a, iz: await izOzeti(a.iz) })));
  const e = sablonlaEsle(baska, adaylar, depo);
  assertEquals(e.eslemeler, [{ tablo: 1, baslik_satiri: 2, roller: { sembol: 0, adet: 1, tutar: 2 } }]);
  assertEquals(e.kullanilan.length, 1);
});

Deno.test('şablon: banka sütun eklerse iz tutmaz (model yeniden sorulur)', async () => {
  const t = tablolariAyikla(metin);
  const y = yeniSablonlar(t, [{ tablo: 1, baslik_satiri: 1, roller: { sembol: 0, adet: 1 } }]);
  const depo = new Map<string, Sablon>([[await izOzeti(y[0].iz), y[0].sablon]]);
  const yeniDuzen = tablolariAyikla(metin.replace('Nominal Miktar\tBakiye', 'Nominal Miktar\tFiyat\tBakiye'));
  const adaylar = await Promise.all(adayIzler(yeniDuzen).map(async (a) => ({ ...a, iz: await izOzeti(a.iz) })));
  assertEquals(sablonlaEsle(yeniDuzen, adaylar, depo).eslemeler, []);
});

Deno.test('şablon: başlıksız eşleme saklanmaz; bozuk DB rolleri düşer', () => {
  const t = tablolariAyikla(metin);
  assertEquals(yeniSablonlar(t, [{ tablo: 1, baslik_satiri: -1, roller: { sembol: 0, adet: 1 } }]), []);
  assertEquals(sablonRolleri({ sembol: 0, adet: 7 }, 3), null);
  assertEquals(sablonRolleri({ sembol: 0, adet: 1, uydurma: 2 }, 3), { sembol: 0, adet: 1 });
});

Deno.test('iz özeti: 64 hane hex (0147 check kısıtı)', async () => {
  const o = await izOzeti('adet|fiyat');
  assertEquals(/^[0-9a-f]{64}$/.test(o), true);
});

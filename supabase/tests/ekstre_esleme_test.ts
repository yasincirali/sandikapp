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
import { hataOzeti, ILK_SATIR, istekGovdesi, iskeletiDogrula, yanitiDogrula } from '../functions/_shared/ekstre_esleme.ts';

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

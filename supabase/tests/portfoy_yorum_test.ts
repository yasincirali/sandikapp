// Kişiye özel AI portföy yorumu — saf kapılar (0145).
//
// Kilitlenen değişmezler:
//   · Pakette tutar YOK (veri minimizasyonu istemciye bırakılmaz).
//   · Yalnız kapanmış takvim dönemi (kaydet-yeniden yazma kuralı).
//   · Kişiye özel dil kapısı: yönlendirme / öneri kipi / değer yargısı / gelecek.

import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  beklenenDonem,
  kapidanGecir,
  paketiDogrula,
  saklamaSiniri,
  sonKapaliAy,
  sonKapaliHafta,
  YorumPaketi,
} from '../functions/_shared/portfoy_yorum.ts';

const BUGUN = '2026-10-13'; // Salı

function paket(ek: Partial<YorumPaketi> = {}): Record<string, unknown> {
  return {
    tur: 'haftalik',
    ...beklenenDonem('haftalik', BUGUN),
    parmak_izi: 'v1|hisse:THYAO=45|fon:TTE=30',
    olcumler: [
      { anahtar: 'getiri', ad: 'Dönem getirisi', gosterim: '+%4,2' },
      { anahtar: 'en_iyi', ad: 'En çok kazandıran: THYAO', gosterim: '+%9,1' },
      { anahtar: 'en_buyuk_pay', ad: 'En büyük pay: THYAO', gosterim: '%46,0' },
      { anahtar: 'dusus', ad: 'Dönemdeki en derin düşüş', gosterim: '−%6,8' },
      { anahtar: 'pozisyon', ad: 'Açık pozisyon sayısı', gosterim: '7' },
    ],
    ...ek,
  };
}

Deno.test('dönem: son kapalı hafta ve ay', () => {
  assertEquals(sonKapaliHafta('2026-10-13'), { baslangic: '2026-10-05', bitis: '2026-10-11' });
  // Pazar: içinde bulunulan hafta henüz kapanmadı.
  assertEquals(sonKapaliHafta('2026-10-11'), { baslangic: '2026-09-28', bitis: '2026-10-04' });
  // Pazartesi: dün biten hafta.
  assertEquals(sonKapaliHafta('2026-10-12'), { baslangic: '2026-10-05', bitis: '2026-10-11' });
  assertEquals(sonKapaliAy('2026-10-13'), { baslangic: '2026-09-01', bitis: '2026-09-30' });
  assertEquals(sonKapaliAy('2026-01-05'), { baslangic: '2025-12-01', bitis: '2025-12-31' });
  assertEquals(sonKapaliAy('2026-03-01'), { baslangic: '2026-02-01', bitis: '2026-02-28' });
});

Deno.test('paket: geçerli paket geçer', () => {
  const d = paketiDogrula(paket(), BUGUN);
  assert(d.gecti);
});

Deno.test('paket: kayan ya da açık dönem reddedilir', () => {
  const d = paketiDogrula(paket({ baslangic: '2026-10-06', bitis: '2026-10-12' }), BUGUN);
  assertEquals(d.gecti ? '' : d.neden, 'donem');
  const ay = paketiDogrula(paket({ tur: 'aylik' }), BUGUN); // haftalık tarihleriyle
  assertEquals(ay.gecti ? '' : ay.neden, 'donem');
});

Deno.test('paket: tutar biçimi hiçbir alanda geçemez', () => {
  const tutarlar = [
    { anahtar: 'deger', ad: 'Portföy değeri', gosterim: '₺412.000' },
    { anahtar: 'deger', ad: 'Portföy değeri', gosterim: '412.000' },
    { anahtar: 'deger', ad: 'Değer ₺412 bin', gosterim: '%4,2' },
    { anahtar: 'deger', ad: 'Değer 412000', gosterim: '%4,2' },
    { anahtar: 'deger', ad: 'Değer 1.250 TL', gosterim: '%4,2' },
    { anahtar: 'adet', ad: 'THYAO adedi', gosterim: '1500' },
  ];
  for (const o of tutarlar) {
    const p = paket();
    (p.olcumler as unknown[]).push(o);
    const d = paketiDogrula(p, BUGUN);
    assert(!d.gecti, `geçmemeliydi: ${JSON.stringify(o)}`);
  }
});

Deno.test('paket: yinelenen anahtar ve ölçüm sınırı', () => {
  const p = paket();
  (p.olcumler as unknown[]).push({ anahtar: 'getiri', ad: 'Tekrar', gosterim: '%1,0' });
  assert(!paketiDogrula(p, BUGUN).gecti);
  const az = paket({ olcumler: [{ anahtar: 'getiri', ad: 'Dönem getirisi', gosterim: '+%4,2' }] });
  assert(!paketiDogrula(az, BUGUN).gecti);
});

function gecerliPaket(): YorumPaketi {
  const d = paketiDogrula(paket(), BUGUN);
  if (!d.gecti) throw new Error(d.neden);
  return d.paket;
}

function yorum(...maddeler: string[]) {
  return {
    baslik: 'Portföyün bu hafta +%4,2 değer kazandı.',
    maddeler: maddeler.map((metin) => ({ metin, kanit: ['getiri'] })),
  };
}

Deno.test('kapı: betimleyici yorum geçer', () => {
  const s = kapidanGecir(yorum(
    'Artışın büyük kısmı THYAO\'dan geldi; THYAO dönemde +%9,1 değişti.',
    'Portföyünün %46,0\'sı tek varlıkta, THYAO\'da duruyor.',
    'Dönemdeki en derin düşüş −%6,8 oldu.',
    'Portföyünde 7 açık pozisyon var.',
  ), gecerliPaket());
  assert(s.gecti, s.gecti ? '' : s.neden);
});

Deno.test('kapı: pakette olmayan sayı reddedilir', () => {
  const s = kapidanGecir(yorum('THYAO payı %50 civarında.'), gecerliPaket());
  assert(!s.gecti && s.neden.startsWith('sayi'));
});

Deno.test('kapı: yönlendirme, öneri kipi, değer yargısı, gelecek reddedilir', () => {
  const yasaklar = [
    'THYAO payını azaltmak düşünülebilir.',
    'Portföyünü çeşitlendirmen faydalı olur.',
    'Tek varlığa bu kadar ağırlık riskli.',
    'Bu dağılımla portföy dengelenmeli.',
    'Yükseliş önümüzdeki hafta da sürebilir.',
    'THYAO\'yu tutmalısın.',
    'Bu yatırım tavsiyesi değildir.',
    'Portföyüne ekle.',
  ];
  for (const m of yasaklar) {
    const s = kapidanGecir(yorum(m), gecerliPaket());
    assert(!s.gecti, `geçmemeliydi: ${m}`);
  }
});

Deno.test('kapı: betimleyici fiiller yanlış alarm vermez', () => {
  const s = kapidanGecir(yorum(
    'Fon payı azaldı, hisse payı arttı.',
    'Dönem boyunca artış THYAO kaynaklı.',
  ), gecerliPaket());
  assert(s.gecti, s.gecti ? '' : s.neden);
});

Deno.test('kapı: bilinmeyen kanıt anahtarı reddedilir', () => {
  const y = yorum('Portföyün +%4,2 kazandı.');
  y.maddeler[0].kanit = ['yok_boyle'];
  assert(!kapidanGecir(y, gecerliPaket()).gecti);
});

Deno.test('saklama: 4 hafta, 12 ay', () => {
  assertEquals(saklamaSiniri('haftalik', '2026-10-05'), '2026-09-14');
  assertEquals(saklamaSiniri('aylik', '2026-09-01'), '2025-10-01');
  assertEquals(saklamaSiniri('aylik', '2026-01-01'), '2025-02-01');
});

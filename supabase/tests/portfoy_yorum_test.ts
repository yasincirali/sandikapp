// Kişiye özel AI portföy yorumu — saf kapılar (0145).
//
// Kilitlenen değişmezler:
//   · Pakette tutar YOK (veri minimizasyonu istemciye bırakılmaz).
//   · Yalnız kapanmış takvim dönemi (kaydet-yeniden yazma kuralı).
//   · Kişiye özel dil kapısı: yönlendirme / öneri kipi / değer yargısı / gelecek.
//   · Seçili dönem / varlık (0151): pencere başı takvimden (istemcinin
//     `PeriodSummaryService.pencere` örnekleriyle aynı), bitiş bugün ±1,
//     varlık izi özet biçiminde, eski (0145) istek aynen geçer.

import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  beklenenDonem,
  kapidanGecir,
  konuGecerli,
  paketiDogrula,
  kullaniciMesaji,
  saklamaSiniri,
  seciliBaslangic,
  seciliSaklamaSiniri,
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

// ── Seçili dönem ve varlık kapsamı (0151) ───────────────────────────────────

const BUGUN2 = '2026-10-14';

function secili(ek: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    ...paket(),
    tur: 'secili',
    donem_kodu: '3A',
    baslangic: '2026-07-14',
    bitis: BUGUN2,
    ...ek,
  };
}

Deno.test('seçili dönem başlangıcı: istemciyle aynı örnekler', () => {
  // `test/portfoy_yorumu_test.dart` "pencere başı sunucuyla aynı örnekler".
  assertEquals(seciliBaslangic('1H', '2026-10-14'), '2026-10-07');
  assertEquals(seciliBaslangic('1A', '2026-10-14'), '2026-09-14');
  assertEquals(seciliBaslangic('3A', '2026-05-31'), '2026-02-28');
  assertEquals(seciliBaslangic('5Y', '2026-10-14'), '2021-10-14');
  assertEquals(seciliBaslangic('1Y', '2028-02-29'), '2027-02-28');
  assertEquals(seciliBaslangic('GÜNLÜK', '2026-10-14'), null);
});

Deno.test('seçili: geçerli portföy paketi geçer, bitiş ±1 gün', () => {
  const d = paketiDogrula(secili(), BUGUN2);
  assert(d.gecti);
  assertEquals(d.gecti && d.paket.kapsam, 'portfoy');
  assertEquals(d.gecti && d.paket.donem_kodu, '3A');
  // Telefon bir gün ileride / geride.
  assert(paketiDogrula(secili(), '2026-10-13').gecti);
  assert(paketiDogrula(secili(), '2026-10-15').gecti);
  const eski = paketiDogrula(secili(), '2026-10-17');
  assertEquals(eski.gecti ? '' : eski.neden, 'donem');
});

Deno.test('seçili: uydurma pencere ve bilinmeyen kod reddedilir', () => {
  const kayik = paketiDogrula(secili({ baslangic: '2026-07-01' }), BUGUN2);
  assertEquals(kayik.gecti ? '' : kayik.neden, 'donem');
  const kod = paketiDogrula(secili({ donem_kodu: 'GÜNLÜK', baslangic: BUGUN2 }), BUGUN2);
  assertEquals(kod.gecti ? '' : kod.neden, 'donem');
  const kodsuz = paketiDogrula(secili({ donem_kodu: undefined }), BUGUN2);
  assertEquals(kodsuz.gecti ? '' : kodsuz.neden, 'donem');
});

Deno.test('kapsam: kapanmış dönem yalnız portföy, eski istek aynen geçer', () => {
  assert(paketiDogrula(paket(), BUGUN).gecti);
  const d = paketiDogrula(paket({ kapsam: 'varlik', varlik_izi: 'v1:' + 'a'.repeat(24) }), BUGUN);
  assertEquals(d.gecti ? '' : d.neden, 'kapsam');
  const k = paketiDogrula(paket({ donem_kodu: '1H' }), BUGUN);
  assertEquals(k.gecti ? '' : k.neden, 'kapsam');
});

Deno.test('varlık: iz biçimi zorunlu, tutar izli ad düşer', () => {
  const iz = 'v1:' + '0123456789abcdef01234567';
  const d = paketiDogrula(secili({ kapsam: 'varlik', varlik_izi: iz, varlik_adi: 'Türk Hava Yolları' }), BUGUN2);
  assert(d.gecti);
  assertEquals(d.gecti && d.paket.varlik_adi, 'Türk Hava Yolları');
  const ham = paketiDogrula(secili({ kapsam: 'varlik', varlik_izi: 'hisse|THYAO|TRY' }), BUGUN2);
  assertEquals(ham.gecti ? '' : ham.neden, 'varlik_izi');
  const tutarli = paketiDogrula(secili({ kapsam: 'varlik', varlik_izi: iz, varlik_adi: 'TR 2030 Eurobond' }), BUGUN2);
  assert(tutarli.gecti);
  assertEquals(tutarli.gecti && tutarli.paket.varlik_adi, undefined);
  const portfoyIzli = paketiDogrula(secili({ varlik_izi: iz }), BUGUN2);
  assertEquals(portfoyIzli.gecti ? '' : portfoyIzli.neden, 'kapsam');
});

Deno.test('mesaj: kapsam ve dönem adı modele gider', () => {
  const d = paketiDogrula(secili({ kapsam: 'varlik', varlik_izi: 'v1:' + 'b'.repeat(24), varlik_adi: 'ALTIN 22 AYAR' }), BUGUN2);
  assert(d.gecti);
  const m = d.gecti ? kullaniciMesaji(d.paket) : '';
  assert(m.includes('Kapsam: varlık (ALTIN 22 AYAR)'), m);
  assert(m.includes('son 3 ay'), m);
  // Varlık adındaki sayı yorumda serbest (kapı izinli sayılara ekler).
  const k = kapidanGecir({
    baslik: 'ALTIN 22 AYAR son üç ayda +%4,2 değer kazandı.',
    maddeler: [{ metin: 'Getiri +%4,2 oldu.', kanit: ['getiri'] }],
  }, d.gecti ? d.paket : (null as never));
  assert(k.gecti, k.gecti ? '' : k.neden);
});

Deno.test('saklama: seçili dönem 7 gün', () => {
  assertEquals(seciliSaklamaSiniri('2026-10-14'), '2026-10-08');
});

Deno.test('konu: geçerli konu saklanır, kötüsü yalnız atılır', () => {
  const p = paketiDogrula(paket(), BUGUN);
  assert(p.gecti);
  const k = kapidanGecir({
    baslik: 'Portföyün geçen hafta +%4,2 kazandı.',
    maddeler: [
      { metin: 'Getiri +%4,2 oldu.', kanit: ['getiri'], konu: 'Alım gücü' },
      { metin: 'En büyük pay %46,0 ile THYAO.', kanit: ['en_buyuk_pay'], konu: 'Pay 46' },
      { metin: 'En derin düşüş −%6,8 oldu.', kanit: ['dusus'], konu: 'Riskli dönem' },
    ],
  }, p.gecti ? p.paket : (null as never));
  assert(k.gecti, k.gecti ? '' : k.neden);
  const m = k.gecti ? k.yorum.maddeler : [];
  assertEquals(m[0].konu, 'Alım gücü');
  assertEquals(m[1].konu, undefined); // rakam
  assertEquals(m[2].konu, undefined); // değer yargısı
  assertEquals(konuGecerli('  Kıyas '), 'Kıyas');
  assertEquals(konuGecerli('x'.repeat(33)), undefined);
  assertEquals(konuGecerli(7), undefined);
});

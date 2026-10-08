// bes-parametre — EGM sayfası ayrıştırma ve doğrulama kapıları.
//
// Bu fonksiyonun yazdığı sayı, kullanıcının BES katkısına eklenen "devlet
// katkısı"nı kırpar. Yanlış sınır = yanlış para. Bu yüzden kilitlenenler:
//   1) Gerçek sayfa cümlesi (2026-10-01'de okundu) doğru ayrışır,
//   2) iç tutarsız, uzak yıllı ya da sıçramalı değer YAZILMAZ,
//   3) Türkçe kod sayfası (windows-1254) ve HTML varlıkları doğru çözülür.
//
// Çalıştır:
//   deno test --allow-all supabase/tests/bes_parametre_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  ayristir,
  dogrula,
  duzMetin,
  hamYanitiCoz,
  metneCevir,
  trSayi,
} from '../functions/bes-parametre/index.ts';

// EGM "Devlet Katkısı" sayfasının ilgili bölümü, 2026-10-01 (HTML hâliyle,
// `üstlimitinden` bitişik yazımı ve `&#39;` dahil).
const EGM_2026 = `
<div class="content"><h1>Devlet Katk&#305;s&#305;</h1>
<p>Devlet katk&#305;s&#305;, bireysel ya da gruba ba&#287;l&#305; bireysel s&#246;zle&#351;menize
&#246;dedi&#287;iniz katk&#305; paylar&#305;n&#305;n %20&#39;si oran&#305;nda Devlet taraf&#305;ndan &#246;denen tutard&#305;r.</p>
<p>2026 y&#305;l&#305; Devlet katk&#305;s&#305; &#252;stlimitinden yararlanabilmek i&#231;in &#246;denmesi gereken
katk&#305; pay&#305; tutar&#305; 396.360 TL&#39;dir. Bu tutara kar&#351;&#305;l&#305;k ilgili y&#305;lda al&#305;nabilecek
maksimum Devlet katk&#305;s&#305; tutar&#305; 79.272 TL&#39;dir.</p></div>
<script>var x = "2020 yılı Devlet katkısı üst limit 1 TL";</script>`;

Deno.test('gerçek EGM cümlesi ayrışır', () => {
  const p = ayristir(duzMetin(EGM_2026));
  assertEquals(p, {
    yil: 2026,
    katki_ust_siniri: 396360,
    azami_devlet_katkisi: 79272,
    oran_yuzde: 20,
  });
  assertEquals(dogrula(p!, 2026, null), null);
});

Deno.test('cümle yoksa null — uydurma yok', () => {
  assertEquals(ayristir(duzMetin('<p>Bakım çalışması</p>')), null);
});

Deno.test('iç tutarsız değer reddedilir', () => {
  // 79.272 yerine 97.272 okunmuş gibi.
  assertEquals(
    dogrula({ yil: 2026, katki_ust_siniri: 396360, azami_devlet_katkisi: 97272, oran_yuzde: 20 }, 2026, null),
    'ic_tutarsiz',
  );
});

Deno.test('uzak yıl reddedilir (eski haber kutusu)', () => {
  assertEquals(
    dogrula({ yil: 2019, katki_ust_siniri: 30700, azami_devlet_katkisi: 7675, oran_yuzde: 25 }, 2026, null),
    'yil_uzak',
  );
});

Deno.test('önceki yıla göre akıl dışı sıçrama reddedilir', () => {
  assertEquals(
    dogrula({ yil: 2027, katki_ust_siniri: 5_000_000, azami_devlet_katkisi: 1_000_000, oran_yuzde: 20 }, 2027, 79272),
    'sicrama',
  );
  // Olağan artış geçer.
  assertEquals(
    dogrula({ yil: 2027, katki_ust_siniri: 480000, azami_devlet_katkisi: 96000, oran_yuzde: 20 }, 2027, 79272),
    null,
  );
});

Deno.test('Türkçe sayı ve kod sayfası', () => {
  assertEquals(trSayi('396.360'), 396360);
  assertEquals(trSayi('79.272,50'), 79272.5);
  // "katkı" windows-1254: k a t k 0xFD
  const bytes = new Uint8Array([0x6b, 0x61, 0x74, 0x6b, 0xfd]);
  assertEquals(metneCevir(bytes), 'katkı');
});

// Canlıda bulundu (2026-10-01): Deno fetch EGM yanıtını "invalid HTTP header"
// diye reddediyor; ham yol yanıtı kendisi ayrıştırır.
Deno.test('ham yanıt: content-length, chunked ve çerez', () => {
  const enc = new TextEncoder();
  const a = hamYanitiCoz(enc.encode(
    'HTTP/1.1 200 OK\r\nContent-Length: 5\r\nSet-Cookie: x=1; HttpOnly\r\nBozuk Baslik\r\n\r\nmerhabaFAZLA',
  ));
  assertEquals(a.status, 200);
  assertEquals(new TextDecoder().decode(a.govde), 'merha');
  assertEquals(a.cerezler, ['x=1']);
  // "katkı": 'ı' UTF-8'de 2 bayt.
  const b = hamYanitiCoz(enc.encode(
    'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nkatk\r\n2\r\nı\r\n0\r\n\r\n',
  ));
  assertEquals(new TextDecoder().decode(b.govde), 'katkı');
});

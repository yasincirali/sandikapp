# Anlatım yazım kuralları — mağaza ve tanıtım videoları

Kullanıcı kuralı (2026-10-10): *"Cümlelerimizi ve vurgularımızı seslendirmede daha
dikkatli, doğal, basit ve açıklayıcı şekilde yapmalıyız."* 2026-09-18 tercihiyle
birlikte: ekran metni = özellik başlığı + tek düz cümle, jargon yok.

Ses EMA Lightning (`scripts/seslendir_ema.py`): **tek ses, vurgu/duygu ayarı yok.**
Vurgu yalnız **cümlenin kuruluşuyla** verilir; aşağıdaki kurallar bu yüzden var.
Betik her satırı bu kurallara göre denetler (`--denetle` yalnız denetler, ses üretmez).

## 1. Bir cümle, bir fikir
- En çok **10–12 kelime**. Uzunsa ikiye böl.
- Düz cümle: özne → nesne → yüklem. Devrik cümle yok ("Takip et portföyünü" değil).
- Hitap **sen**, günlük dil: "paran", "ekle", "gör". Broşür dili yok
  ("kapsamlı çözüm", "deneyimleyin", "sizlere sunuyoruz").
- Anlatım ekranı **okumaz**, ne işe yaradığını söyler. Ekranda "Ekle" düğmesi
  görünüyorsa ses "Ekle'ye bas" demez; "Eklediğin an fiyatı gelir" der.

## 2. Jargon yok — günlük karşılığı
| Yazma | Yaz |
|---|---|
| reel getiri | enflasyondan sonra kalan kazanç |
| nominal kâr | (söyleme; gerekirse "görünen kâr") |
| TÜFE | enflasyon |
| XU100, BIST 100, endeks | borsa |
| BIST | Borsa İstanbul |
| TEFAS fonu | fon |
| XIRR, TWR, getiri oranı | kazancın, yüzde kaç kazandığın |
| volatilite | ne kadar oynadığı |
| portföy dağılımı | paranın nerede durduğu |

## 3. Vurgu: cümlenin kuruluşuyla
Türkçede vurgu **yüklemin hemen önündeki** sözcüğe düşer. Öne çıkmasını
istediğin sözcüğü oraya koy:
- "Sandık paranın **enflasyonu** geçip geçmediğini söyler." → vurgu enflasyonda.
- "Altını, fonu, hisseyi **tek yerde** gör." → vurgu "tek yerde".

Ölçülen davranış (EMA 1.0.4, 2026-10-10):
- **Nokta** cümle arasında ~180 ms durur. **Virgül hiç durmaz.** Duraklama
  istiyorsan virgül değil nokta koy.
- **Üç nokta** ~220 ms durur; nadiren, gerilim için.
- **Soru işareti** uzun soruda tonu biraz yükseltir, kısa soruda fark küçük.
  Soruyu **"mi" ekiyle** kur; soru işaretine güvenme.
- Ünlem, BÜYÜK HARF, tırnak, kalın yazı sese **hiçbir şey katmaz**. Ünlem
  reklam tonu verir, kullanma.
- Daha uzun ve kesin bir es gerekiyorsa cümleleri **ayrı satır** üret, aradaki
  boşluğu kompozisyonda ver (300–600 ms). Bu, noktadan daha güvenilir.

## 4. Sayılar: sesin söyleyeceği gibi yaz, yuvarla
- Ekranda kesin sayı durur, ses yuvarlar: ekranda "31,49 puan" →
  sesle "otuz puandan fazla". Ölçüm: "Yüzde 31,49 puan önündesin" 2,7 sn,
  "Enflasyonun otuz puan önündesin" 1,9 sn — daha kısa ve anlaşılır.
- Rakam yerine sözcük yaz ("otuz", "bin"); normalizer genelde doğru okur ama
  "31,49" gibi ondalıkları dinleyici tutamaz.
- `%` yazma, "yüzde" yaz. Para: "bin lira", "₺" değil.

## 5. Adlar ve kısaltmalar
- Marka küçük harfle: **sandık** (ses fark etmez, metin tutarlılığı için).
- Kısaltmalar harf harf ya da yanlış okunur: "BIST", "ABD", "TL" → "Borsa İstanbul",
  "Amerikan", "lira".
- Yabancı sözcükler Türkçe imla kuralıyla okunur ("App Store" bozuk çıkar). Yazma.

## 6. Hız
- Ölçülen EMA hızı ~**2,3 kelime/sn**. Planlarken **2 kelime/sn** say: 30 sn
  video ≈ en çok **55–60 kelime**, sahne başına tek cümle.
- Metin videodan **kısa** hissettirmeli; cümle aralarındaki sessizlik iştir.
- Hız ayarı (`"hiz": 0.95`) son çare; önce cümleyi kısalt.

## 7. Yapı (30 sn mağaza videosu)
1. **Kanca** (ilk 3 sn): soru ya da karşıtlık. "Paran arttı. Peki enflasyonu geçti mi?"
2. **Ne yapar**: 3–4 sahne, her biri tek cümle, tek işlev.
3. **Kapanış**: ad + tek satır. Mağaza CTA'sı ve fiyat yok (Apple 2.3.4 / 2.3.7).

## 8. Kontrol listesi (yayından önce)
- [ ] Sesli oku: nefes almadan söyleyemediğin cümle uzundur.
- [ ] Her cümlede jargon yok; sayılar yuvarlak ve sözcükle.
- [ ] Vurgulanacak sözcük yüklemin hemen önünde.
- [ ] `--denetle` uyarısız (ya da her uyarının gerekçesi var).
- [ ] Dinle: yanlış okunan sözcük varsa yazımını değiştir ya da tohumu değiştir.
- [ ] Yapay zekâ sesi beyanı satırı (`SES_LISANS.md`).

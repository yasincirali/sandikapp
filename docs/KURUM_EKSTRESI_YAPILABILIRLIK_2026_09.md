# Aracı kurum ve banka ekstresi — yapılabilirlik (karar 5.3 / 5.4 / 5.5)

**Tarih:** 2026-09-30 · **Karar sahibi:** kullanıcı ("tüm aracı kurum ve
bankaların yatırım ekstrelerini karşılamamız lazım, asıl öncelik o").

## Bugün ne çalışıyor (yapıldı, `024f6f4`)

Toplu ekle › "Ekstreden / CSV'den yapıştır":

| Yetenek | Durum |
|---|---|
| Kurum sütun adları: Menkul Kıymet, Kıymet, Nominal, Ortalama Maliyet, Ort. Mlyt, Maliyet Fiyatı, İşlem Fiyatı, İşlem Tarihi, Valör… | ✅ |
| Alış/satış yönü: "İşlem Türü", "Al/Sat", "Yön", "A/S", "Buy/Sell" sütunu ya da eksi adet | ✅ |
| Birim fiyat yoksa "Tutar" / "İşlem Tutarı" / "Maliyet Tutarı" ÷ adet | ✅ |
| Sembol hücresi "THYAO - Türk Hava Yolları" / "THYAO.E" | ✅ |
| Satışlar tarih sırasıyla, o gün elde olandan fazlası reddedilir, maliyet o güne kadarki ağırlıklı ortalama | ✅ |
| Dosya seçip okuma (Excel / PDF) | ❌ — aşağıda |

Kopyala-yapıştır masaüstünde her kurumda çalışır. **Telefonda zayıf:**
Excel mobil uygulamasından tablo kopyalamak zahmetli, PDF'ten kopyalanan
tablo satır yapısını kaybeder. Bu yüzden asıl açık **dosyadan okuma**.

## Kurumların verdiği biçimler (araştırma 2026-09-30)

| Kaynak | Biçim | Not |
|---|---|---|
| **MKK e-Yatırımcı** | PDF + Excel ([kılavuz](https://www.mkk.com.tr/sites/default/files/2026-09/e-YATIRIMCI_KILAVUZ_16.09.2026.pdf)) | TÜM kurumlardaki hesapları tek yerde gösterir. Portföy dökümü + aylık hesap ekstresi; ekstre "tarih, saat, işlem türü" sütunlu. **Tek adaptörle herkesi kapsayan en değerli kaynak.** Açık soru: hareket satırlarında fiyat var mı (takas/virman hareketi olabilir). |
| **Midas** | Yalnız PDF ([destek](https://www.getmidas.com/destek/profil-ve-hesap-bilgileri/genel-bilgiler/ekstrelerimi-nereden-ve-nasil-gorebilirim)) | Excel talebine destek "yapamıyoruz" diyor. PDF okumadan Midas kullanıcısı dosyayla aktaramaz. |
| **İş Yatırım (TradeMaster)** | "Excel'e Aktar" ([kılavuz](https://tmweb.isyatirim.com.tr/Kullanim-Kilavuzu.pdf)) | Web arayüzünden. |
| Diğer kurum/bankalar (Garanti BBVA Yatırım, Yapı Kredi Yatırım, Ak Yatırım, QNB, Gedik, Info, Deniz, Ziraat, Halk, Vakıf…) | Bilinmiyor | Türk kurumlarının "Excel" indirmelerinin önemli kısmı gerçek `.xlsx` değil: uzantısı `.xls` olan **HTML tablo** ya da eski ikili `.xls`. Örnek görmeden yazılan okuyucu gerçek dosyada çalışmayabilir. |

## Yol haritası (öneri)

| Adım | Ne | Efor | Engelleyici |
|---|---|---|---|
| **A** | Dosya seçici + okuyucu: `.csv`, `.txt`, `.xlsx`, HTML-`.xls` → metin → bugünkü ayrıştırıcı. Paket: `file_selector` (flutter.dev; iOS'ta yalnız belge seçici, fotoğraf izni gerektirmez). `file_picker` **bilerek değil**: iOS'ta fotoğraf kitaplığı kodunu da getiriyor, App Store "izin açıklaması eksik" uyarısı riski. | 1,5–2 gün | Her biçimden **bir gerçek örnek** |
| **B** | MKK e-Yatırımcı adaptörü (portföy dökümü + ekstre). Tüm kurumları tek seferde kapsar. | 1–2 gün | e-Yatırımcı Excel + PDF örneği |
| **C** | PDF metin çıkarma: iOS PDFKit / Android PdfBox (Apache-2.0) üzerinden, kurum başına satır ayrıştırıcı. Önce Midas. | 3–4 gün + kurum başına 1 gün | Midas PDF ekstresi örneği; paket/lisans kararı |
| **D** | Kurum adaptörleri (karar 5.3): başlık imzası tanınınca sormadan eşle | kurum başına 0,5–1 gün | Kurum başına örnek |
| **E** | Uygulama içi "ekstrem tanınmadı → örnek gönder" akışı (anonimleştirme uyarısıyla). "Tüm kurumları karşılamak" ancak kullanıcılardan gelen örneklerle ölçeklenir. | 1 gün | KVKK metni: kullanıcının gönüllü gönderdiği finansal belge — aydınlatma + açık rıza |

**Öneri sırası:** B (tek adaptör, herkes) → A (dosyadan okuma) → C (Midas) →
E → D. B ve A aynı örnek dosyalarla birlikte yazılabilir.

## Senden gerekenler (engelleyici)

Tutarları değiştirebilirsin; sütun başlıkları ve satır düzeni aynı kalsın:

1. **MKK e-Yatırımcı** — "Portföyüm" dökümü (Excel + PDF) ve bir aylık
   hesap ekstresi (Excel + PDF).
2. **Midas** — bir aylık ekstre PDF'i (içinde en az bir alış ve bir satış).
3. Kullandığın başka bir kurum/banka varsa onun ekstresi.

Örnekler `tmp/ekstre_ornekleri/` altına (gitignore'da; repoya girmez).

## 5.5 "PDF / dosya seçici" nedir? (sorunun cevabı)

Bugün ekstre yalnız **kopyala-yapıştır** ile giriyor. 5.5, telefondaki
dosyayı (kurumun indirdiğin Excel ya da PDF ekstresi) doğrudan seçip
içeri almak: "Dosyalar'dan seç → önizle → sepete ekle". Midas yalnız PDF
verdiği için Midas kullanıcısı için tek yol bu.

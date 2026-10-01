# Evrensel ekstre motoru — tasarım (2026-10-01)

**Karar sahibi:** kullanıcı — "Varlık ekstresi nasıl universal olarak eklenebilir;
öyle bir algoritma çözmeliyiz ki tüm formattakiler .pdf, .xlsx, .csv hepsini çözüp
uygulamaya dahil edebilmeli, farklı kolon yapıları veri tutma yapıları olmasına
rağmen. Bu çok kritik; müşterinin ilk gelişini hızlandıracak."

Önceki durum ve kurum araştırması: `KURUM_EKSTRESI_YAPILABILIRLIK_2026_09.md`
(yalnız yapıştırma vardı; dosya okuma, PDF ve kurum örneği yoktu).

## Gereksinimler

| İşlevsel | İşlevsel olmayan |
|---|---|
| PDF, `.xlsx`, `.xls` (HTML ya da eski ikili), CSV/TSV/TXT dosyasını telefondan seç | Kurum başına kod YOK — yeni kurum çoğu zaman sıfır iş |
| Sütun adı/sırası bilinmeyen tablodan sembol, adet, maliyet, tutar, tarih, alış/satış çıkar | Uydurma yok: emin olunmayan eşleme kullanıcıya sorulur |
| Portföy dökümü (anlık) ve işlem ekstresi (hareket) ikisi de | Cihazda çalışır; belge sunucuya gitmez (KVKK: finansal belge) |
| Temettü/virman/toplam satırları, tekrar eden sayfa başlıkları elenir | Mevcut satış/tür/fiyat kuralları tek yerde kalır (`CsvImportService`) |

## Mimari

```mermaid
graph TD
  Dosya["Dosya baytları"] --> Sez{"bicimiSez<br/>(imza, uzantı değil)"}
  Sez -->|PK..| XLSX["xlsxOku<br/>archive + xml"]
  Sez -->|%PDF| PDF["pdfTablolari<br/>pdfrx karakter kutuları"]
  Sez -->|"&lt;table"| HTML["htmlTablolari<br/>(.xls uzantılı HTML)"]
  Sez -->|metin| CSV["ayrilmisMetinOku<br/>kodlama + ayraç sezgisi"]
  Sez -->|D0CF| Eski["eski .xls → dürüst ret"]
  PDF --> Geo["sayfadanSatirlar<br/>kelime→satır→hücre→sütun bandı"]
  XLSX --> T["List&lt;EkstreTablosu&gt;<br/>satır × hücre"]
  HTML --> T
  CSV --> T
  Geo --> T
  T --> Anla["tablolariAnla<br/>başlık bul · sütun profili · rol ataması<br/>adet×fiyat≈tutar · güven"]
  Anla --> Kanonik["kanonik sekmeli metin"]
  Kanonik --> Parse["CsvImportService.parse<br/>(satış, tür, fiyat kuralları)"]
  Anla -->|güven < 0,75| Duzelt["Eşleme kartı + Sütunları düzelt"]
  Duzelt --> Kanonik
```

Kod: `lib/services/ekstre/` — `tablo_okuyucular.dart`, `metin_cozucu.dart`,
`pdf_tablo.dart` (saf geometri), `pdf_okuyucu.dart` (tek eklenti noktası),
`tablo_anlama.dart`, `ekstre_ice_aktarma.dart` (giriş). Ekran:
`lib/screens/csv_import_screen.dart`. Testler: `test/ekstre_motoru_test.dart`.

## Algoritma — "anlama" katmanı

1. **Başlık satırı:** ilk 40 satırda, sözlükle ≥0,6 eşleşen FARKLI rol sayısı en
   yüksek satır (en az biri sembol/adet/fiyat/tutar). Kurum unvanı, müşteri no,
   dönem satırları üstte kalabilir. Bulunamazsa tablo başlıksız sayılır.
2. **Veri satırları:** tek hücreli satırlar (başlık/dipnot), başlığın tekrarı (PDF'in
   her sayfası) ve "Toplam / Genel Toplam" satırları atlanır.
3. **Sütun profili** (≤400 hücre): sayı oranı, tarih oranı, sembol puanı (BIST
   listesi, TEFAS 3 harf, ISIN→kod, kripto, altın/döviz sözcükleri), alış/satış
   oranı (açıklama içinde de), para birimi, tür, tam sayı oranı. Sayı biçimi
   (1.234,56 / 1,234.56) sütunun kanıtından; kanıt yoksa TABLONUN kanıtından.
   Tarih düzeni (gg/aa / aa/gg) sütun bazında: ay 13+ olan tek hücre çevirir.
4. **Rol puanı** = 1,5 × başlık + 2 × içerik; içerik şartı sağlanmadan başlık rolü
   VEREMEZ. Olumsuz sözcükler: "Son Fiyat", "Güncel", "Piyasa Değeri" maliyet/tutar
   sayılmaz (portföy dökümünde maliyetle yan yana durur). Açgözlü atama, her sütun
   tek role.
5. **Sayısal roller başlıktan gelmezse:** üç sayısal sütun arasında `a × b ≈ t`
   (±%2) satırların ≥%60'ında tutuyorsa t tutar; a/b'den tam sayı oranı yüksek
   olan adet. Başlıksız tablolar böyle çözülür.
6. **Güven:** sembol/adet başlıktan değil içerikten geldiyse düşer; adet×fiyat
   tutarla uyuşmazsa ("fiyat" belki güncel fiyattır) düşer. < 0,75 → kart uyarır,
   "Sütunları düzelt" her rol için sütun seçtirir (örnek değerle).

Kanonik çıktı: `sembol adet fiyat tutar tarih "islem turu" tur "para birimi" isim`,
sayı "1234,56", tarih "gg.aa.yyyy", yön "Alış/Satış", eksi adet → satış. Yön
sütunu varken alım/satım olmayan satır (temettü, virman, bedelsiz) çıkmaz, sayısı
kartta yazar.

## PDF

PDF'te tablo yok; karakter kutuları var. `sayfadanSatirlar`: karakter → kelime
(yatay boşluk > 0,35 × yükseklik) → satır (dikey merkez, 0,5 × medyan yükseklik) →
hücre (boşluk > 0,9 × yükseklik) → **sütun bandı** (çok hücreli satırların x
aralıkları birleştirilir; her hücre en çok örtüştüğü banda). Boş hücre boş kalır,
sütun kaymaz. Sınır: taranmış (görüntü) PDF metin içermez → dürüst mesaj; OCR yok.

## Kararlar (ADR özeti)

| Karar | Seçilen | Alternatif | Neden |
|---|---|---|---|
| Dosya seçici | `file_selector` (flutter.dev) | `file_picker` | iOS'ta yalnız belge seçici; fotoğraf izni/uyarı riski yok |
| PDF metni | `pdfrx` (PDFium, MIT) | Syncfusion PDF; platform kanalları | Android'in `PdfRenderer`'ı metin çıkarmaz; Syncfusion lisans kısıtlı; pdfrx iki platformda aynı motor. Maliyet: uygulama boyutu +PDFium ikilisi |
| XLSX | `archive` + `xml` (zaten dolaylı bağımlılık) | `excel` paketi | Yalnız okuma gerekiyor; stil/tarih biçimini kendimiz çözüyoruz |
| Eski ikili `.xls` | Dürüst ret + "xlsx/CSV olarak kaydet" | BIFF8 okuyucu yazmak | Güvenilir saf Dart okuyucu yok; yarım okuma yanlış maliyet üretir |
| Belge nerede işlenir | Cihazda | Sunucu/LLM | Finansal belge dışarı çıkmaz (KVKK); çevrimdışı çalışır |
| Anlama → mevcut ayrıştırıcı | Kanonik metin | Ayrıştırıcıyı yeniden yazmak | Satış/tür/fiyat kuralları ve testleri tek yerde kalır; kullanıcı okunanı metin olarak görür/düzeltir |

## Gerçek dosya öncesi sertleştirme (2026-10-02)

Kurum dosyası görülmeden, bilinen kurum biçimlerinden (MKK e-Yatırımcı, banka
PDF'leri, "Excel'e aktar" HTML'leri) türetilen kırılma noktaları kapatıldı;
her biri `test/ekstre_motoru_test.dart`'ta bir vakadır:

| Kırılma | Düzeltme |
|---|---|
| "THYAO TÜRK HAVA YOLLARI A.O." tek hücrede, " - " yok → sembol tanınmaz, tablo reddedilir | `sembolAyikla`: ilk kelime bilinen BIST kodu / ISIN / döviz kodu ise kesin; 3–6 harf kod + ≥2 kelimelik ad ise ilk kelime; altın deyimleri bölünmez |
| "Birim Pay Fiyatı", "İşlem Adedi", "Kıymet Kodu" sözlükte çekimli yok | Başlık ve sözlük iyelik ekinden köke iner (`_kokler`) |
| Döküm'de adet × Son Fiyat ≈ Piyasa Değeri yakalanıp "tutar" sayılıyor, ardından "maliyet uyuşmuyor" sahte uyarısı | Çarpım araması başlıktan bilinen adet/fiyatı içermek zorunda |
| `20260903` bitişik tarih, `−250` Unicode eksi | `tarihCoz` / `sayiCoz` |
| HTML'in ilk 4 KB'si `<style>` → CSV sanılır; `</td>`/`</tr>` yazmayan eski çıktı → sıfır satır | 64 KB sezgi; açılış etiketine göre bölen toleranslı ayrıştırıcı |
| `<x:row>` önekli XLSX → "dolu sayfa yok" | `namespaceUri: '*'` |
| Çok sayfalı PDF'te sayfa başına bant → sütunlar sayfadan sayfaya kayar | Bantlar belge genelinde (`sayfalardanSatirlar`) |
| Sembol tanınmayınca doğrudan hata, kullanıcı için çıkmaz | En büyük tablo güven 0 ile döner; "Sütunları düzelt" açık, metin alanı boş |

## Riskler ve açık işler

- **Gerçek kurum örnekleri hâlâ yok** (MKK e-Yatırımcı, Midas PDF…). Motor örneksiz
  tasarlandı ve sentetik senaryolarla test edildi; ilk gerçek dosyalar geldiğinde
  `test/ekstre_motoru_test.dart`'a (anonimleştirilmiş) eklenmeli.
- **iOS derlemesi:** pdfrx/file_selector yerel parçaları bu makinede derlenmedi (CI).
- **Uygulama boyutu:** PDFium ikilisi — ölçüldü (`docs/CPU_GPU_VE_BOYUT_RAPORU_2026_10.md`):
  arm64 APK'da 6,4 MB, Play indirmesinde 3,0 MB. Kalması kararlaştırıldı.
- **Çok satırlı hücre (PDF):** uzun şirket adı ikinci satıra taşarsa o satır sembolsüz
  kalır ve atlanır — veri kaybı yok, ad kısalır.
- **Sonraki adım (E):** "ekstrem tanınmadı → örnek gönder" akışı (açık rızayla).

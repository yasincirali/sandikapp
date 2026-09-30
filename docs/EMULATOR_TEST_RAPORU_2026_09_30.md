# Emülatör Test Raporu — büyüme özellikleri + düzeltmeler (2026-09-30)

**Durum:** Her şey YEREL. Dal `claude/dreamy-sagan-ict187`, `origin/main`'in 28 commit
önünde (169 dosya, +15.526 / −596). **Push yapılmadı, Supabase'e hiçbir şey dağıtılmadı.**
Onay verince push'lanır.

---

## 1. Özet

| | Sonuç |
|---|---|
| Flutter `analyze lib/ test/` | Temiz |
| Flutter tam test paketi | **3755 geçti, 0 kırık** (2 kasıtlı atlanan: golden ve görsel önizleme) |
| Deno `check` (tüm edge function'lar) | Temiz |
| Deno testleri | **434 geçti, 0 kırık** |
| Emülatör kurulumu | İki emülatörde çalışıyor, çökme yok |
| Emülatör testinde bulunan | **46 bulgu** (test 1: 31, test 2: 15) |
| Düzeltilen | **38** |
| Senin kararına kalan | 4 (§4) |
| Bilinçli bırakılan / kapsam dışı | Kalanlar (§5) |

**Test yöntemi.** İki emülatörde paralel iki test agent'ı çalıştı. Ekran görüntüsü siyah
geldiği için arayüz `uiautomator` ağacından okundu, `adb` ile sürüldü. Test 1 giriş yapmış
kullanıcı akışlarını, test 2 oturumsuz akışları, demoyu ve halka arzı test etti. Test 2,
emülatöre geçici olarak açılan ikinci bir Android kullanıcısında oturumsuz çalıştı;
senin oturumlarına dokunulmadı ve o kullanıcı sonunda silindi. Düzeltmeleri altı agent,
birbirine dokunmayan dosya gruplarında yaptı. Hepsi birleştirildi, ardından ana
bulgular emülatörde yeniden doğrulandı.

---

## 2. Bu turda eklenen özellikler

Bunlar bir önceki turda yazıldı, bu turda test edildi. Hepsi Remote Config bayrağı
arkasında: **debug derlemede açık, mağaza sürümünde kapalı.**

| Özellik | Durum |
|---|---|
| F1 Örnek portföyle dene (kayıtsız demo) | Çalışıyor. Sunucuya hiç istek gitmiyor (logcat ile doğrulandı) |
| F2 İlk açılış sırası (kilit teklifi ilk varlıktan sonra, seviye sorusu) | Çalışıyor |
| F3 Anlaşılırlık (işaretli yüzde, "puan geride/önde") | Çalışıyor; bayraksız |
| F4 Fon karnesi | Çalışıyor |
| F5 Temettü kartı + öneri | İstemci çalışıyor; **sunucu tarafı dağıtılmadı** |
| F6 Halka arz takvimi | Çalışıyor; liste push'a kadar "çevrimdışı" (gömülü) |
| F9 Yıl sonu özeti anı | Yazıldı; **dağıtılmadı** |
| F11 Kayıt hunisi ölçümü | Olaylar ekleniyor |

---

## 3. Bulgular ve durumları

### Yüksek önem (5)

| # | Bulgu | Durum |
|---|---|---|
| T1-1 | Varlık ekranında dönem kâr/zararı: fon düşerken "+%7,55" yeşil | ✅ Yüzde kendi işaretini taşıyor, "fiyat" etiketiyle ayrıldı: "₺0 · fiyat −%7,55" |
| T1-2 | CSV'den gelen fon (AFT) hiç fiyatlanmıyordu; portföy ~₺24.500 eksikti | ✅ **Kök neden:** CSV içe aktarma fon kodunu `TEFAS:` önekisiz yazıyordu. Okuma tarafında düzeltildi, veri değişmedi. **Emülatörde doğrulandı:** toplam ₺1.388.018 → ₺1.410.147 |
| T1-3 | "Bakiyeyi gizle" yalnız Ana sayfada çalışıyordu | ✅ Maske biçimleyicinin içine taşındı; Portföy, Performans ve varlık ekranı da gizleniyor. **Emülatörde doğrulandı** |
| T1-4 | Özet'te "bu ay ekside" ile "alım gücün arttı" yan yana | ✅ İki rakam da doğru ama farklı aralıkları ölçüyor (TÜFE son açıklanan aya kadar). Aralık notu ve "Bu aralıkta senin getirin" etiketi eklendi |
| T2-1 | Demodaki fonlar yanlış kaynaktan fiyatlanıyordu (Yahoo'daki ABD fonu gibi) | ✅ T1-2 ile aynı kök neden |

### Orta ve düşük önem — düzeltilenler

| # | Bulgu | Düzeltme |
|---|---|---|
| T1-5, T2-5 | Yüzde biçimi karışıktı ("%-3,77", "%+107") | Tek kaynak `fmtPctIsaretli` → "−%3,77". `showSign` kaldırıldı; kaynak tarama testi var |
| T1-6, T2-6 | Kartlarda tutar işaretli, yüzde işaretsiz | Kart, Özet ve Performans başlığında işaretli. Sonuncusu emülatör doğrulamasında ayrıca yakalanıp düzeltildi |
| T1-7 | Y ekseninde aynı etiket tekrarı ("₺1,39M" ×4) | Hane sayısı ızgara adımına göre seçiliyor |
| T1-8 | "MIKTAR", "MALIYET" (Türkçe büyük harf hatası) | "MİKTAR", "ORT. MALİYET"; metinler l10n'a taşındı |
| T1-9 | Satışta "Hepsi (1) \| 10 \| 100 \| Hepsi (1)" | Yalnız eldekini aşmayan öneriler ve tek "Hepsi" |
| T1-11 | Tür dökümü ekran okuyucuda birikimi "kayıp" diye okuyordu | "artış/azalış" |
| T1-12 | Temettü "net" alanı brüt tutarla ön doluydu | Stopaj bilinmiyorsa alan boş; brüt yardımcı metinde |
| T1-13 | Aramada dolar kuru "$49,00" | "₺49,00". Aynı kural takip listesine de uygulandı |
| T1-14 | Şeritteki "Gram altın" 22 ayardı, 24 ayar varlıkla karışıyordu | Şerit 24 ayar gösteriyor. **Emülatörde doğrulandı:** 6.586 |
| T1-15 | Fon karnesi getirisi dönem çipiyle farklıydı | Kaynak farkı (TEFAS'ın açıkladığı rakam); dipnot eklendi |
| T1-16 | Brifing bildirimi zilde ve push'ta farklı yere gidiyordu, metni belirsizdi | Tek yönlendirme; hisse brifingi o hissenin ekranını açıyor. Metin: "N hisse daha hareketli" (**sunucu dağıtımı gerekiyor**) |
| T1-17 | Takip listesi TalkBack'te dokunulamıyordu; lejantta ham semboller, BIST 100'de ₺ | Satır ve + düğmesi erişilebilir; görünen adlar; endeks puan olarak |
| T1-19, T2-12 | "siz" kalıntıları | Metinler "sen"e çevrildi. Material tarih seçici için "sen" kipi delegate'i eklendi |
| T1-20, T2-7 | Yasal uyarı sayfada 3 kez | 1 kez; kapsam testi sıkılaştırıldı |
| T1-21 | Eksende "Oca 26" (26 Ocak gibi okunuyordu) | "Oca '26" |
| T1-23 | Ham sembol "ARDYZ.IS" | "ARDYZ" |
| T1-24 | Alarm güncel fiyata eşit hedefle kuruluyordu | Formda uyarı; kaydedilmiyor |
| T1-25 | Not onaysız siliniyordu; filtre sonrası liste eski kaydırma konumunda kalıyordu | "Geri al" snackbar'ı; filtrede liste başa dönüyor |
| T1-26 | "Geçen hafta" aslında son 7 gündü; zil rozeti okununca düşmüyordu | Etiket "Son 7 gün"; rozet yalnız yeni bildirimleri sayıyor |
| T1-27 | İngilizce modda çevrilmemiş metinler ve çoğul hataları | Çoğu çevrildi (§5'te kalanlar) |
| T1-28 | Etiketsiz ya da seçili durumu bildirmeyen kontroller | Segmentler seçili durumu bildiriyor; ikonlar etiketlendi |
| T1-29 | Kripto, Emtia ve Diğer tür çipleri kaydırmada gizliydi | Çipler sarmalı (`Wrap`) |
| T1-31 | Hafta sonu tarihi için "kapanış"; teknik özet "1/2" ile panel "5/8"; "₺250,0K" | "Son işlem günü kapanışı (27 Şub)"; sayım etiketleri netleşti; "₺250K" |
| T2-2 | Demoda "Çıkış yap" ikonu görünüyordu | Demoda çizilmiyor |
| T2-3 | Demo şeridi TalkBack'te hiç yoktu | **Kök neden:** iç Navigator'ın sayfa engeli (`BlockSemantics`). Ayrı kapsam; testle kilitlendi |
| T2-11 | Giriş formu e-postayı yalnız '@' ile doğruluyordu | Kayıtla aynı kural |
| T2-14 | Oturum yokken `db_logs` yazımı deneniyor, RLS hatası üretiyordu | Denenmiyor |
| T2-15 | İşlem gören halka arzda "işlem başlayana kadar…" cümlesi | Duruma uygun metin |
| — | Piyasa şeridinde "%-0,23" | "−%0,23" (ilk bulgu, koordinatör) |

---

## 4. Senin kararın gerekenler

1. **Zirvedeki Portföyler — KVKK rızası (T1-18).** Ekran "herkes kendiliğinden ve anonim
   olarak havuzdadır" diyor ve ekranda çıkış yolu yok. Anonim ve toplulaştırılmış veri olsa
   da açık rıza ya da itiraz hakkı gerekip gerekmediğini hukukçuyla netleştir. **Koda
   dokunulmadı.**
2. **Fon birimi "lot" mu "pay" mı (T1-22).** Doğru terim "pay". Ama `miktar_birimi_test`
   senin önceki örneklerinle "lot"u kilitliyor. Varlık Ekle formu artık portföyle aynı
   birimi ("lot") gösteriyor.
3. **Eski USD kayıtları (T1-30).** Silinenler'de TL kurla girilmiş döviz kayıtları
   (ör. "$2.200 → ₺4,15M"). İsteğe bağlı tek seferlik veri migration'ı gerekiyor; yazılmadı.
4. **Kripto kapsamında "Değişim yok" (T1-10).** Kök neden: dönem içinde açılan pozisyon
   için taban, serinin ilk dolu günü alınıyor. Tabanı "0 + katkı" modeline çevirmek
   `piyasaEtkisi`'nin bütün yüzeylerini değiştirir; ürün kararı. Ayrıca `kripto-seri`
   fonksiyonunun iki sunucuda da veri döndürdüğü kontrol edilmeli.

---

## 5. Bilinçli bırakılanlar ve bilinen kalıntılar

- **Yasal metinler "siz" kipinde kaldı:** `disclaimerText`, `legal_doc_screen`, KVKK dışa
  aktarma notu. Hukuk metni olduğu için değiştirilmedi.
- **Tarih aralığı seçicide TalkBack "to" okuyor:** Flutter'ın içine sabit yazılmış; yamasız
  düzelmez. Görsel başlık doğru.
- **~40 yerde sabit `'tr_TR'` tarih biçimi:** İngilizce modda "29 Eyl" kalabilir. Ortak
  yardımcı `context.tarihDili` eklendi, yalnız Performans kartında uygulandı.
- **~30 yerde `Semantics` + `ExcludeSemantics` kalıbı:** Takip listesinde yakalanan
  erişilebilirlik hatası başka yerlerde de olabilir; ayrıca taranmalı.
- **T2-4:** Oturumsuz ekranlardaki metin alanlarında etiket yok; `hintText` okunuyor.
- **T2-9:** Demoda Portföy sekmesindeyken geri tuşu demoyu doğrudan kapatıyor.
- **T2-10:** Demoda arama da "kaydedilmez" sayfasını açıyor; metin aramaya uygun değil.
- **T2-13:** Kullanıcı adı uygunluk isteği ağ hatasında sessiz kalıyor.
- **T2-8:** Teknik görünüm sayım etiketleri düzeltildi; anlamı yeniden gözden geçirilebilir.
- **Hafta içi resmî tatiller:** Tarih önizlemesi bu günlerin kapanışını bilmiyor.
- **"Fiyat alınamadı" işareti yok:** Fiyatı dönmeyen varlık kartında sessizce eski fiyatla
  duruyor. Öneri: `PortfolioState.fiyatsizSemboller` + kartta küçük not.
- **AFT kaydı veritabanında `is_manual_price=true` ise** okuma düzeltmesi uygulanmaz
  (bilinçli). Canlı veritabanında doğrulanmadı.

---

## 6. Sunucuya dağıtılması gerekenler (hiçbiri yapılmadı)

Hepsi iki sunucuya birlikte: Actions → Supabase deploy, hedef `ikisi`, sonda
`sema_esitlik.py`.

| Parça | Neden |
|---|---|
| Migration `0086_temettu_bildirimleri` + `temettu-yakala` + Vault secret | Temettü push'u (F5) |
| Migration `0087_yil_sonu_ozeti_ani` + `calendar-nudge` | Yıl sonu özeti anı (F9) |
| `daily-brief` | Brifing hisse ekranına gider, yeni metin (T1-16) |
| `analyze-signals` | `_shared/technical_analysis.ts` açıklama metni değişti (T1-31) |

Ayrıntılar ve bayrak açma sırası: `YAPMAN_GEREKENLER.md`.

---

## 7. Test sırasında gerçek hesaplarda değişen veri

Testler canlı sunucuya bağlı iki gerçek hesapta yapıldı.

| Hesap | Eklenen | Geri alınan |
|---|---|---|
| emulator-5554 | Hedef ₺2,5M; not "test notu 123"; TTE 10 pay; TUPRS 100 lot ×2; TUPRS alarmı ₺383,25 | Hepsi kaldırıldı ya da silindi. Tema, dil ve seviye eski hâline döndü |
| emulator-5556 | NETGL 1 lot (halka arz "Katıldım" testi) | Silindi |

**Tam geri alınamayanlar:** Silme yumuşak olduğu için TTE, TUPRS ×2 ve NETGL test lotları
iki hesabın "Silinenler" listesinde duruyor (5554'te sayaç 49 → 52). Uygulamada kalıcı
silme yok; istersen veritabanından temizlenebilir. 5554'te dil yeniden seçildiği için
`pref_locale='tr'` ayarı yazıldı; işlevsel olarak varsayılanla aynı.

**Emülatör ortamı:** emulator-5556 yüksek bellek yükü yüzünden bir kez yeniden başlatıldı
ve bir kez kendiliğinden çekirdek paniği verdi. Test için açılan ikinci Android kullanıcısı
silindi. Bakiye görünür bırakıldı.

---

## 8. Emülatörde kendin bakmak istersen

1. **Ana:** şeritte "+%0,05 / −%…", Gram altın ~6.586. "Son 7 gün" satırı (piyasa açılınca).
2. **Portföy:** AFT fiyatlı mı, toplam ~₺1,41M. Zarardaki kartta "−₺… · −%…". Kart okunda
   "MİKTAR". 1 lotluk hisseyi kaydır → Sat → yalnız "Hepsi (1)".
3. **Bakiyeyi gizle** (Ana'daki göz): Portföy ve Performans'ta "₺••••".
4. **Performans › Özet › 1A:** TÜFE aralık notu, "Bu aralıkta senin getirin".
5. **TUPRS ekranı:** "GÜNLÜK −%…", yasal uyarı tek. Alarmda güncel fiyatı yazınca kırmızı
   uyarı. Temettü "Kaydet"te alan boş, brüt tutar yardımcı metinde.
6. **Ara › Amerikan Doları:** "₺49,00".
7. **Takip Listesi:** BIST 100 ₺'siz.
8. **Varlık Ekle:** tüm tür çipleri kaydırmadan görünür.
9. **Çıkış yap → "Önce bir göz at":** demoda çıkış ikonu yok, fonlar TEFAS fiyatıyla.
10. **Profil › Halka arzlar** → NETGL detayı: işlem gören kayıt için doğru ipucu.

Emülatör ekranı siyah görünürse gerçek cihazda bakılmalı.

---

## 9. Sonraki adım

Onay verirsen: push → PR → CI (5 kontrol) → `main`'e birleştirme → TestFlight.
Bayraklar mağazada kapalı gider. `YAPMAN_GEREKENLER.md`'deki sırayla açılır.

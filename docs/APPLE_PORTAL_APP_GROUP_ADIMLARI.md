# Apple Developer Portalı — App Group Kurulumu (elle)

Live Activity'nin TestFlight'a çıkabilmesi için portalda yapılması gereken
**tek seferlik** adımlar. Tahmini süre: 10 dakika.

> Bu adımlar `match`/fastlane tarafından **yapılamaz**. `match` provisioning
> profili üretir ama App Group capability'sini App ID'ye bağlamaz — o
> portalda elle işaretlenir.

---

## Kopyalanacak değerler

Bunları elle yazma, kopyala. Tek karakter farkı sessiz hataya yol açar.

| Ne | Değer |
|---|---|
| App Group ID | `group.com.sandik.app` |
| Ana uygulama Bundle ID | `com.sandik.app` |
| Uzantı Bundle ID | `com.sandik.app.SandikWidget` |
| Team ID | `6267T8PYDR` |

**Doğrulama kaynağı:** bu değerler sırasıyla
`ios/Runner/Runner.entitlements`, `ios/SandikWidget/SandikWidget.entitlements`,
`lib/services/home_widget_service.dart:42` ve `project.pbxproj` içinden
okundu — üçü birbiriyle eşleşiyor.

---

## Giriş

<https://developer.apple.com/account/resources/identifiers/list>

Sağ üstte doğru **Team**'in seçili olduğundan emin ol (`6267T8PYDR`).
Birden fazla ekibe üyeysen yanlış ekipte oluşturulan identifier
görünmez ve "neden bulamıyorum" döngüsüne girersin.

---

## ADIM 1 — App Group oluştur

1. Sol menü: **Identifiers**
2. Sayfanın sağ üstündeki listede **App Groups**'u seç
   *(varsayılan "App IDs" gelir — bu açılır listeyi değiştirmen gerekiyor)*
3. Mavi **+** butonu
4. **App Groups** seçili → **Continue**
5. Doldur:
   - **Description:** `Sandik Paylasimli Depo`
     *(sadece portal içi etiket; Türkçe karakter kullanma — portal bazen reddediyor)*
   - **Identifier:** `group.com.sandik.app`
6. **Continue** → **Register**

### ✅ Doğrulama
App Groups listesinde `group.com.sandik.app` görünüyor.

### ❌ Atlanırsa / yanlış yazılırsa
CI'da `build_app` adımı şu hatayla kırılır:

```
Provisioning profile "match AppStore com.sandik.app" doesn't match the
entitlements file's value for the com.apple.security.application-groups
entitlement
```

> **Zaten varsa:** Bu adımı atla, ADIM 2'ye geç. Var olanı silme —
> `HomeWidgetService` da aynı grubu kullanıyor, silmek ana ekran
> widget'ını da bozar.

---

## ADIM 2 — Ana uygulamaya App Group'u bağla

1. **Identifiers** → listeyi **App IDs**'e çevir
2. `com.sandik.app` satırına tıkla
3. Capability listesinde **App Groups** satırını bul
4. Solundaki **kutucuğu işaretle**
5. Aynı satırdaki **Edit** (veya **Configure**) butonuna bas
6. Açılan pencerede `group.com.sandik.app` **kutucuğunu işaretle**
7. **Continue** → sağ üst **Save**
8. Çıkan "Modify App Capabilities" uyarısında **Confirm**

### ✅ Doğrulama
Sayfayı yenile → **App Groups** hem işaretli hem de altında
`group.com.sandik.app` yazıyor.

### ⚠️ En sık yapılan hata
**Kutucuğu işaretleyip Edit'e basmamak.** Capability açık görünür ama
altında hiçbir grup seçili değildir. Portal bu durumda uyarı vermez;
hata ancak CI'da yukarıdaki entitlement mesajıyla ortaya çıkar.
Adım 5–6'yı atlama.

### ❗ Save sonrası: profil yenilenmeli
App ID'nin capability'si değiştiğinde **mevcut provisioning profilleri
geçersizleşir.** Bu yüzden ADIM 4 (match'i yeniden çalıştırma) zorunlu —
"zaten profilim vardı" diye atlanamaz.

---

## ADIM 3 — Uzantı için yeni App ID

1. **Identifiers** → mavi **+**
2. **App IDs** → **Continue**
3. **App** → **Continue**
4. Doldur:
   - **Description:** `Sandik Widget Extension`
   - **Bundle ID:** **Explicit** seçili olsun → `com.sandik.app.SandikWidget`
5. Capability listesinde **App Groups** kutucuğunu işaretle
6. **Continue** → **Register**

> ⚠️ **Bu adım İKİ TURDA yapılır.** Kayıt ekranında App Groups kutucuğunu
> işaretlediğinde **Configure/Edit butonu ÇIKMAZ** — bu normaldir, hata
> değildir. App ID henüz kaydedilmediği için portalın bağlayacağı bir şey
> yoktur. Grubu kayıttan SONRA seçeceksin (adım 7).
>
> (ADIM 2'de Configure hemen çıkıyordu çünkü `com.sandik.app` zaten
> kayıtlıydı — düzenleme ekranındaydın, kayıt ekranında değil.)

7. **Kayıttan sonra grubu bağla:**
   - **Identifiers** listesine dön
   - Yeni oluşan `com.sandik.app.SandikWidget` satırına tıkla
   - **Şimdi** App Groups satırının sağında **Configure/Edit** görünür
   - Tıkla → `group.com.sandik.app` işaretle → **Continue**
   - Sağ üst **Save** → **Confirm**

### ✅ Doğrulama
App IDs listesinde `com.sandik.app.SandikWidget` görünüyor **ve** detayına
girdiğinde App Groups hem işaretli hem altında `group.com.sandik.app` yazıyor.

Adım 7'yi atlarsan capability açık ama grup boş kalır — portal uyarı
vermez, hata ancak CI'da entitlement uyuşmazlığı olarak çıkar.

### ❌ Atlanırsa
```
No profiles for 'com.sandik.app.SandikWidget' were found
```

> **Not:** `match` bu App ID'yi `readonly: false` modunda kendisi de
> oluşturabilir — ama **App Group capability'sini bağlamaz.** O yüzden
> match'e bırakmak yerine burada elle oluşturmak daha güvenli; bıraktıysan
> match koştuktan sonra bu sayfaya dönüp adım 5–6'yı uygulaman gerekir.

### Push Notifications hakkında
Ana uygulamada `aps-environment` var ama **uzantıda yok** — uzantının
entitlements dosyasında yalnızca App Groups tanımlı. Bu doğru: Live
Activity şu an push ile güncellenmiyor (bkz. `TECHNICAL_DEBT.md`).
Uzantı App ID'sinde Push Notifications capability'sini **işaretleme**;
işaretlersen entitlements ile profil arasında uyumsuzluk çıkar.

---

## ADIM 4 — Provisioning profillerini yenile

Portal işi bitti; sıra CI'da.

1. GitHub → **Actions** sekmesi
2. Sol menü: **iOS — Setup Match Certificates (one-time)**
3. **Run workflow** → branch `main` → yeşil **Run workflow**

Bu, `Matchfile`'daki **iki** bundle id için de profil üretip şifreli olarak
cert repo'suna yazar.

### ✅ Doğrulama — log'da şu iki satırı ara
```
match AppStore com.sandik.app
match AppStore com.sandik.app.SandikWidget
```

İkincisi **yoksa** Matchfile okunmamış demektir; bana haber ver.

### ❌ Bu adım atlanırsa
ADIM 2'de capability değiştiği için **eski profiller artık geçersiz.**
`beta` lane'i entitlement uyuşmazlığı hatasıyla kırılır — App Group'u
doğru kurmuş olsan bile.

---

## ADIM 5 — TestFlight

`main`'e push et. `ios-testflight` workflow'u otomatik koşar.

---

## Sorun giderme

| Hata | Sebep | Çözüm |
|---|---|---|
| `doesn't match the entitlements file's value for ... application-groups` | ADIM 2'de Edit'e basılmadı, grup seçilmedi | ADIM 2 adım 5–6, sonra ADIM 4 |
| `No profiles for 'com.sandik.app.SandikWidget' were found` | ADIM 3 veya 4 atlandı | Her ikisini sırayla |
| `No profiles for 'com.sandik.app' were found` | ADIM 2'den sonra ADIM 4 koşulmadı | ADIM 4 |
| Portal'da App Group listesi boş görünüyor | Yanlış Team seçili | Sağ üstten `6267T8PYDR` |
| Yeni App ID kaydederken App Groups'ta **Configure çıkmıyor** | Beklenen davranış — kayıt ekranında grup seçilemez | Önce Register, sonra ADIM 3 adım 7 |
| `Authentication credentials are missing or invalid` | ASC API key secret'ı süresi dolmuş | Yeni key üret, secret'ları güncelle |

---

## Neden App Group gerekiyor?

Uygulama ile uzantı **ayrı süreçlerdir** ve normalde birbirinin verisine
erişemez. App Group, ikisinin ortak bir kabı paylaşmasını sağlar.

Sandık'ta iki tüketicisi var:
- `HomeWidgetService` → ana ekran widget'ı (7/24)
- Live Activity → kilit ekranı (seans içi)

Grup kimliği **üç yerde birebir** aynı olmalı: portalda, iki entitlements
dosyasında ve `home_widget_service.dart:42`'de. Şu an üçü de
`group.com.sandik.app` — eşleşiyor.

> **Gizlilik hatırlatması:** App Group içeriği cihaz genelinde okunabilir.
> Bu yüzden her iki servis de yalnızca ÖZET yazar; varlık listesi, ticker
> veya kullanıcı kimliği asla girmez. Bakiye gizliyken tutar hiç
> üretilmez. Bu davranış `test/live_activity_session_test.dart` ve
> `test/home_widget_privacy_test.dart` ile kilitli.

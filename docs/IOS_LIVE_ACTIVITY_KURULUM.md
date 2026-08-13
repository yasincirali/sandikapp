# iOS Live Activity — Kurulum ve Doğrulama

Kilit ekranı + Dynamic Island "Piyasa Seansı" yüzeyi. Kod tamamlandı;
bu doküman **Mac'te yapılması gereken** adımları ve doğrulama listesini
içerir.

> ⚠️ Kod Windows'ta yazıldı. `xcodebuild` ve Xcode burada çalışmadığı için
> **derleme hiç denenmedi**. Aşağıdaki adımlar bir Mac'te tamamlanmadan
> TestFlight'a gönderilmemeli.

---

## 1. Ne yapıldı (kod tarafı — tamam)

| Dosya | Rol |
|---|---|
| `ios/SandikWidget/SandikAttributes.swift` | Veri sözleşmesi — **iki hedefe birden** üye |
| `ios/SandikWidget/SandikTheme.swift` | `sandik.dart` token'larının Swift kopyası |
| `ios/SandikWidget/SandikLogoMark.swift` | Logo — brief'teki SVG'nin birebir karşılığı |
| `ios/SandikWidget/SandikLiveActivity.swift` | Kilit ekranı + 4 Dynamic Island durumu |
| `ios/SandikWidget/SandikWidgetBundle.swift` | Uzantı giriş noktası (`@main`) |
| `ios/Runner/LiveActivityPlugin.swift` | ActivityKit ↔ MethodChannel köprüsü |
| `lib/services/live_activity_service.dart` | Seans yaşam döngüsü + gizlilik |
| `test/live_activity_session_test.dart` | 13 test — seans saatleri, gizlilik |

Ayrıca güncellendi: `Runner.entitlements` (App Group), `Info.plist`
(`NSSupportsLiveActivities`), `project.pbxproj` (yeni hedef + iOS 17.0),
`Matchfile` / `Fastfile` (ikinci bundle id), `main.dart`, `auth_service.dart`.

**Yeni bundle id:** `com.sandik.app.SandikWidget`

---

## 2. Mac'te yapılacaklar

### 2.1 Apple Developer portalı

**→ Adım adım rehber: [`APPLE_PORTAL_APP_GROUP_ADIMLARI.md`](APPLE_PORTAL_APP_GROUP_ADIMLARI.md)**

Özet:
1. **App Groups** → `group.com.sandik.app` oluştur
2. `com.sandik.app` App ID'sine App Groups capability'sini bağla
   *(kutucuğu işaretlemek YETMEZ — Edit'e basıp grubu seçmek gerekir)*
3. `com.sandik.app.SandikWidget` App ID'sini oluştur, aynı gruba bağla

⚠️ Adım 2'den sonra mevcut provisioning profilleri **geçersizleşir**;
`setup-match` workflow'u yeniden koşturulmalı (bkz. 2.2).

### 2.2 Provisioning profilleri

Matchfile'a ikinci id eklendi. Profilleri üret:

```bash
cd ios
bundle exec fastlane setup_match_certificates
```

Bu, private cert repo'suna `match AppStore com.sandik.app.SandikWidget`
profilini yazar. **Atlanırsa** CI build şu hatayla kırılır:

```
No profiles for 'com.sandik.app.SandikWidget' were found
```

### 2.3 Xcode doğrulaması

```bash
cd ios && open Runner.xcworkspace
```

`project.pbxproj` elle düzenlendi — **Xcode'un dosyayı sorunsuz açması ilk
doğrulamadır.** Açıldıktan sonra kontrol et:

- [ ] Hedef listesinde **SandikWidgetExtension** görünüyor
- [ ] `SandikAttributes.swift` → File Inspector → **Target Membership**'te
      HEM `Runner` HEM `SandikWidgetExtension` işaretli
      *(bu paylaşım şart; yalnızca birindeyse diğer taraf derlenmez)*
- [ ] Runner → Build Phases → **Embed Foundation Extensions** içinde
      `SandikWidgetExtension.appex` var
- [ ] Her iki hedefte Signing & Capabilities → **App Groups** →
      `group.com.sandik.app` işaretli

### 2.4 Derleme

```bash
flutter build ios --release
```

---

## 3. Cihazda doğrulama

Simülatörde Dynamic Island için **iPhone 15 Pro veya üstü** gerekir.

| Durum | Nasıl tetiklenir | Beklenen |
|---|---|---|
| Kilit ekranı | Seans saatinde uygulamayı aç, telefonu kilitle | Yeşil zeminli iki sütunlu kart |
| Compact | Uygulamayı arka plana al | Solda amber logo, sağda ▲/▼ + yüzde |
| Expanded | Dynamic Island'a basılı tut | Gold toplam + alt pill |
| Minimal | İkinci bir Live Activity başlat | Yalnızca logo |

**Seans saati dışında hiçbir şey görünmez** — bu tasarım gereğidir
(bkz. bölüm 5). Test için `LiveActivityService._openHour` / `_closeHour`
geçici olarak genişletilebilir.

### Gizlilik kontrolü (elle)

1. Uygulamada bakiyeyi gizle (göz ikonu).
2. Kilit ekranına bak → **`••••••` görünmeli**, rakam değil.

Bu, `test/live_activity_session_test.dart` içinde de kilitlendi ama
kilit ekranı hassas bir yüzey olduğu için elle de doğrulanmalı.

---

## 4. DM Sans notu (isteğe bağlı)

Uzantı şu an **sistem fontunu** `monospacedDigit()` ile kullanıyor.
Hizalama bozulmaz — yalnızca karakter biçimi uygulamadan farklıdır.

Marka fontunu gömmek istersen:

1. `assets/fonts/DMSans-*.ttf` dosyalarını `SandikWidgetExtension`
   hedefine ekle (Target Membership).
2. `ios/SandikWidget/Info.plist` → `UIAppFonts` dizisine dosya adlarını yaz.
3. `SandikTheme.swift` → `sandikNumber` / `sandikLabel` içinde
   `.custom("DMSans-Bold", size:)` kullan, `.monospacedDigit()` **kalsın**.

Uzantı binary boyutu artar; bu yüzden varsayılan olarak yapılmadı.

---

## 5. Neden "sürekli açık" değil de seans?

`home_widget_service.dart` içindeki eski not Live Activity'ye karşı uyarıyordu
ve gerekçesi hâlâ geçerli: Apple, ActivityKit'i **başı ve sonu olan** olaylar
için tasarladı; sistem oturumu 8 saat sonra kendiliğinden sonlandırır.

Bu yüzden yüzey bir **piyasa seansına** bağlandı (hafta içi 10:00–18:10):

- Apple'ın beklediği "canlı olay" kalıbına oturur → App Review'da savunulabilir
- 8 saatlik sistem limiti seans süresini aşmaz → kullanıcı "kayboldu" demez
- Seans dışında pil/kota harcanmaz

`HomeWidgetService` (ana ekran, 7/24) ile bu servis **birbirinin yerine
geçmez** — farklı yüzeyler, farklı yaşam döngüleri.

---

## 6. Geri alma

`project.pbxproj` elle düzenlendi. Bozulursa:

```bash
git checkout ios/Runner.xcodeproj/project.pbxproj
```

Oturum yedeği ayrıca şurada:
`%TEMP%\claude\c--projects-PortfoyTakip\<oturum>\scratchpad\project.pbxproj.bak`

Bütünlük doğrulaması (parantez dengesi, referans bütünlüğü, yetim nesne)
`scratchpad/verify_pbxproj.py` ile yapıldı ve **geçti** — ama bu Xcode'un
kendi parser'ının yerini tutmaz.

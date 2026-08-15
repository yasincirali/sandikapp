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

## 4b. APNs push kurulumu (canlı güncelleme için ZORUNLU)

Push olmadan kilit ekranı yalnızca uygulama önplandayken tazelenir.

### Apple Developer portalı
1. **Keys** → **+** → **Apple Push Notifications service (APNs)** işaretle
2. İndirilen `.p8` dosyasını sakla — **bir daha indirilemez**
3. Key ID'yi ve Team ID'yi not al

### Supabase secret'ları

```bash
supabase secrets set APNS_KEY_ID=<key-id>
supabase secrets set APNS_TEAM_ID=6267T8PYDR
supabase secrets set APNS_BUNDLE_ID=com.sandik.app
supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_XXX.p8)"
# TestFlight/App Store: api.push.apple.com (varsayılan)
# Xcode'dan doğrudan cihaza kurulumda: api.sandbox.push.apple.com
supabase secrets set APNS_HOST=api.push.apple.com
```

> ⚠️ **Sandbox/üretim ayrımı.** Xcode'dan cihaza kurduğun build
> **sandbox** token üretir; TestFlight ve App Store **üretim**. Yanlış
> host'a push atmak sessizce `BadDeviceToken` döner ve token silinir.

### Vault + cron

```sql
select vault.create_secret('<service-role-key>', 'live_activity_cron_secret');
```

Migration'ları uygula:
```bash
supabase db push          # 0032 + 0033
supabase functions deploy push-live-activity
```

### Doğrulama

```sql
-- Oturum kaydedildi mi? (uygulamayı seans saatinde aç, kilitle)
select token, expires_at, show_amounts, summary is not null as ozet_var
from live_activity_sessions;

-- Cron çalışıyor mu?
select jobname, schedule, active from cron.job
where jobname like 'live-activity%';
```

Elle tetikleme (hata ayıklama):
```bash
curl -X POST "$SUPABASE_URL/functions/v1/push-live-activity" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"userId":"<uuid>"}'
```

Yanıt `{"sent":1,...}` ise push gitti. `{"sent":0,"reason":"aktif oturum yok"}`
ise oturum kaydedilmemiş — Swift tarafında token dinleyicisini kontrol et.

---

## 4c. Kilit ekranında tutar gizleme

**iOS kilitli/açık ayrımı VERMEZ.** ActivityKit'te böyle bir sinyal yok;
aynı `ContentState` iki durumda da render edilir. Bu yüzden "kilitliyken
gizle, açılınca göster" davranışı **teknik olarak kurulamaz.**

Bunun yerine kullanıcı tercihi taşınır:
**Ayarlar → Gizlilik → "Kilit ekranında tutarı göster"** (varsayılan KAPALI).

| Tercih | Kilit ekranı | Dynamic Island |
|---|---|---|
| Kapalı (varsayılan) | Günlük % + grafik | Logo + % |
| Açık | Toplam + net kazanç + grafik | Tutar + % |

Yüzde ve grafik her iki durumda da görünür: ikisi de portföy
**büyüklüğünü** ele vermez. Grafik `sparkline` olarak **normalize** (0…1)
gönderilir — ham TL değeri cihazın o yüzeyine hiç ulaşmaz.

Uygulama içi göz ikonu (`hideBalance`) daha güçlüdür: açıkken tercih ne
olursa olsun tutar da grafik de gönderilmez.

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

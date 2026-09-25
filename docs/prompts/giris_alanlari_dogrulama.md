# Giriş alanları — tek dolgu kuralı: doğrulama ve tamamlama

> **Nasıl kullanılır:** Bu dosyanın tamamını MCP'lerin bağlı olduğu yerel
> Claude Code oturumuna yapıştır (ya da "docs/prompts/giris_alanlari_dogrulama.md
> dosyasını uygula" de). Dal: `claude/dreamy-sagan-ict187`.
> Önce: `git fetch origin && git checkout claude/dreamy-sagan-ict187 && git pull`.

---

## Bağlam (bulut oturumunda yapılanlar — Flutter/MCP yoktu, hiçbir şey koşulmadı)

Kullanıcı şikâyeti: arama kutusunda ("Ara...") ikonun sağında farklı renkte bir
şerit. Kullanıcı kararı (2026-09-25): **"uygulama içi tüm inputfield'larda
uygulanmalı."**

Kök neden: `lib/main.dart` → `_buildTheme` → `inputDecorationTheme` her alana
`filled: true, fillColor: p.overlay` (dark'ta beyaz %4.5) veriyordu; bu,
`lib/theme/sandik.dart` → `inputFill` kuralıyla çelişiyordu. Kutu içindeki
`TextField` ikinci bir dolgu dikdörtgeni çiziyordu.

İki commit:
1. Tema varsayılanı = `inputFill` kuralı (dark şeffaf, light `surface2`, hairline
   çerçeve, odakta amber 1.5, köşe `SandikRadius.mdAll`). `add_asset_screen.dart`
   arama alanına `filled: false`. `comparison_screen.dart` araması temaya bırakıldı.
2. Alan bazlı `fillColor`/`BorderSide.none` ezmeleri kaldırıldı: add_asset hızlı
   giriş, `asset_detail/karsilastirma_secici.dart`, `settings_screen.dart`
   (geri bildirim), `widgets/gorunum_cipi.dart`, `widgets/dividend_dialog.dart`,
   `widgets/quick_adjust_dialog.dart` (×2), `widgets/hedef_sheet.dart`. OTP
   hücreleri: dolgu `inputFill`, boş kenar hairline. Ölü statik
   `Sandik.inputDecoration` silindi. Yeni test:
   `test/input_fill_consistency_test.dart`.

**Güvenme, doğrula.** Aşağıdaki adımların her biri bir iddiayı sınar.

---

## Adım 0 — Skill yönlendirmesi (CLAUDE.md kuralı)

Başlamadan çağır:
- `flutter-architecture`, `flutter-expert` (UI) — ⚠️ Bloc/GoRouter/ham `Colors.*`
  önerilerini **alma**; Riverpod + tasarım sistemi geçerli.
- `flutter-testing` (Adım 3–4 testleri için; `test-master` değil).
- `emil-design-eng` (Adım 5 görsel yargı; CSS sözdizimi alınmaz).
- Sonda `/code-review` → `code-reviewer`.

## Adım 1 — Statik doğrulama (dart MCP)

Ham kabuk yerine **dart MCP** araçlarını kullan:
1. `analyze` → `lib/` ve `test/`. Beklenen: yeni uyarı yok. Özellikle
   kullanılmayan import (`SandikRadius` artık kullanılmayan dosyalar olabilir),
   `sandik.dart`'ta silinen statikten kalan referans.
2. Şu testleri koş:
   ```
   test/input_fill_consistency_test.dart
   test/light_theme_surface_test.dart
   test/light_mode_render_test.dart
   test/design_token_leak_test.dart
   test/spacing_scale_test.dart
   test/touch_target_size_test.dart
   test/l10n_coverage_test.dart
   ```
   Kırılan varsa: testin koruduğu **kararı** oku (yorumlar karar kaydıdır),
   kodu karara uydur; eşiği gevşetme.
3. `test/` altında `fillColor`, `overlay`, `surface1`, `BorderSide.none`,
   `enabledBorder`, `inputDecoration` geçen testleri bul; alanların görünümünü
   sabitleyen (golden, `find.byWidgetPredicate` ile dekorasyon okuyan) test varsa
   koş.

## Adım 2 — Kapsam: hiçbir alan kaçmadı mı? (codebase-memory MCP)

Bulut oturumu yalnızca grep yaptı. Graph ile teyit et:
1. `search_graph` / `query_graph`: şu tiplerin **tüm** kullanım yerleri —
   `TextField`, `TextFormField`, `CupertinoTextField`, `CupertinoSearchTextField`,
   `SearchBar`, `SearchAnchor`, `Autocomplete`, `DropdownButtonFormField`,
   `DropdownMenu`, `InputDecorator`, `InputDecoration.collapsed`.
2. Her biri için tabloyu doldur: dosya:satır | dekorasyon kaynağı (tema /
   `context.inputDecoration` / özel) | zemin (sayfa `background`, alt sayfa
   `surface2`, diyalog `surface1`, kart) | durum (uyumlu / düzeltildi).
3. Özellikle bak:
   - **Cupertino alanları** Material temasını okumaz → `BoxDecoration.color`
     `context.inputFill` + `Border.all(color: context.c.hairline)` olmalı
     (`add_watchlist_screen.dart` örnek).
   - **`DropdownButtonFormField` / `DropdownMenu`** `inputDecorationTheme`'i
     alır → artık hairline çerçeveli; bu istenen mi, kontrol et.
   - Alan kendi `Container`/`SandikCard`'ının içindeyse → `filled: false` +
     `InputBorder.none` (çift çerçeve/dolgu olmasın).
   - `enabled: false` alanlar (profil ortaklık kodu kilitliyken): tema
     `disabledBorder` vermiyor → Material varsayılanı mı düşüyor? Gerekirse
     temaya `disabledBorder: hairline` (soluk) ekle.
4. Kaçan varsa düzelt; tarama testine yeni deseni ekle
   (`input_fill_consistency_test.dart`).

## Adım 3 — Davranış testi: tema gerçekten doğru değeri veriyor mu

`test/input_fill_consistency_test.dart`'a (ya da yeni
`test/input_theme_render_test.dart`) **widget testi** ekle — kaynak taraması
yetmez, render edilen değer ölçülmeli:
- Gerçek `_buildTheme`'e erişim yoksa `SandikApp`'in tema üretimini test
  edilebilir bir fonksiyona çıkarmayı değerlendir (minimal refactor, özette
  işaretle).
- Light ve dark için: dekorasyonsuz bir `TextField` pump et,
  `tester.widget<InputDecorator>(...).decoration` ile
  `fillColor == context.inputFill` ve `enabledBorder.borderSide.color == hairline`
  doğrula.
- Kutu içi arama alanı (add_asset seçici alt sayfası): `InputDecorator`'ın
  `filled == false` olduğunu doğrula.

## Adım 4 — Görsel kanıt (emülatör render edemiyor → golden)

CLAUDE.md: yerel emülatörler Flutter'ı siyah çiziyor; görsel doğrulama widget
testiyle. `flutter-testing` skill'iyle:
1. `test/goldens/input_fields_golden_test.dart` yaz: her alan tipini (düz,
   prefix ikonlu arama, çok satırlı, suffix'li sayı, hata durumu, odaklı,
   disabled, OTP hücresi, kutu içi arama) **üç zeminde** (`background`,
   `surface1` diyalog, `surface2` alt sayfa) × **iki tema** ızgarası olarak
   çiz.
2. `flutter test --update-goldens test/goldens/input_fields_golden_test.dart`,
   PNG'yi aç ve bak. Kabul ölçütü: **hiçbir hücrede alanın içi zeminden farklı
   renkte değil (dark)**; çerçeve her zeminde seçilebiliyor; light'ta beyaz alan
   krem sayfada öne çıkıyor, beyaz alt sayfada çerçeveyle ayrışıyor.
3. Goldenlar platforma duyarlıysa (font) CI'da kırılmaması için repodaki
   mevcut golden düzenine uy; yoksa testi `tags: ['golden']` ile işaretle ve
   PNG'yi yalnız inceleme için kullan — bunu özette yaz.

## Adım 5 — Tasarım yargısı (ui-ux-pro MCP + emil-design-eng)

- `get_platform_guidelines` (iOS + Android) ve `search_ui` ("text field dark
  mode outlined vs filled", "search field in bottom sheet"): hairline kontrastı
  (dark'ta beyaz %7) dokunma hedefini ve "burası yazılabilir" algısını
  karşılıyor mu? **Renk paletini alma** — yalnız yerleşim/hiyerarşi yargısı.
- Sonuç "çerçeve çok silik" ise: yeni token öner (`inputBorder`), paletin iki
  modunda tanımla, `light_mode_contrast_test`'e ekle. Tek başına karar verme,
  özette seçenek olarak sun.

## Adım 6 — Tam doğrulama ve dağıtım

```bash
bash tool/deploy_emulators.sh   # analyze → tüm testler → build → install → çökme kontrolü
```
Kırılırsa dur, düzelt, tekrar koş. (Görsel doğrulamanın yerini tutmaz — Adım 4.)

## Adım 7 — Kayıt

1. `codebase-memory-mcp cli index_repository --repo-path "c:\projects\PortfoyTakip"`
   (**önce** indeksle — `index_repository` ADR'yi siler).
2. Sonra `manage_adr`: "Giriş alanı dolgusu tek kaynak: tema = inputFill; ekran
   `fillColor` vermez; kutu içi alan `filled: false`." Gerekçe: dört ayrı
   "içi farklı renk" şikâyeti; zemin sayfadan sayfaya değiştiği için sabit dolgu
   her zaman birinde yabancı kalıyor.
3. CLAUDE.md → **Kurallar → Tasarım sistemi** paragrafına bir cümle ekle:
   "Giriş alanı dolgusu/çerçevesi temadan gelir; ekranda `fillColor` yazma,
   kendi kutusundaki alana `filled: false` ver (`input_fill_consistency_test`)."
   Son güncelleme satırını tarihle.
4. Tur: yalnız renk/çerçeve değişti → "tur etkilenmedi" yaz (tur metni kuralı).
   Sürüm notu istenmedi → ekleme.

## Adım 8 — İnceleme ve commit

- `/code-review` çalıştır, bulguları düzelt.
- Commit mesajı Türkçe, "ne değil neden". Dal `claude/dreamy-sagan-ict187`;
  force push yok.

## Özet biçimi (sonda bana yaz)

- Adım 1–6 her birinin sonucu (geçti / kırıldı → ne yapıldı).
- Adım 2 tablosu (kaçan alan var mıydı).
- Golden PNG yolu ve senin gözlemin.
- Açık kalan tasarım sorusu (çerçeve kontrastı) varsa seçenekleriyle.
- "Skill dışı" kalan adım varsa nedeni; CLAUDE.md ile skill çelişkisi varsa hangisi.

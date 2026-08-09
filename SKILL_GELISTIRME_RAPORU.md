# Skill Entegrasyonu ve UI Geliştirme Raporu

**Tarih:** 2026-08-09
**Kapsam:** 5 skill deposunun incelenmesi, projeye entegrasyonu ve bu skill'lerin
işaret ettiği somut geliştirme fırsatları.

---

## 1. En önemli bulgu: stack uyuşmazlığı

İstenen 5 deponun **dördü web için yazılmış**. Ölçüm (markdown dosyası sayısı):

| Depo | Flutter/Dart geçen dosya | Web (CSS/React/GSAP/Tailwind) geçen dosya |
|---|---|---|
| `taste-skill` | 1 | 12 |
| `awwwards-animations-skill` | 1 | 15 |
| `claude-minimal-plugin` | 0 | 18 |
| `ui-ux-pro-max-skill` | 13 | 74 |
| `anthropics/skills` | — | stack-bağımsız + doküman araçları |

Bu depoları **olduğu gibi** kurmak somut bir zarar üretir: skill'ler `useGSAP`,
`ScrollTrigger`, `Lenis`, Tailwind class'ı ve `transform: translateY()` üretmeye
yönlendirir. Bunlar `.dart` dosyasında karşılıksızdır; en iyi ihtimalle gürültü,
en kötü ihtimalle projeye gereksiz JS bağımlılığı önerisidir.

**Bu yüzden seçici kurulum yaptım** — hepsini kopyalamak istenen sonucu vermezdi.
Gerekçeler aşağıda; kurulmayanlar da listelendi.

---

## 2. Kurulan skill'ler

`.claude/skills/` altına (toplam ~2.9 MB):

| Skill | Kaynak | Neden |
|---|---|---|
| `skill-creator` | anthropics | Projeye özel skill yazmak için; stack-bağımsız |
| `frontend-design` | anthropics | Estetik yön/tipografi yargısı, framework'süz |
| `ui-ux-pro-max` | nextlevelbuilder | **Flutter stack'i var**; 84 stil, 192 palet, 98 UX kuralı |
| `design-system` | nextlevelbuilder | Token mimarisi (primitive→semantic→component) |
| `design-taste-frontend` | taste-skill | "Generic AI görünümü" teşhisi — audit-first yaklaşımı |
| `high-end-visual-design` | taste-skill | Ucuz/şablon görünüm engelleri |
| `redesign-existing-projects` | taste-skill | Var olanı bozmadan yükseltme; bu projenin durumu tam bu |
| `awwwards-animations` | DevMartinese | Sadece zamanlama/easing sezgisi için (React kodu kullanılmaz) |

Zaten kurulu olan 9 skill (`animate`, `apple-design`, `emil-design-eng`,
`improve-animations`, `review-animations`, `find-animation-opportunities`,
`animation-vocabulary`, `prototype`, `pick-ui-library`) korundu.

### Bilinçli olarak kurulmayanlar

- **`brand-guidelines`** (anthropics) — Anthropic kurumsal renk/tipografisi.
  sandık'ın amber/gold + DM Sans kimliğiyle doğrudan çakışır. Kurmak zararlı olurdu.
- **`canvas-design`** (anthropics) — 5.6 MB poster/PDF üretim aracı. Mobil uygulamayla ilgisiz;
  tek başına kurulu tüm skill'lerin iki katı yer kaplıyordu.
- **`claude-minimal-plugin`'in tamamı** — içeriğinin neredeyse tamamı ya kopya
  (`taste-skill`'in birebir aynısı: `soft-skill`, `minimalist-skill`, `redesign-skill`,
  `stitch-skill`, `output-skill`, `brutalist-skill`), ya Kore pazarına özel
  (`korean-frontend-defaults`), ya da alakasız (`claude-hud` statusline, `agent-browser`).
  Bu depodan **özgün ve bu projeye yarayan hiçbir şey çıkmadı**.
- **`mcp-builder`** — iki depoda birden var; bu projede MCP *tüketiyoruz*, yazmıyoruz.
- **`brutalist` / `stitch` / `gpt-taste` / `imagegen-*`** — sandık'ın sakin,
  finansal-güven estetiğiyle çelişen görsel diller.

### Çakışma: `ui-ux-pro-max` ↔ `ui-ux-pro-mcp`

`.mcp.json`'da zaten kurulu olan `ui-ux-pro-mcp` ile yeni kurulan `ui-ux-pro-max`
skill'i **aynı ürünün** iki dağıtım biçimi (MCP v103 stil / skill v2.13 84 stil).
İkisini birden sorgulamak token israfı. Önerilen kullanım:
hızlı arama → **MCP**, offline/derin referans + Flutter stack örnekleri → **skill**.

### Koruma katmanı

`.claude/skills/SKILLS_README.md` yazıldı. İçeriği:
- "Yargıyı al, sözdizimini alma" kuralı
- **CSS → Flutter karşılık tablosu** (`transition` → `SandikMotion`,
  `prefers-reduced-motion` → `MediaQuery.disableAnimations`,
  `will-change` → `RepaintBoundary`, `aria-label` → `Semantics` …)
- Marka renk/font önerilerini reddetme kuralı (kimlik sabit)
- Hangi skill hangi durumda, hangileri neden kurulmadı

Bu dosya olmadan kurulum net negatif olurdu; asıl değer buradadır.

---

## 3. Projenin gözden geçirilmesi

**Sağlık:** `flutter analyze` → **13 info, 0 hata/uyarı**. Temiz zemin.
Kod: 80 Dart dosyası, 24 ekran, ~22.8k satır ekran kodu.
Tasarım sistemi (`lib/theme/sandik.dart`, 27 KB) olgun: renk/boşluk/yarıçap/hareket
tokenları ve `SandikTappable` gibi hazır primitive'ler mevcut.

### Ölçülen sorun: tasarım sistemi var ama tutarlı uygulanmıyor

| Ölçüm | Sayı | Yorum |
|---|---|---|
| `lib/theme/` **dışında** hardcoded `Color(0x…)` | **80** | Token atlanmış |
| `lib/theme/` dışında çıplak `Duration(milliseconds:)` | **42** | `SandikMotion` atlanmış |
| `SandikMotion.*` kullanımı | 32 | Yani hareketlerin ~%43'ü tokensız |
| Sayısal `EdgeInsets` | **218** | `SandikSpace` kullanımı sadece 54 |
| `GestureDetector` + `InkWell` | 51 + 15 | `SandikTappable` sadece **13** |
| `Semantics(` kullanan dosya | **5** / 80 | Erişilebilirlik zayıf |
| `HapticFeedback` | **4** | Finansal işlemde dokunsal geri bildirim çok az |
| Reduced-motion kontrolü | **3** | Erişilebilirlik + App Store incelemesi riski |

Yani: **sistem doğru kurulmuş, disiplin uygulanmamış.** Kurulan
`redesign-existing-projects` ve `design-system` skill'lerinin tam hedefi budur.

---

## 4. Skill'lere göre geliştirme önerileri

Etki/maliyet sırasıyla. Hiçbiri henüz uygulanmadı — onay bekliyor.

### Öncelik 1 — Token disiplinini geri getir *(düşük risk, yüksek getiri)*
- 80 hardcoded rengi `Sandik.*` tokenlarına taşı; eksik ton varsa tokena ekle.
- 42 çıplak `Duration` → `SandikMotion.press/state/surface`.
- 218 sayısal `EdgeInsets` → `SandikSpace` (en sık tekrarlayanlardan başla).
- Kalıcılık için `analysis_options.yaml`'a kural + `test/` altına token-sızıntı testi.
- *İlgili skill:* `design-system`, `redesign-existing-projects`.

### Öncelik 2 — Dokunma geri bildirimini teklileştir *(hissiyatta en görünür kazanç)*
66 ham `GestureDetector`/`InkWell` var, `SandikTappable` sadece 13 yerde.
Basılabilir her yüzey aynı 110 ms scale + aynı haptik ile tepki vermeli.
Şu an ekranlar arası dokunuş hissi tutarsız.
- *İlgili skill:* `emil-design-eng`, `apple-design`.

### Öncelik 3 — Erişilebilirlik ve reduced-motion *(App Store/Play riski)*
- 80 dosyanın 5'inde `Semantics` var; para tutarları, kazanç/kayıp delta'ları ve
  ikon-only butonlar ekran okuyucuya anlamsız geliyor.
- Yalnız 3 reduced-motion kontrolü — `MediaQuery.disableAnimations` merkezî olarak
  `SandikMotion` içinde ele alınmalı (tek noktadan tüm süreleri sıfırlayacak şekilde).
- Kazanç/kayıp yalnız **renkle** anlatılıyorsa renk körlüğü için işaret/ok eklenmeli.
- *İlgili skill:* `apple-design`, `ui-ux-pro-max` (98 UX guideline).

### Öncelik 4 — Grafik ve sayı sunumu
`charts_screen` (1708 satır), `performance_screen` (2692), `portfolio_performance_screen` (2440).
`fl_chart` üzerinde eksen/tooltip/boş-durum tutarlılığı ve para formatı tek elden
gözden geçirilmeli. `ui-ux-pro-max`'ta 25 chart tipi + Flutter stack örnekleri var.
- *İlgili skill:* `ui-ux-pro-max`, `dataviz`.

### Öncelik 5 — Hareket cilası *(en son, en görünür)*
- `Hero` sadece 6 yerde: liste → varlık detayı geçişi doğal Hero adayı.
- Liste girişlerinde stagger, sayı değişiminde count-up, boş durumlar için
  hazırlanmış (skeleton) yükleme.
- **Uyarı:** `awwwards-animations` bu konuda GSAP/Lenis önerecek — projeye
  kurulmayacak; sadece süre/easing sezgisi alınacak.
- *İlgili skill:* `animate`, `find-animation-opportunities`, `apple-design`.

### Öncelik 6 — Ekran boyutu (teknik borç)
`performance_screen` 2692 ve `add_asset_screen` 2631 satır. `TECHNICAL_DEBT.md`'de
bu parçalama **bilinçli olarak ertelenmiş durumda** — kullanıcı kararı olduğu için
burada yalnızca hatırlatma olarak yer alıyor, öneri olarak değil.

---

## 5. Özet

- 5 deponun 4'ü web odaklı; **seçici** kurulum yapıldı (8 skill kuruldu, gerisi gerekçeli olarak elendi).
- Asıl değer kurulumda değil, **`SKILLS_README.md` çeviri/koruma katmanında** —
  bu olmadan skill'ler Flutter koduna CSS önerirdi.
- Proje teknik olarak sağlıklı (0 analyze hatası), tasarım sistemi olgun;
  gerçek açık **sistemin tutarsız uygulanması** (80 hardcoded renk, 66 ham tap
  hedefi, 5 dosyada erişilebilirlik).
- Öncelik 1–3 düşük riskli ve ölçülebilir; onay verilirse buradan başlanabilir.

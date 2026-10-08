# Kurulu Skill'ler — Flutter Kullanım Rehberi

Bu proje **Flutter/Dart** bir mobil uygulamadır. Kurulu design/animation skill'lerinin
büyük çoğunluğu **web (CSS, React, GSAP, Tailwind)** için yazılmıştır.

> **Kural:** Bu skill'lerden gelen *yargıyı* (hiyerarşi, ritim, boşluk, zamanlama, kontrast)
> al; *sözdizimini* (CSS property, Tailwind class, GSAP çağrısı, React hook) **alma**.
> Bir skill sana `transform: translateY(-4px)` derse, karşılığı `Transform.translate` +
> `SandikMotion` süresidir — `.dart` dosyasına CSS yazılmaz.

## Zorunlu ön kontrol

Herhangi bir UI değişikliğinden önce:

1. `lib/theme/sandik.dart` içindeki tokenlar **tek kaynaktır**.
   - Renk: `Sandik.amber / gold / gain / loss / surface1 / surface2 / background / text90…text20`
   - Boşluk: `SandikSpace.xs(4) sm(8) md(16) lg(24) xl(32) xxl(48)`
   - Yarıçap: `SandikRadius.sm(8) md(14) lg(20)`
   - Hareket: `SandikMotion.press(110ms) state(180ms) surface(240ms)`,
     `enter = easeOutCubic`, `move = easeInOutCubic`
2. Skill bir palet/font önerirse **reddet** — marka kimliği (amber/gold + DM Sans) sabittir.
   Skill'den alınacak şey renk *değeri* değil, kontrast ve hiyerarşi mantığıdır.
3. Yeni bir sabit (hardcoded `Color(0x…)`, çıplak `Duration(...)`, sihirli padding)
   ekleme — tokena ekle, oradan kullan.

## Skill → Flutter karşılık tablosu

| Skill'in dediği | Flutter'daki karşılığı |
|---|---|
| `transition: 200ms ease-out` | `AnimatedContainer(duration: SandikMotion.state, curve: SandikMotion.enter)` |
| `transform: scale(0.97)` (press) | `SandikTappable` (zaten var — yeniden yazma) |
| `@media (prefers-reduced-motion)` | `MediaQuery.of(context).disableAnimations` |
| `box-shadow` katmanı | `BoxShadow` **veya** `surface1`/`surface2` yükseklik tonu |
| `stagger` liste girişi | `AnimatedList` / index'e göre gecikmeli `TweenAnimationBuilder` |
| `ScrollTrigger` / parallax | `ScrollController` + `AnimatedBuilder` (GSAP yok, `Lenis` yok) |
| `will-change` / GPU accel | `RepaintBoundary` |
| `aria-label` | `Semantics(label: …)` |
| Tailwind spacing ölçeği | `SandikSpace` |

## Hangi skill ne zaman

**Doğrudan kullanılabilir (stack-bağımsız):**
- `skill-creator` — bu projeye özel yeni skill yazarken
- `apple-design` — iOS HIG, jest fiziği, spring, reduced-motion (TestFlight tarafı için en uygunu)
- `emil-design-eng` — komponent cilası, görünmez detaylar
- `animation-vocabulary` — bir hareketin adını bulmak
- `claude-automation-recommender` — Claude Code kurulumunu (hook, subagent, skill,
  plugin, MCP) projeye göre önerir. **Salt-okunur**, dosya oluşturmaz/değiştirmez.
  Kaynak: `anthropics/claude-plugins-official` → `plugins/claude-code-setup/`
  (kurulum 2026-08-31, yerel marketplace kopyasından).

  ⚠️ **Flutter körlüğü — çıktısını süzerek oku.** Skill'in tarama komutları
  `package.json` / `pyproject.toml` / `Cargo.toml` arar; `pubspec.yaml` **arama
  listesinde yok**. Yani stack'i kendiliğinden tanımaz; sorarken "Flutter/Dart
  projesi, bağımlılıklar `pubspec.yaml`'da" diye söyle, yoksa boş profil çıkarır.

  ⚠️ **Kurulu MCP'leri yeniden önerir.** `codebase-memory-mcp` (Memory MCP),
  `dart` ve `ui-ux-pro-mcp` zaten `.mcp.json`'da. Skill "Memory MCP kur",
  "Supabase MCP kur" derse önce mevcut üçlüyle çakışıyor mu bak.
  Supabase önerisi geçerli olabilir — henüz kurulu değil.

**Yargısı alınır, kodu alınmaz (web kaynaklı):**
- `design-taste-frontend`, `high-end-visual-design`, `redesign-existing-projects`,
  `frontend-design` — "generic görünüm" teşhisi için iyi; ürettikleri CSS/HTML kullanılmaz
  - İlk üçünün kaynağı `github.com/Leonxlnx/taste-skill` (MIT; depo klasörleri
    `taste-skill`, `soft-skill`, `redesign-skill`). **2026-10-01 kontrol:** depo
    `ce26fc2` (2026-09-26) ile kurulu üç `SKILL.md` bayt bayt AYNI — güncelleme yok.
    Depoda sonradan gelen ve kurulmayanlar: `brandkit`, `imagegen-frontend-mobile`,
    `imagegen-frontend-web`, `image-to-code-skill` (görsel ÜRETİM aracı ister; bu
    ortamda yok, üstelik web/Codex akışı), `minimalist-skill` (sıcak monokrom editoryal
    web estetiği — sandık paletiyle çakışır), `output-skill` (yanıt uzunluğu
    davranışını ezer; CLAUDE.md'nin özet düzeniyle çakışır), `taste-skill-v1`
    (v2'nin eski kopyası, aynı ad ailesi — çift yükleme).
- `awwwards-animations` — React/GSAP. Sadece *zamanlama ve easing sezgisi* için oku;
  `useGSAP`, `Lenis`, `motion/react` bu projeye **kurulmaz**
- `animate`, `improve-animations`, `review-animations`, `find-animation-opportunities`
  — web varsayımlı; öneriyi Flutter'a çevirerek uygula

**Çakışma uyarısı:**
- `ui-ux-pro-max` (skill) ile `ui-ux-pro-mcp` (MCP, `.mcp.json`) **aynı ürünün** iki
  dağıtımıdır. İkisini birden sorgulamak token israfıdır.
  Tercih: hızlı arama için **MCP**, offline/derin referans için **skill**.
  Skill'in Flutter stack'i vardır (`search_stack` → flutter) — web çıktısı alırsan yanlış stack'tesin.
- `design-system` skill'i CSS değişkeni/token mimarisi anlatır; burada o katman
  zaten `lib/theme/sandik.dart`. Yeni token *mimarisi* kurma, var olanı genişlet.

**Kurulmadı (bilinçli):**
- `brand-guidelines` — Anthropic kurumsal kimliği, sandık markasıyla çakışır
- `canvas-design` — poster/PDF üretimi (5.6 MB), mobil uygulamayla ilgisiz
- `korean-frontend-defaults`, `brutalist-skill`, `stitch-skill`, `gpt-tasteskill`,
  `imagegen-*`, `agent-browser`, `claude-hud` — bu ürünün estetiğiyle veya stack'iyle ilgisiz
- `mcp-builder` — iki repoda da var, MCP *yazmıyoruz*, tüketiyoruz.
  (Karıştırma: `claude-automation-recommender` MCP **önerir** ve kuruldu;
  `mcp-builder` MCP sunucusu **yazar** ve kurulmadı.)

---

# Jeffallan/claude-skills (kurulum 2026-09-14)

Kaynak: `github.com/Jeffallan/claude-skills` (MIT, plugin adı `fullstack-dev-skills`
v0.4.16, 67 skill / 5.0 MB). **67'nin 14'ü kuruldu (760 KB).**

Yukarıdaki design/animation skill'leri **web** kaynaklıydı; bu paket ise **stack**
kaynaklı. Farklı bir süzgeç gerekir: oradaki kural "kodunu alma, yargısını al" idi.
Burada tersi geçerli — kod örnekleri doğru dilde gelir ama **yanlış mimariyi** önerebilir
(bkz. `flutter-expert` uyarısı). Süzgeç: **CLAUDE.md kuralları her zaman kazanır.**

## Kurulanlar

**Stack — doğrudan ilgili:**
- `flutter-expert` — widget desenleri, performans, proje yapısı.

  ⚠️ **Mimari çakışması — iki referansını kullanma.** `references/bloc-state.md`
  (259 satır) ve `references/gorouter-navigation.md` bu projenin kurallarına
  **aykırıdır**: durum yönetimi **Riverpod**, navigasyon **`adaptiveRoute` +
  `pushGuarded`** (CLAUDE.md). Skill "Bloc kur" / "go_router ekle" derse **reddet**.
  Kullanılacak referanslar: `riverpod-state.md`, `widget-patterns.md`,
  `performance.md`, `project-structure.md`.

  ⚠️ Tema/token bilmez — `context.c` / `SandikSpace` yerine ham `Colors.*` ve
  `fontSize:` üretir. `design_token_leak_test` bunu yakalar ama **önce sen yakala**.

- `swift-expert` — iOS Live Activity (`ios/`) ve ana ekran widget'ı Swift tarafı.
  SwiftUI + async/await + actor. Üç katmanlı Swift sözleşmesine dokunurken işe yarar.

**Supabase/Postgres tarafı** (`supabase/migrations/`, Edge Functions):
- `postgres-pro` — EXPLAIN, JSONB, VACUUM, extension. RLS/`SECURITY DEFINER`
  incelemesinde en isabetlisi.
- `sql-pro` — sorgu yazımı, window function, CTE, indeks stratejisi.
- `database-optimizer` — yavaş sorgu teşhisi, indeks tasarımı, kilit çekişmesi.

  ⚠️ Üçü de örtüşür. Tek soruda **birini** seç: şema/sorgu *yazımı* → `sql-pro`,
  Postgres'e *özgü* özellik → `postgres-pro`, *yavaşlık teşhisi* → `database-optimizer`.

**Güvenlik:**
- `security-reviewer` — yapılandırılmış audit raporu (severity + remediation).
  `docs/` altındaki iki kaynak audit'in (A/B/C/D, S1-S8) formatına yakın.
- `secure-code-guardian` — auth/authorization *yazarken*. OWASP Top 10, input
  doğrulama. Not: örnekleri web (Zod, CORS/CSP, JWT); buradaki karşılığı
  **RLS + GRANT + `requireCronSecret()`**.

**Genel:**
- `code-reviewer` — geniş kapsamlı inceleme (doğruluk + performans + bakım).
- `debugging-wizard` — stack trace, log korelasyonu, hipotez güdümlü teşhis.
- `test-master` — test mimarisi, mock stratejisi, kapsam boşluğu.
- `architecture-designer` — ADR yazımı, teknoloji ödünleşimi.
- `code-documenter` — docstring, API dokümantasyonu.
- `spec-miner` — dokümansız koddan spesifikasyon çıkarma.
- `the-fool` — şeytanın avukatı, pre-mortem, red team. Stack-bağımsız; bir kararı
  bilerek zorlatmak için.

**Video / motion graphics:**
- `remotion-motion-graphics` — Remotion (React tabanlı video). Mağaza tanıtım
  filmi, özellik duyuru videosu, Reel/Short için. Kaynak:
  `github.com/haidrrrry/claude-remotion-skill`, kurulum 2026-09-16.

  ⚠️ **Uygulama kodu değildir.** React/TypeScript üretir; çıktısı `lib/` altına
  girmez, ayrı bir Remotion projesinde durur (repoya ekleniyorsa yeri
  kararlaştırılır — `tool/` veya ayrı repo). Flutter tarafına Remotion
  bağımlılığı **girmez**.

  **Araç: Remotion** (`remotion-dev/remotion`, React tabanlı video). Depo
  **klonlanmadı** — ~4.2 GB monorepo ve video üretmek için gereksiz; skill'in
  kendisi de `npm install remotion @remotion/cli` diyor. Video projesi kurulunca
  bağımlılık oradan gelir, sürüm hep güncel olur (kullanıcı kararı 2026-09-16).
  Lisans standart OSS değil (NOASSERTION) — şirket/ticari kullanımda
  `remotion.dev/license` okunur; bu proje tek geliştiricili.

  ⚠️ Kendi tema dosyası (`assets/theme.ts`) ve renk paleti vardır; sandık'ın
  amber/gold/gain/loss + DM Sans kimliğiyle **çakışır**. Tanıtım videosunda
  uygulamanın kimliği kazanır — skill'in motion kuralları (easing, stagger,
  spring) alınır, **paleti alınmaz**. Aynı kural `ui-ux-pro-mcp`'de de geçerli.

## Çakışma uyarıları

- `code-reviewer` / `security-reviewer` ↔ **yerleşik `/code-review` ve
  `/security-review`**. Yerleşikler bu depoya göre ayarlıdır (diff hedefleme,
  `ReportFindings`, `--fix`). **Önce yerleşiği kullan**; bu ikisi yerleşiğin
  kapsamadığı bir şey istendiğinde (ör. uyumluluk kontrol listesi, severity'li
  audit raporu) devreye girer.
- `test-master` ↔ kurulu **`flutter-testing`**. `test-master` Flutter/Dart'tan
  **hiç söz etmez** (k6, Artillery, OWASP odaklı). Flutter testi için
  `flutter-testing` doğru olandır; `test-master` yalnızca *strateji/kapsam*
  sorusunda okunur.
- `architecture-designer` ADR yazar ↔ ADR'ler **`codebase-memory-mcp`'nin
  `manage_adr`'ında** tutulur. Skill'in ürettiği ADR'yi dosyaya değil oraya yaz
  (⚠️ `index_repository` ADR'yi siler — önce indeksle, ADR'yi sonra yaz).
- `flutter-expert` ↔ kurulu `flutter-architecture` / `flutter-navigation` /
  `flutter-animations` / `flutter-adaptive-ui`. Bunlar **resmî Flutter** kaynaklıdır
  ve çelişkide **onlar kazanır**.

## Kurulmadı (bilinçli) — 53 skill

- **Kullanılmayan stack (~40):** `wordpress-pro`, `shopify-expert`,
  `salesforce-developer`, `rails-expert`, `laravel-specialist`, `php-pro`,
  `django-expert`, `django-storages-s3`, `fastapi-expert`, `nestjs-expert`,
  `nextjs-developer`, `react-expert`, `react-native-expert`, `vue-expert`,
  `vue-expert-js`, `angular-architect`, `javascript-pro`, `typescript-pro`,
  `python-pro`, `golang-pro`, `rust-engineer`, `cpp-pro`, `csharp-developer`,
  `dotnet-core-expert`, `java-architect`, `kotlin-specialist`,
  `spring-boot-engineer`, `game-developer`, `embedded-systems`, `pandas-pro`,
  `spark-engineer`, `cli-developer`, `websocket-engineer`, `graphql-architect`,
  `legacy-modernizer`, `microservices-architect` …

  `react-native-expert` ve `swift-expert` gerekçesi ayrışır: RN **kurulmadı**
  (rakip framework, `flutter-expert` ile tetikleme gürültüsü yaratır), Swift
  **kuruldu** (`ios/` altında gerçekten Swift kodu var).

  `typescript-pro` sınırdaydı — Edge Function'lar Deno/TS. Kurulmadı: o dosyalar
  küçük ve kuralları (`cron_auth.ts`, `fcm.ts`, fail-closed) projeye özgü;
  genel TS skill'i bunları bilmez.

- **Altyapı — bu projede yok:** `kubernetes-specialist`, `terraform-engineer`,
  `cloud-architect`, `devops-engineer`, `sre-engineer`, `chaos-engineer`,
  `monitoring-expert`. Arka uç **Supabase** (yönetilen); gözlem **Crashlytics +
  Supabase logları**. Prometheus/Grafana/k6 yığını yok.
- **ML/LLM:** `ml-pipeline`, `rag-architect`, `fine-tuning-expert`,
  `prompt-engineer` — ürün LLM içermiyor.
- **`mcp-developer`:** MCP *tüketiyoruz*, yazmıyoruz (üstteki `mcp-builder`
  kararıyla aynı gerekçe).
- **`atlassian-mcp`:** Jira/Confluence yok. İş takibi `YAPMAN_GEREKENLER.md` +
  `TECHNICAL_DEBT.md`.
- **`api-designer`:** REST/GraphQL *tasarımı*. Burada API yüzeyi Supabase'in
  üretttiği PostgREST + RPC'dir; tasarlanmaz, şemadan doğar.
- **`playwright-expert`:** Web E2E. Mobil karşılığı `integration_test` +
  `flutter_driver`.
- **`fullstack-guardian`, `feature-forge`:** geniş kapsamlı "her şeyi yap"
  skill'leri; kurulu uzmanlarla ve CLAUDE.md iş akışıyla örtüşüyor.

## Komutlar kurulmadı

Depo ayrıca 9 workflow komutu getiriyor (`commands/`: epic planning, discovery,
execution, retrospectives). **Kurulmadı** — Jira/Confluence iş akışına bağlılar,
bu proje tek geliştiricili ve o rolü `YAPMAN_GEREKENLER.md` + `TECHNICAL_DEBT.md`
zaten görüyor.

## Güncelleme

Dosya kopyası olarak kuruldu (plugin marketplace olarak **değil**) — `.claude/`
gitignore'da olduğu için kurulum bu makineye özgüdür, upstream güncellemesi
otomatik gelmez. Tazelemek için ilgili depoyu yeniden klonlayıp yalnızca
kurulu dizinleri kopyala; bu dosyadaki uyarıları **koru** (upstream onları bilmez).

İki ayrı kaynak vardır:
- Ana küme (14 dizin) — Claude skills deposu.
- `remotion-motion-graphics` — `github.com/haidrrrry/claude-remotion-skill`.
  Depo kökünde skill **alt dizindedir**; kopyalanan yalnızca
  `remotion-motion-graphics/` (+ `examples/`). Depodaki `demo.mp4`, `demo.gif`
  ve `examples/videos/` alınmadı (7.5 MB, referans değeri yok).
  Tazeleme:
  ```bash
  git clone --depth 1 https://github.com/haidrrrry/claude-remotion-skill.git /tmp/rms
  cp -r /tmp/rms/remotion-motion-graphics .claude/skills/
  cp -r /tmp/rms/examples .claude/skills/remotion-motion-graphics/
  rm -rf .claude/skills/remotion-motion-graphics/examples/videos
  ```
  ⚠️ SSH (`git@github.com:`) bu makinede host key doğrulamasında kırılır —
  HTTPS kullan.


## brag (kurulum 2026-09-17)

Kaynak: `latent-spaces/brag` (MIT). `/plugin` bu ortamda çalışmadığı için skill
`skills/brag/` klasöründen elle kopyalandı: `.claude/skills/brag/` (proje) ve
`~/.claude/skills/brag/` (global). Hyperframes alan skill'leri
(`hyperframes-core/-cli/-audio/-animation/-creative/-keyframes`) `npx hyperframes
skills` ile `~/.claude/skills/` altına kuruldu.

- Ne yapar: projeyi okuyup 15–25 sn'lik "launch" videosu planlar (rubrik → plan →
  brief), render'ı **Hyperframes**'e (HeyGen, HTML+GSAP) devreder. Müzik
  (ende.app) ve CC0 SFX (Kenney) skill'le gelir.
- Bu projede: mağaza önizlemesinin anlatımlı sürümü
  `store_listing/preview_video/brag-output/` (README orada). Remotion kurgusu
  (`src/`) olduğu gibi duruyor; iki hat birbirinden bağımsız.
- ⚠️ `--voice` Kokoro'ya bağlı ve **Türkçe ses yok**. Anlatım için
  `python -m edge_tts --voice tr-TR-AhmetNeural` (veya EmelNeural) kullan,
  WAV'ı `assets/vo/` altına koy; brag'in "let the voice set the pace" kuralı aynen.
- ⚠️ Hyperframes `ffmpeg`'i PATH'te ister; Remotion'un compositor ffmpeg'i **olmaz**
  (kısıtlı build). `composition/tools/` altındaki ffmpeg-static'i PATH'e ekle.
- ⚠️ Müzik lisansı skill README'sinde "yayınlamadan önce doğrula" diyor —
  mağaza yüklemesinden önce `YAPMAN_GEREKENLER.md` maddesine bak.

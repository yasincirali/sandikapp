# Faz 10 — Draw Tools Implementation Plan

Bu doküman Faz 10 (grafik üzerine kullanıcı çizim araçları) için mimari ve
implementasyon planıdır. **Kod yazılmadı** — bir sonraki seansta buradan
başlanır.

## Kapsam

Kullanıcının grafik üzerine şu araçlarla çizim yapabilmesi:

1. **Trend line** (2 nokta arası düz çizgi)
2. **Horizontal line** (S/R — tek Y'de yatay çizgi, tüm X boyunca)
3. **Fibonacci retracement** (2 nokta arası 0/23.6/38.2/50/61.8/78.6/100
   seviye çizgileri)

Çizimler **kalıcı** — DB'ye kaydedilir, kullanıcı ekranı kapatıp açınca
tekrar görünür. Her çizim tek bir varlığa (ticker) bağlıdır.

## DB şeması

Yeni tablo `chart_annotations`:

```sql
CREATE TABLE chart_annotations (
  id TEXT PRIMARY KEY,          -- uuid
  user_id TEXT NOT NULL,        -- auth kullanıcısı
  ticker TEXT NOT NULL,         -- hangi varlık grafiği
  kind TEXT NOT NULL,           -- 'trend' | 'hline' | 'fib'
  color INTEGER,                -- ARGB int
  data TEXT NOT NULL,           -- JSON payload (aşağıda)
  created_at INTEGER NOT NULL   -- ms epoch
);
CREATE INDEX ix_chart_annotations_user_ticker
  ON chart_annotations(user_id, ticker);
```

**data JSON payload — kind'e göre**:

```json
// trend
{"x1": 12345.6, "y1": 105.20, "x2": 12400.3, "y2": 110.50}
// hline
{"y": 108.75}
// fib
{"x1": 12345.6, "y1": 105.20, "x2": 12400.3, "y2": 110.50}
// (fib de trend gibi 2 nokta; 7 seviye chart tarafında hesaplanır)
```

X koordinatı price grafiğinin kendi X uzayında (gün-fraction cinsinden).
Y ham fiyat (TRY veya varlığın currency'si — grafik ekseniyle uyumlu).

## Mimari

### Katmanlar

```
┌─ ZoomableChart (mevcut) ────────────────────────────────┐
│ ┌─ LineChart ──────────────────────────────────────────┐│
│ │ Segments, MA20, compare bar…                         ││
│ └──────────────────────────────────────────────────────┘│
│ ┌─ CrosshairOverlay (mevcut)                           ││
│ └──────────────────────────────────────────────────────┘│
│ ┌─ DrawableChartLayer (YENİ) ──────────────────────────┐│
│ │ CustomPaint — mevcut & taslak çizimleri              ││
│ │ GestureDetector — yeni çizim başlatma & seçim        ││
│ └──────────────────────────────────────────────────────┘│
│ ┌─ TimeScaleDragZone (mevcut, alt 32px)                ││
│ └──────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘

┌─ DrawToolPalette (YENİ, chip strip'in yanına)  ─────────┐
│  ✎ Trend  ─  H-line  Fib   [Silgi]                      │
└─────────────────────────────────────────────────────────┘
```

### Widget/state yeni bileşenleri

- **`DrawableChartLayer`** (`lib/widgets/drawable_chart_layer.dart`)
  - Parametreler:
    - `List<ChartAnnotation> annotations` (mevcut çizimler)
    - `DrawTool? activeTool` (`trend | hline | fib | null`)
    - `Rect chartRect` (LineChart'ın çizim alanı — pixel<>data mapping için)
    - `double viewMinX/maxX/minY/maxY`
    - `void Function(ChartAnnotation) onCreated` / `onDeleted`
  - CustomPaint ile tüm annotations'ları çizer
  - Active tool varsa: parmak dokun → nokta1, sürükle → nokta2 (canlı önizleme),
    kaldır → onCreated tetikle
  - Tool yoksa: annotation'ya tap → seçili → uzun bas = sil confirm

- **`DrawTool` enum** (`lib/models/draw_tool.dart`)
  ```dart
  enum DrawTool { trend, horizontal, fibonacci }
  ```

- **`ChartAnnotation` model** (`lib/models/chart_annotation.dart`)
  - `id, userId, ticker, kind, color, data, createdAt`
  - `factory ChartAnnotation.trend(...)`, `.hline(...)`, `.fib(...)`
  - `toJson()`, `fromJson()`, `toMap()`, `fromMap()` (sqflite için)

- **`AnnotationDao`** (`lib/services/annotation_dao.dart`)
  - `Future<List<ChartAnnotation>> forTicker(String userId, String ticker)`
  - `Future<void> insert(ChartAnnotation)`
  - `Future<void> delete(String id)`

- **`chartAnnotationsProvider(String ticker)`** — Riverpod
  ProviderFamily. StreamProvider olabilir (DB değişiklikleri anında chart'a
  yansır).

- **`DrawToolPalette`** — küçük horizontal chip strip
  - Icon buttonlar: trend / hline / fib / seçim modu
  - Aktif tool amber highlight
  - Sağda `Icons.delete_sweep` "tümünü sil" (confirm ile)

### Pixel ↔ data koordinat dönüşümü

`ZoomableChart` LayoutBuilder'dan `_chartWidth` biliyor ama `LineChart`'ın
kendi iç padding'i (grid, axis labels) var. Bunu hesaba katmak için:

- `LineChart` içinde `getTouchedSpot` gibi bir API'den çizim rect'ini almak
  yerine, `LineChartData` içindeki `minX/maxX/minY/maxY` + `titlesData`
  reservedSize'ları biliyoruz. **Approximate mapping** yeterli olur:
  - `leftAxisWidth ≈ 72` (mevcut reservedSize)
  - `bottomAxisHeight ≈ 32`
  - Bu değerleri `DrawableChartLayer` parametresi olarak geçir.
- Widget rect = `(left: leftAxisWidth, top: 0, right: 0, bottom: bottomAxisHeight)`.
- Pixel → data:
  - `xData = viewMinX + (dx - leftAxisWidth) / (chartWidth - leftAxisWidth) * (viewMaxX - viewMinX)`
  - `yData = viewMaxY - dy / (chartHeight - bottomAxisHeight) * (viewMaxY - viewMinY)`

## UX akışı

1. Grafik üstünde chip strip'ine "✎" ikonu eklenir → `DrawToolPalette`
   açılır (küçük popup / bottom sheet).
2. Kullanıcı "Trend" seçer → grafiğe döner, cursor mode değişir (top-left'te
   küçük "Trend çiziyorsun" pill).
3. Parmakla A noktasına dokun (100ms delay) → başlangıç noktası set.
4. Parmağı sürükle → canlı olarak B noktası takip eder, çizgi çizilir.
5. Parmak kalkar → çizim kaydedilir (DB insert), palette'e "seçim modu"na
   döner.
6. Var olan çizime tap → seçili (kalın border), popup: rengi değiştir / sil.
7. Long-press ile draggable? — Faz 10.1, MVP'ye dahil değil.

## Zoom / pan ile etkileşim

- **Draw mode aktifken**: pinch/pan devre dışı — kullanıcı çizim yapıyor,
  yanlışlıkla zoom olmasın.
- **Seçim modunda**: pinch/pan normal, çizimler grafikle beraber zoom olur
  (çünkü data koordinatlarında çiziliyor, viewMinX/Y değişince otomatik
  yeniden çizilir).

## Compare / log-scale uyumu

- **Compare mod aktifken**: çizimler ana varlığın normalize edilmiş Y
  domain'inde çizilir. Toggle edildiğinde koordinat sistemi değişir —
  çizimler görsel olarak "kayar". Kabul edilebilir (kullanıcı zaten mod
  değiştiriyor); alternatif çizimleri gizle.
- **Log-scale aktifken**: çizimler ham Y'de saklanıyor, `toY()` transform
  ile display Y'ye çevrilir. Yani DB'de değişmez, sadece render sırasında
  transform.

## Efor tahmini

| İş | Süre |
|---|---|
| DB migration + model + DAO | 3 saat |
| DrawableChartLayer widget (custom paint + gesture) | 6 saat |
| DrawToolPalette + tool state | 2 saat |
| Chart entegrasyonu (performance_screen'e ekle) | 2 saat |
| Compare/log uyumu + edge case'ler | 2 saat |
| Test (widget + integration) | 3 saat |
| Polish (renk picker, animasyon, "tümünü sil" confirm) | 2 saat |
| **Toplam** | **~20 saat / 3-4 gün** |

## Riskler

1. **fl_chart pixel<>data mapping** yaklaşık — kenarda 1-2px kayma normal.
   Bunu kabul et; TradingView-benzeri precision gerekmiyor.
2. **CustomPaint performansı** — 20+ çizim varsa render maliyeti artar.
   `RepaintBoundary` ile izole et.
3. **Sync (partner shared portfolio)** — annotations user_id bazlı, ortağın
   çizimleri görünmez. İleride "share annotation" özelliği eklenebilir.
4. **Zoom-lock**: draw mode'da pinch devre dışı → kullanıcı yanlış tool
   seçtiyse önce seçim moduna dönmesi gerek. Sağ üstte "İptal" X butonu
   şart.

## Sonraki adım

Bir sonraki seansta:
1. Bu dokümanı oku
2. `ChartAnnotation` model + DAO'yu yaz
3. DB migration'ı ekle (mevcut schema v6, yeni sürüm v7)
4. Boş `DrawableChartLayer` widget'ı ekle, önce sadece **mevcut çizimleri
   render** et (yeni çizim eklenmez, sadece read-only)
5. Gesture recognizer ekle, önce **trend** araç için
6. hline + fib
7. Palette + integration

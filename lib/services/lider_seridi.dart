// Düello arenasının lider şeridi — dönemin her günü (yılda her ay) kim
// öndeydi (kullanıcı seçimi 2026-10-04, "2 · Düello arenası", bayrak
// `yaris_duello_arena`).
//
// ## Veri nereden
// Sunucu günlük TWR yazmıyor: `leaderboard-snapshot` dönem SONUNU tutar,
// gün gün geçmişi değil. Ama sıralamanın kendisi (`secim_getirisi.dart`)
// dönemi zaten günlere bölüp her günün çarpanını hesaplıyor; şerit o
// döngünün ara toplamlarını ([SecimGetirisi.donemSerisi]) iki kişi için
// AYNI ölçüm anlarında kıyaslar. Yeni kaynak, yeni RPC, uydurma nokta yok:
// bir kişinin o gün ölçümü yoksa çubuk "bilinmiyor" çizilir.
//
// ## Neden servis katmanında
// Kıyas ve kovalama saf; widget yalnız çizer (CLAUDE.md katmanlama).
import 'dart:math' as math;

import 'secim_getirisi.dart';

/// Bir çubukta kim önde.
enum SeritLider { ben, rakip, berabere, bilinmiyor }

/// Şeridin bu dönemde kaç çubuğu olur: hafta ve ay gün gün, daha uzun
/// dönem ay ay (365 çubuk telefonda okunmaz; 12 kova bir yılı anlatır).
const int _ayKovaSayisi = 12;

/// Fark bu kadar puanın altındaysa o gün başa baş — arenanın "başa baş"
/// eşiğiyle aynı (`duelTied`, 0,05 puan).
const double basaBasEsigi = 0.05;

class LiderSeridi {
  const LiderSeridi({
    required this.cubuklar,
    required this.baslangic,
    required this.aylik,
    required this.donemGun,
  });

  /// Soldan sağa: en eski → bugün.
  final List<SeritLider> cubuklar;

  /// İlk çubuğun anı (alt etiket).
  final DateTime baslangic;

  /// Çubuklar ay ay mı (yıllık dönem) yoksa gün gün mü.
  final bool aylik;

  /// Hangi dönem için kuruldu — dönem değişince şerit yeniden dalgalanır.
  final int donemGun;

  /// Kaç kez yer değişti: ardışık KARARLI çubuklar (ben/rakip) arasında
  /// lider değişimi. Başa baş ve bilinmeyen günler değişim sayılmaz; araya
  /// girdiklerinde öncesi ve sonrası kıyaslanır.
  int get yerDegisimi {
    SeritLider? onceki;
    var n = 0;
    for (final c in cubuklar) {
      if (c != SeritLider.ben && c != SeritLider.rakip) continue;
      if (onceki != null && onceki != c) n++;
      onceki = c;
    }
    return n;
  }

  /// Hiç kararlı çubuk yoksa şerit bir şey anlatmaz.
  bool get bos => !cubuklar
      .any((c) => c == SeritLider.ben || c == SeritLider.rakip);
}

/// Sıralı seride `t` anına kadarki son nokta; seri `t`'den SONRA başlıyorsa
/// `null` (o gün ölçüm yok — [seriDegeriAninda]'nın aksine ilk noktaya
/// yaslanmaz, yoksa başlamamış bir kişi o gün "ölçülmüş" görünürdü).
double? _birikimAninda(List<({int an, double pct})> s, int t) {
  if (s.isEmpty || s.first.an > t) return null;
  var lo = 0, hi = s.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (s[mid].an <= t) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return s[lo].pct;
}

/// Saf: iki birikim serisinden lider şeridi. Serilerden biri yoksa ya da
/// hiçbir gün iki taraf birlikte ölçülmediyse `null` — şerit çizilmez.
///
/// [nowMs] iki serinin hesaplandığı AN olmalı (ölçüm ızgarası bugüne
/// hizalı, bkz. [olcumAnlari]).
LiderSeridi? liderSeridiKur({
  required List<({int an, double pct})>? ben,
  required List<({int an, double pct})>? rakip,
  required int gun,
  required int nowMs,
}) {
  if (ben == null || rakip == null || ben.isEmpty || rakip.isEmpty) {
    return null;
  }
  const gunMs = 24 * 60 * 60 * 1000;
  final anlar = olcumAnlari(nowMs - gun * gunMs, nowMs);
  if (anlar.length < 2) return null;
  final gunluk = <SeritLider>[];
  for (final t in anlar.skip(1)) {
    final a = _birikimAninda(ben, t);
    final b = _birikimAninda(rakip, t);
    if (a == null || b == null) {
      gunluk.add(SeritLider.bilinmiyor);
    } else if ((a - b).abs() < basaBasEsigi) {
      gunluk.add(SeritLider.berabere);
    } else {
      gunluk.add(a > b ? SeritLider.ben : SeritLider.rakip);
    }
  }
  final aylik = gun > 31;
  final List<SeritLider> cubuklar;
  if (!aylik) {
    cubuklar = gunluk;
  } else {
    // Eşit kovalar; kovanın lideri kova SONUNDAKİ durum (ay sonu gibi).
    final k = math.min(_ayKovaSayisi, gunluk.length);
    cubuklar = [
      for (var i = 0; i < k; i++) gunluk[((i + 1) * gunluk.length ~/ k) - 1],
    ];
  }
  final seritim = LiderSeridi(
    cubuklar: cubuklar,
    baslangic: DateTime.fromMillisecondsSinceEpoch(anlar[1]),
    aylik: aylik,
    donemGun: gun,
  );
  return seritim.bos ? null : seritim;
}

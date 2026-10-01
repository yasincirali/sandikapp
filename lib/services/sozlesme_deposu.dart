import 'dart:async';

import '../demo/demo_modu.dart';
import '../models/asset_type.dart';
import '../models/sozlesme.dart';
import 'crash_reporter.dart';
import 'mevduat_hesabi.dart';
import 'supabase_service.dart';

/// Sözleşmelerin bellekteki deposu — fiyat servisi mevduatı BURADAN fiyatlar.
///
/// ## Neden servis katmanında tekil
/// `PriceService` bir `MEVDUAT:<id>` sembolü gördüğünde dönemleri bilmek
/// zorunda; provider'a (Riverpod) erişimi yok ve olmamalı (fiyat kaynağı
/// sözleşmesi: sembolün nereden fiyatlanacağına tek yer karar verir).
/// Depo o yerin arka odasıdır: sözleşme provider'ı yüklediğini buraya yazar,
/// fiyat servisi okur, tanımadığı id'yi kendisi ister ([eksikleriYukle]).
///
/// ## Ortak görünümü
/// Ortağın mevduat lotu da `MEVDUAT:<onun sözleşmesi>` taşır. RLS ortağa
/// okuma izni verir (0088 `*_partner_read`); depo tanımadığı id'yi ilk
/// fiyat turunda çeker ve ortak görünümü aynı birim değeri hesaplar.
///
/// ## Kullanıcı değişimi
/// Kayıtlar sözleşme id'siyle anahtarlıdır; başka kullanıcının id'si
/// yalnızca RLS izin verdiyse buraya girebilir. Yine de çıkışta
/// [temizle] çağrılır (bkz. `sozlesme_provider`), eski oturumun kaydı
/// bellekte kalmasın.
class SozlesmeDeposu {
  SozlesmeDeposu._();
  static final SozlesmeDeposu instance = SozlesmeDeposu._();

  final Map<String, Sozlesme> _sozlesmeler = {};
  final Map<String, List<MevduatDonemi>> _donemler = {};

  /// Sunucuda bulunamayan id'ler — her turda yeniden sorulmasın.
  final Set<String> _bulunamayan = {};

  /// Uçuşan yükleme — aynı turda iki çağıran aynı isteği bekler.
  Future<void>? _ucusan;

  Sozlesme? sozlesme(String id) => _sozlesmeler[id.toLowerCase()];

  List<MevduatDonemi> donemler(String id) =>
      List.unmodifiable(_donemler[id.toLowerCase()] ?? const []);

  /// Provider'ın yüklediği ya da yeni yazdığı kayıtları depoya alır.
  ///
  /// [donemler] verilen sözleşmelerin dönemlerinin TAMAMI olmalıdır:
  /// sözleşme başına liste değiştirilir, birleştirilmez.
  void yaz(Iterable<Sozlesme> sozlesmeler, Iterable<MevduatDonemi> donemler) {
    for (final s in sozlesmeler) {
      final id = s.id.toLowerCase();
      _sozlesmeler[id] = s;
      _bulunamayan.remove(id);
      if (s.tur == SozlesmeTuru.mevduat) _donemler[id] = [];
    }
    for (final d in donemler) {
      (_donemler[d.sozlesmeId.toLowerCase()] ??= []).add(d);
    }
    for (final l in _donemler.values) {
      l.sort((a, b) => a.baslangic.compareTo(b.baslangic));
    }
  }

  /// Tek dönemi ekler (yenileme).
  void donemEkle(MevduatDonemi d) {
    final l = _donemler[d.sozlesmeId.toLowerCase()] ??= [];
    l
      ..removeWhere((x) => x.id == d.id)
      ..add(d)
      ..sort((a, b) => a.baslangic.compareTo(b.baslangic));
  }

  /// Depoda olmayan sözleşmeleri sunucudan çeker. Hata fırlatmaz.
  Future<void> eksikleriYukle(Iterable<String> idler) async {
    if (DemoModu.aktif) return;
    final onceki = _ucusan;
    if (onceki != null) await onceki;
    final eksik = {
      for (final i in idler)
        if (!_sozlesmeler.containsKey(i.toLowerCase()) &&
            !_bulunamayan.contains(i.toLowerCase()))
          i.toLowerCase(),
    }.toList();
    if (eksik.isEmpty) return;
    final is_ = _yukle(eksik);
    _ucusan = is_;
    try {
      await is_;
    } finally {
      if (identical(_ucusan, is_)) _ucusan = null;
    }
  }

  Future<void> _yukle(List<String> eksik) async {
    try {
      final s = await SupabaseService.instance.fetchSozlesmeler(eksik);
      final mevduatIdleri = [
        for (final x in s)
          if (x.tur == SozlesmeTuru.mevduat) x.id,
      ];
      final d =
          await SupabaseService.instance.fetchMevduatDonemleri(mevduatIdleri);
      yaz(s, d);
      final gelen = {for (final x in s) x.id.toLowerCase()};
      _bulunamayan.addAll(eksik.where((i) => !gelen.contains(i)));
    } catch (e, st) {
      // Fiyat turu durmasın: lot son yazılan fiyatında kalır.
      CrashReporter.report(e, st, reason: 'SozlesmeDeposu.yukle');
    }
  }

  /// `MEVDUAT:<id>` sembolünün [t] anındaki birim değeri; bilinmiyorsa
  /// `null` (uydurma yok — lot son bilinen fiyatında kalır).
  double? mevduatBirimDegeri(String sembol, DateTime t) {
    final id = mevduatSozlesmeId(sembol);
    if (id == null) return null;
    final d = _donemler[id];
    if (d == null || d.isEmpty) return null;
    return MevduatHesabi.birimDeger(d, t);
  }

  /// [bas] → [son] arası birim değer değişimi (%), SÖZLEŞMEDEN.
  ///
  /// Neden seriden değil (2026-10-01 emülatör testi): seri adımlı örneklenir
  /// (5Y haftalık) ve ilk noktası açılıştan günler sonra düşer — 5Y +%40,10
  /// yazarken pozisyon +%40,92'ydi; gün içi seri bugün açılan hesapta tek
  /// noktadan kaldığı için BUGÜN %0,00 kalıyordu; yenilemeden sonra açık
  /// sayfadaki gün içi taban eski dönemden geliyordu. Sözleşmenin tahakkuku
  /// kesin bilinir; yüzde doğrudan ondan hesaplanır.
  ///
  /// Pencere sözleşmeden önce başlıyorsa ilk dönemin başından ölçülür
  /// (pencere pozisyondan uzunsa yüzde pozisyonun ömrünün getirisidir).
  double? mevduatDegisimi(String sembol, DateTime bas, DateTime son) {
    final id = mevduatSozlesmeId(sembol);
    final d = id == null ? null : _donemler[id];
    if (d == null || d.isEmpty) return null;
    final ilk = d
        .map((x) => x.baslangic)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final b = MevduatHesabi.birimDeger(d, bas.isBefore(ilk) ? ilk : bas);
    final s = MevduatHesabi.birimDeger(d, son);
    if (b == null || s == null || b <= 0) return null;
    return (s / b - 1) * 100;
  }

  /// `MEVDUAT:<id>` sembolünün seri penceresi.
  List<(int, double)> mevduatSerisi(
    String sembol, {
    required DateTime bas,
    required DateTime son,
    required Duration adim,
  }) {
    final id = mevduatSozlesmeId(sembol);
    final d = id == null ? null : _donemler[id];
    if (d == null || d.isEmpty) return const [];
    return MevduatHesabi.seri(d, bas: bas, son: son, adim: adim);
  }

  void temizle() {
    _sozlesmeler.clear();
    _donemler.clear();
    _bulunamayan.clear();
  }
}

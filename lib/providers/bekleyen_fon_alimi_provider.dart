import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';
import '../services/bist_calendar.dart';
import '../services/bugun_service.dart' show BugunService;
import '../services/crash_reporter.dart';
import '../services/tefas_service.dart';
import '../utils/tr_format.dart' show dayKey;
import 'add_asset_form_provider.dart' show tutardanAdet;
import 'portfolio_provider.dart';

/// Fon alımında "fiyat yarın kesinleşir" (Ar-Ge 7 Kas 14:30 #1, ücretsiz).
///
/// ## Sorun
/// TEFAS fonları İLERİ fiyatlanır: bugün verilen alım emri bugünün akşamı
/// hesaplanan (TEFAS'ta BUGÜNÜN tarihini taşıyan) fiyattan gerçekleşir.
/// "10.000 TL'lik aldım" diyen kullanıcının adedi ise kayıt anında bilinen
/// (dünkü) fiyatla hesaplanıyor (`tutardanAdet`); ertesi gün bankadaki adetle
/// tutmuyor, kullanıcı elle düzeltiyordu.
///
/// ## Karar
/// - Kayıt bugünkü gibi kalır (adet = tutar ÷ bilinen fiyat). Şema
///   değişmez; "bekleyen" işaretini istemci tutar (bu cihazın
///   `shared_preferences`'ı, lot kimliğiyle). Başka cihazda yalnız etiket
///   görünmez, veri bozulmaz.
/// - Alım gününe ait TEFAS fiyatı gelince satırda TEK DOKUNUŞLUK öneri.
///   SESSİZ OTOMATİK DÜZELTME YOK: ekstreyle zaten eşlemiş kullanıcının
///   kaydını sormadan değiştirmek yanlış düzeltme riski taşır.
/// - Fiyat gelmeden öneri yok (uydurma sayı yasak). Eşleşme GÜN ile: alım
///   gününden başka bir günün fiyatı (dünkü ya da ertesi günün) öneri
///   üretmez.
/// - Bilinen sınır: kesim saatinden (çoğu fonda 13:30) sonra verilen emir
///   ertesi günün fiyatına gider; uygulama emrin saatini bilmez. Öneri
///   yine alım gününün fiyatını söyler, kullanıcı "Yok say" ile kapatır.
/// - Hafta sonu / resmî tatil alımı (2026-11-10, takvim artık istemcide —
///   `BistTakvimi`): o günün TEFAS fiyatı yoktur; emir sonraki BIST iş
///   gününün fiyatından gerçekleşir. İşaretin "alım günü" o iş gününe
///   kaydırılır ([fonFiyatGunu]); öneri o günün fiyatı gelince çıkar,
///   gelmeden yine yok. Kaydın kendi tarihi (lotun `addedDate`'i)
///   DEĞİŞMEZ — kullanıcının girdiği gün. Eskiden hafta sonu alımı hiç
///   işaretlenmiyordu: hangi iş gününe gideceği tatil takvimi olmadan
///   kesin bilinemezdi. Takvimin kapsamadığı yılda ([BistTakvimi.
///   sonKapsananYil] sonrası) bu hâlâ doğru; orada eski davranış sürer
///   (hafta sonu işaretlenmez, hafta içi o günle eşlenir).
@immutable
class BekleyenFonAlimi {
  const BekleyenFonAlimi({
    required this.lotId,
    required this.kod,
    required this.tutar,
    required this.alimGunu,
    required this.kayitAdet,
    required this.kayitFiyat,
    this.kayitFiyatGunu,
    this.kesinFiyat,
  });

  final String lotId;

  /// Fon kodu, `TEFAS:` öneki olmadan (ör. `AFT`).
  final String kod;

  /// Kullanıcının girdiği tutar — Güncelle'de değişmeyen şey.
  final double tutar;

  /// Fiyatın eşleneceği gün, yerel takvim günü: iş günü alımında kayıt
  /// günü, hafta sonu/tatil alımında sonraki BIST iş günü ([fonFiyatGunu],
  /// 2026-11-10). Ad eski (JSON `g`), anlam "alımın fiyat günü".
  final DateTime alimGunu;

  /// Kayıttaki adet ve birim fiyat: lot sonradan düzenlenirse (biri
  /// değişirse) işaret düşer — kullanıcı zaten elle düzeltmiş demektir.
  final double kayitAdet;
  final double kayitFiyat;

  /// Kayıt anındaki fiyatın TEFAS günü (bilinmiyorsa null).
  final DateTime? kayitFiyatGunu;

  /// Alım gününe ait TEFAS fiyatı; gelene kadar null.
  final double? kesinFiyat;

  BekleyenFonAlimi kesinlesti(double fiyat) => BekleyenFonAlimi(
        lotId: lotId,
        kod: kod,
        tutar: tutar,
        alimGunu: alimGunu,
        kayitAdet: kayitAdet,
        kayitFiyat: kayitFiyat,
        kayitFiyatGunu: kayitFiyatGunu,
        kesinFiyat: fiyat,
      );

  Map<String, dynamic> toJson() => {
        'l': lotId,
        'k': kod,
        't': tutar,
        'g': _gunMetni(alimGunu),
        'a': kayitAdet,
        'f': kayitFiyat,
        if (kayitFiyatGunu != null) 'fg': _gunMetni(kayitFiyatGunu!),
        if (kesinFiyat != null) 'kf': kesinFiyat,
      };

  /// Bozuk kayıt null döner (sessizce atlanır; işaret yalnız bir ipucu).
  static BekleyenFonAlimi? fromJson(Object? j) {
    if (j is! Map) return null;
    final lot = j['l'], kod = j['k'], gun = j['g'];
    final tutar = j['t'], adet = j['a'], fiyat = j['f'];
    if (lot is! String || kod is! String || gun is! String) return null;
    if (tutar is! num || adet is! num || fiyat is! num) return null;
    final alim = DateTime.tryParse(gun);
    if (alim == null) return null;
    final fg = j['fg'];
    final kf = j['kf'];
    return BekleyenFonAlimi(
      lotId: lot,
      kod: kod,
      tutar: tutar.toDouble(),
      alimGunu: alim,
      kayitAdet: adet.toDouble(),
      kayitFiyat: fiyat.toDouble(),
      kayitFiyatGunu: fg is String ? DateTime.tryParse(fg) : null,
      kesinFiyat: kf is num && kf > 0 ? kf.toDouble() : null,
    );
  }
}

String _gunMetni(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final g = d.day.toString().padLeft(2, '0');
  return '$y-$m-$g';
}

bool _ayniGun(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

bool _gundenSonra(DateTime a, DateTime gun) =>
    dayKey(a.toLocal()).isAfter(dayKey(gun.toLocal()));

/// Bu gün verilen fon alımı hangi günün TEFAS fiyatından gerçekleşir?
/// İş günüyse kendisi; hafta sonu ya da resmî tatilse sonraki BIST iş
/// günü (gün başı). Takvimin kapsamadığı yılda dinî bayram bilinmez: hafta
/// içi gün olduğu gibi döner (eski davranış), hafta sonu `null` — hedef
/// gün uydurulmaz, işaret kurulmaz.
///
/// Kesim saati burada YOK (bilinen sınır, yukarıda): iş günü kesimden
/// sonra verilen emir de o günle eşlenir.
DateTime? fonFiyatGunu(DateTime islem) {
  var gun = dayKey(islem.toLocal());
  final haftaSonu = gun.weekday >= DateTime.saturday;
  if (!BistTakvimi.yilKapsaniyor(gun.year)) return haftaSonu ? null : gun;
  for (var i = 0; i < 20; i++) {
    if (BugunService.islemGunuMu(gun)) {
      // Yıl sınırını geçtiyse (31 Ara → Ocak) o yıl da kapsanmalı.
      return BistTakvimi.yilKapsaniyor(gun.year) ? gun : null;
    }
    gun = DateTime(gun.year, gun.month, gun.day + 1);
  }
  return null;
}

/// Kayıtta işaret kurulsun mu? Yalnız fon + tutar kipi + işlem tarihi
/// bugün + fiyat günü belli ([fonFiyatGunu]; hafta sonu/tatilde sonraki iş
/// günü) + fiyatı kullanıcı yazmamış + bilinen fiyat o günün değil.
/// Fiyatı kullanıcı yazdıysa onu biliyordur; bilinen fiyat zaten o günün
/// fiyatıysa adet doğrudur.
bool fonAlimiIsaretlensinMi({
  required AssetType tur,
  required bool tutarModu,
  required bool fiyatGirildi,
  required DateTime islemTarihi,
  required DateTime simdi,
  required DateTime? bilinenFiyatGunu,
}) {
  if (tur != AssetType.fon || !tutarModu || fiyatGirildi) return false;
  if (!_ayniGun(islemTarihi, simdi)) return false;
  final hedef = fonFiyatGunu(simdi);
  if (hedef == null) return false;
  if (bilinenFiyatGunu != null && _ayniGun(bilinenFiyatGunu, hedef)) {
    return false;
  }
  return true;
}

/// Aday fiyat alım gününün fiyatı mı? Değilse null. Eşleşme takvim günüyle;
/// kayıtta kullanılan fiyatın günüyle aynı gün asla "yeni" sayılmaz.
double? alimGunuFiyati(
  BekleyenFonAlimi isaret, {
  required double? fiyat,
  required DateTime? tarih,
}) {
  if (fiyat == null || tarih == null) return null;
  if (!fiyat.isFinite || fiyat <= 0) return null;
  if (!_ayniGun(tarih, isaret.alimGunu)) return null;
  final eski = isaret.kayitFiyatGunu;
  if (eski != null && _ayniGun(eski, tarih)) return null;
  return fiyat;
}

/// TEFAS geçmiş serisinden (ms, fiyat) alım gününün fiyatı; yoksa null.
double? gecmistenAlimGunuFiyati(
    BekleyenFonAlimi isaret, List<(int, double)> noktalar) {
  for (final (ms, fiyat) in noktalar) {
    final r = alimGunuFiyati(isaret,
        fiyat: fiyat, tarih: DateTime.fromMillisecondsSinceEpoch(ms));
    if (r != null) return r;
  }
  return null;
}

/// Lot silindiyse ya da adedi/birim fiyatı değiştiyse işaret geçersiz.
bool fonAlimiIsaretiGecersiz(BekleyenFonAlimi isaret, Asset? lot) {
  if (lot == null || lot.isDeleted) return true;
  bool farkli(double a, double b) =>
      (a - b).abs() > 1e-9 * (a.abs() > 1 ? a.abs() : 1);
  return farkli(lot.quantity, isaret.kayitAdet) ||
      farkli(lot.purchasePrice, isaret.kayitFiyat);
}

/// Satırın göreceği durum.
sealed class FonAlimDurumu {
  const FonAlimDurumu(this.lotId);
  final String lotId;
}

/// Alım gününün fiyatı henüz yok: "fiyat yarın kesinleşir".
class FonAlimBekliyor extends FonAlimDurumu {
  const FonAlimBekliyor(super.lotId);
}

/// Fiyat geldi: adet = tutar ÷ yeni fiyat, birim maliyet yeni fiyat.
class FonAlimOnerisi extends FonAlimDurumu {
  const FonAlimOnerisi(super.lotId,
      {required this.adet, required this.birimFiyat});
  final double adet;
  final double birimFiyat;
}

/// İşaretten durum (saf). Yeni adet kayıttakiyle aynıysa (fiyat değişmemiş)
/// öneri yok: `null`, işaret düşürülür.
FonAlimDurumu? fonAlimDurumu(BekleyenFonAlimi isaret) {
  final f = isaret.kesinFiyat;
  if (f == null) return FonAlimBekliyor(isaret.lotId);
  final adet = tutardanAdet(tutar: isaret.tutar, birimFiyat: f);
  if (adet == null) return FonAlimBekliyor(isaret.lotId);
  if ((adet - isaret.kayitAdet).abs() <= 1e-9 * isaret.kayitAdet.abs()) {
    return null;
  }
  return FonAlimOnerisi(isaret.lotId, adet: adet, birimFiyat: f);
}

/// Bekleyen fon alımları (lot kimliği → işaret), `shared_preferences`'ta.
///
/// Portföy değiştikçe ([portfolioProvider] dinlenir) eşitlenir: silinen ya
/// da düzenlenen lotun işareti düşer; TEFAS önbelleğinde alım gününün
/// fiyatı varsa işarete yazılır. Önbellek daha yeni bir günü gösteriyorsa
/// (kullanıcı o akşam açmadı) geçmiş seriden o günün fiyatı aranır; seri
/// geldi ama gün yoksa (tatil) işaret düşer — sonsuza dek "bekliyor"
/// yazmasın.
class BekleyenFonAlimlariNotifier
    extends Notifier<Map<String, BekleyenFonAlimi>> {
  static const anahtar = 'bekleyen_fon_alimlari_v1';

  final Set<String> _gecmisAraniyor = {};
  bool _yuklendi = false;

  @override
  Map<String, BekleyenFonAlimi> build() {
    ref.listen<AsyncValue<PortfolioState>>(
      portfolioProvider,
      (_, sonraki) => _esitle(sonraki.valueOrNull),
    );
    _yukleme = _yukle();
    CrashReporter.arkaPlan(_yukleme, reason: 'bekleyen_fon_alimi._yukle');
    return const {};
  }

  /// Disk okuması; yazım bunu bekler — yükleme bitmeden gelen ilk işaret
  /// (kayıt) diskteki eski işaretleri ezmesin.
  late Future<void> _yukleme;

  Future<void> _yukle() async {
    final prefs = await SharedPreferences.getInstance();
    final ham = prefs.getString(anahtar);
    final okunan = <String, BekleyenFonAlimi>{};
    if (ham != null) {
      try {
        final liste = jsonDecode(ham);
        if (liste is List) {
          for (final j in liste) {
            final i = BekleyenFonAlimi.fromJson(j);
            if (i != null) okunan[i.lotId] = i;
          }
        }
      } on FormatException {
        // Bozuk değer: işaretler yalnız ipucu, boş başlanır.
      }
    }
    _yuklendi = true;
    // Yükleme sürerken eklenen işaret (kayıt) korunur.
    state = {...okunan, ...state};
    _esitle(ref.read(portfolioProvider).valueOrNull);
  }

  Future<void> _kaydet() async {
    await _yukleme;
    final prefs = await SharedPreferences.getInstance();
    if (state.isEmpty) {
      await prefs.remove(anahtar);
    } else {
      await prefs.setString(
          anahtar, jsonEncode([for (final i in state.values) i.toJson()]));
    }
  }

  void _yaz(Map<String, BekleyenFonAlimi> yeni) {
    state = yeni;
    CrashReporter.arkaPlan(_kaydet(), reason: 'bekleyen_fon_alimi._kaydet');
  }

  /// Kayıttan hemen sonra (ekleme formu).
  void ekle(BekleyenFonAlimi isaret) =>
      _yaz({...state, isaret.lotId: isaret});

  /// "Yok say" ya da Güncelle sonrası.
  void kaldir(String lotId) {
    if (!state.containsKey(lotId)) return;
    _yaz({...state}..remove(lotId));
  }

  /// Güncelle: mevcut lot güncelleme yolu (`updateAsset`); adet = tutar ÷
  /// yeni fiyat, birim maliyet yeni fiyat, toplam tutar aynı. Hata
  /// çağırana gider (ekran `showAppError`), işaret o zaman kalır.
  Future<void> uygula(String lotId) async {
    final isaret = state[lotId];
    if (isaret == null) return;
    final durum = fonAlimDurumu(isaret);
    if (durum is! FonAlimOnerisi) return;
    final lot = _lot(ref.read(portfolioProvider).valueOrNull, lotId);
    if (fonAlimiIsaretiGecersiz(isaret, lot)) {
      kaldir(lotId);
      return;
    }
    // İşaret ÖNCE düşer: güncellenen lotun adedi değişince eşitleme onu
    // zaten "düzenlendi" sayardı; hata olursa geri konur.
    kaldir(lotId);
    lot!
      ..quantity = durum.adet
      ..purchasePrice = durum.birimFiyat;
    try {
      await ref.read(portfolioProvider.notifier).updateAsset(lot);
    } catch (_) {
      lot
        ..quantity = isaret.kayitAdet
        ..purchasePrice = isaret.kayitFiyat;
      ekle(isaret);
      rethrow;
    }
  }

  static Asset? _lot(PortfolioState? s, String id) {
    if (s == null) return null;
    for (final a in s.assets) {
      if (a.id == id) return a;
    }
    return null;
  }

  void _esitle(PortfolioState? s) {
    if (!_yuklendi || s == null || state.isEmpty) return;
    var yeni = state;
    var degisti = false;
    for (final isaret in state.values) {
      if (fonAlimiIsaretiGecersiz(isaret, _lot(s, isaret.lotId))) {
        yeni = {...yeni}..remove(isaret.lotId);
        degisti = true;
        continue;
      }
      if (isaret.kesinFiyat != null) continue;
      final onbellek = TefasService.instance.tarihliFiyat(isaret.kod);
      final f = alimGunuFiyati(isaret,
          fiyat: onbellek?.fiyat, tarih: onbellek?.tarih);
      if (f != null) {
        yeni = {...yeni, isaret.lotId: isaret.kesinlesti(f)};
        degisti = true;
      } else if (onbellek != null &&
          _gundenSonra(onbellek.tarih, isaret.alimGunu)) {
        CrashReporter.arkaPlan(_gecmistenAra(isaret),
            reason: 'bekleyen_fon_alimi._gecmistenAra');
      }
    }
    // Fiyat değişmemişse (aynı adet) öneri yok, işaret düşer.
    for (final isaret in yeni.values.toList()) {
      if (fonAlimDurumu(isaret) == null) {
        yeni = {...yeni}..remove(isaret.lotId);
        degisti = true;
      }
    }
    if (degisti) _yaz(yeni);
  }

  Future<void> _gecmistenAra(BekleyenFonAlimi isaret) async {
    if (!_gecmisAraniyor.add(isaret.lotId)) return;
    try {
      final noktalar =
          await TefasService.instance.fetchHistory(isaret.kod, periyod: 1);
      // Ağ hatası/boş yanıt: bir sonraki eşitlemede yeniden denenir.
      if (noktalar.isEmpty) return;
      final guncel = state[isaret.lotId];
      if (guncel == null || guncel.kesinFiyat != null) return;
      final f = gecmistenAlimGunuFiyati(guncel, noktalar);
      if (f != null) {
        final k = guncel.kesinlesti(f);
        _yaz(fonAlimDurumu(k) == null
            ? ({...state}..remove(k.lotId))
            : {...state, k.lotId: k});
      } else if (noktalar.any((n) => _gundenSonra(
          DateTime.fromMillisecondsSinceEpoch(n.$1), guncel.alimGunu))) {
        // Seri alım gününü geçti ama o gün yok (tatil): uydurmak yerine düş.
        kaldir(guncel.lotId);
      }
    } finally {
      _gecmisAraniyor.remove(isaret.lotId);
    }
  }
}

final bekleyenFonAlimlariProvider = NotifierProvider<
    BekleyenFonAlimlariNotifier,
    Map<String, BekleyenFonAlimi>>(BekleyenFonAlimlariNotifier.new);

/// Lot kimliği → durum. Satır bunu okur; hesap burada, `build()`'de değil.
final fonAlimDurumlariProvider = Provider<Map<String, FonAlimDurumu>>((ref) {
  final isaretler = ref.watch(bekleyenFonAlimlariProvider);
  return {
    for (final i in isaretler.values)
      if (fonAlimDurumu(i) case final d?) i.lotId: d,
  };
});

/// Pozisyonun lotlarından ilk bekleyen durum (bir pozisyonda aynı gün iki
/// tutar alımı nadir; ilki gösterilir, Güncelle'den sonra sıradaki çıkar).
FonAlimDurumu? pozisyonFonAlimDurumu(
    Map<String, FonAlimDurumu> durumlar, Iterable<String> lotIdleri) {
  for (final id in lotIdleri) {
    final d = durumlar[id];
    if (d != null) return d;
  }
  return null;
}

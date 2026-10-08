import 'dart:math' as math;
import '../utils/tr_format.dart';

import '../models/sozlesme.dart';

/// Mevduatın BİRİM DEĞER hesabı — sözleşmeden, saf fonksiyonlarla.
///
/// ## Neden birim değer (2026-09-30)
/// Mevduat fon gibi fiyatlanır (`AssetType.fiyatlamaTuru`): lot miktarı
/// "pay", fiyat pay başına TL. İlk dönem 1,0 ile başlar; net faiz vadeli
/// hesapta vade sonunda, günlük faizli hesapta her gün sonunda eklenir. Ek para yatırma o günün birim değerinden yeni bir alım
/// lotu, çekim satım lotudur — fonun NAV'ı gibi. Böylece toplam, kâr/zarar,
/// tarihçe ve ortak görünümü hiçbir "mevduat hariç" dalı olmadan çalışır
/// (0058'de silinen ilk sürümün bakım yükü tam olarak bu dallardı).
///
/// ## Kurallar
///   · **Vadeli dönem** basit faizle hesaplanır, `anapara × net × gün / 365`,
///     ve faiz VADE SONUNDA anaparaya eklenir; yenilenen dönem bu tutardan
///     başlar (bileşik zincir). Vade içinde değer anaparada DÜZ kalır.
///
///     Neden düz (kullanıcı kararı, 2026-10-02): *"Vadelide kâr anlık kazanç
///     şeklinde değil, vade sonunda yansıtılmalı."* Banka faizi vade sonunda
///     öder; vadeyi bozan faiz almaz. Eskiden değer her gün tahakkukla
///     artıyordu: portföy kâr/zarar ve "Bugün" henüz ele geçmemiş faizi
///     kazanç gibi gösteriyor, erken "Çektim" faiz ödenmiş gibi satıyordu.
///     Vade içinde faiz oranı değişirse (`mevduatFaizGuncelle`) dönem satırı
///     güncellenir ve vade sonundaki kazanç SON girilen orana göre çıkar.
///
///     İstisna: dönem vadesinden ÖNCE bir sonraki dönemle kapanmışsa (eski
///     sürümlerde erken yenileme / oran değişikliği yeni dönem açıyordu),
///     o güne kadarki faiz geçiş anında eklenir — geçmiş kayıtların değeri
///     değişmesin.
///   · **Vadesiz / günlük faizli** dönem günlük bileşiktir: bu hesaplar
///     faizi her gün öder. Faiz GÜN SONUNDA eklenir; gün içinde değer düz
///     kalır, gece yarısı o günün net faizi kadar artar.
///
///     Neden gün sonu (kullanıcı kararı, 2026-10-02): *"Günlük faizde de gün
///     sonunda hak ettiğimiz kazancı görmeliyiz; gün içinde anlık kârımızı
///     görmemeliyiz."* Eskiden saniye saniye tahakkuk ediyordu: 18:20'de
///     açılan ₺100.000'lik %40 hesap açılır açılmaz ~₺70 kâr gösteriyordu.
///   · **Net = brüt × (1 − stopaj)**. Stopaj dönem satırında saklıdır; oran
///     kararla değişince eski dönem geriye dönük değişmez.
///   · **Uydurma yok** (fiyat kaynağı sözleşmesi madde 3): son dönemin
///     vadesi dolup yeni dönem girilmediyse değer DÜZ kalır. Bankanın
///     yenileme faizini "aynıdır" diye varsaymayız.
abstract final class MevduatHesabi {
  /// Hızlı vade çipleri (gün). 32 gün Türkiye'de en yaygın vadedir.
  static const hizliVadeler = [32, 92, 181, 365];

  /// Gün cinsinden kesirli süre — gün içi seride eğri kademesiz olsun.
  static double _gun(DateTime a, DateTime b) =>
      b.difference(a).inSeconds / Duration.secondsPerDay;

  /// [a] gününden [b] gününe kaç GÜN SONU geçti (takvim günü farkı, saat
  /// yok sayılır). UTC gün farkı: yaz saati geçişinde 23/25 saatlik gün
  /// `inDays`'i kaydırmasın.
  static int _tamGun(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays;

  /// Net yıllık oran (0,35 = %35).
  static double netOran(MevduatDonemi d) =>
      d.yillikFaiz / 100 * (1 - d.stopaj / 100);

  /// Tek dönemin başından [t]'ye kadar büyüme çarpanı (≥ 1).
  static double _donemCarpani(MevduatDonemi d, double gun) {
    if (gun <= 0) return 1;
    final n = netOran(d);
    if (d.vadesiz) return math.pow(1 + n / 365, gun).toDouble();
    return 1 + n * gun / 365;
  }

  /// [t] anındaki birim değer; sözleşme henüz başlamadıysa `null`.
  ///
  /// [donemler] sıralı olmak zorunda değildir.
  static double? birimDeger(List<MevduatDonemi> donemler, DateTime t) {
    if (donemler.isEmpty) return null;
    final ds = [...donemler]..sort((a, b) => a.baslangic.compareTo(b.baslangic));
    if (t.isBefore(ds.first.baslangic)) return null;
    var b = 1.0;
    for (var i = 0; i < ds.length; i++) {
      final d = ds[i];
      // Önceki dönemin bitişiyle bunun başı arasında boşluk varsa (vade
      // doldu, kullanıcı birkaç gün sonra yeniledi) değer düz kalır.
      if (t.isBefore(d.baslangic)) return b;
      final sonraki = i + 1 < ds.length ? ds[i + 1].baslangic : null;
      // Dönemin fiilî sonu: vade ya da (erken yenileme/oran değişikliği)
      // bir sonraki dönemin başı — hangisi önceyse.
      DateTime? bitis = d.vadeSonu;
      if (sonraki != null && (bitis == null || sonraki.isBefore(bitis))) {
        bitis = sonraki;
      }
      if (bitis == null || t.isBefore(bitis)) {
        // Vadeli dönemde faiz vade sonunda eklenir; o güne kadar düz.
        if (!d.vadesiz) return b;
        // Günlük faizli dönemde faiz GÜN SONUNDA eklenir: yalnızca biten
        // günler sayılır, gün içinde değer düz.
        return b * _donemCarpani(d, _tamGun(d.baslangic, t).toDouble());
      }
      b *= _donemCarpani(
          d,
          d.vadesiz
              ? _tamGun(d.baslangic, bitis).toDouble()
              : _gun(d.baslangic, bitis));
    }
    return b;
  }

  /// [bas]–[son] aralığında [adim] aralıklı birim değer serisi (epoch ms).
  ///
  /// Sözleşme başlamadan önceki noktalar seriye GİRMEZ (değer yok, sıfır
  /// değil). Son nokta her zaman [son]'dur — grafiğin "ŞİMDİ" ucu.
  static List<(int, double)> seri(
    List<MevduatDonemi> donemler, {
    required DateTime bas,
    required DateTime son,
    required Duration adim,
  }) {
    final out = <(int, double)>[];
    if (donemler.isEmpty || !son.isAfter(bas) || adim <= Duration.zero) {
      return out;
    }
    // Aşırı sık adımda nokta sayısını sınırla: 5 yıllık 5 dk'lık seri
    // yarım milyon nokta olurdu.
    var a = adim;
    final toplam = son.difference(bas);
    if (toplam.inSeconds / a.inSeconds > 2000) {
      a = Duration(seconds: (toplam.inSeconds / 2000).ceil());
    }
    for (var t = bas; t.isBefore(son); t = t.add(a)) {
      final v = birimDeger(donemler, t);
      if (v != null) out.add((t.millisecondsSinceEpoch, v));
    }
    final v = birimDeger(donemler, son);
    if (v != null) out.add((son.millisecondsSinceEpoch, v));
    return out;
  }

  /// Son (en yeni) dönem.
  static MevduatDonemi? sonDonem(List<MevduatDonemi> donemler) {
    if (donemler.isEmpty) return null;
    return donemler.reduce((a, b) => a.baslangic.isAfter(b.baslangic) ? a : b);
  }

  /// Dönem numarası (1'den) — son dönem kaçıncı.
  static int donemSayisi(List<MevduatDonemi> donemler) => donemler.length;

  /// Son dönemin vadesi doldu mu (ve yenilenmedi mi)?
  static bool vadesiDoldu(List<MevduatDonemi> donemler, DateTime simdi) {
    final d = sonDonem(donemler);
    final v = d?.vadeSonu;
    return v != null && !simdi.isBefore(v);
  }

  /// Vadeye kalan gün (tam gün, bugün hariç); vadesiz ya da doluysa `null`.
  static int? vadeyeKalanGun(List<MevduatDonemi> donemler, DateTime simdi) {
    final v = sonDonem(donemler)?.vadeSonu;
    if (v == null) return null;
    final bugun = dayKey(simdi);
    final kalan = v.difference(bugun).inDays;
    return kalan > 0 ? kalan : null;
  }

  /// Son dönemin ilerleme oranı (0–1); vadesizde `null`.
  static double? donemIlerlemesi(List<MevduatDonemi> donemler, DateTime simdi) {
    final d = sonDonem(donemler);
    final v = d?.vadeSonu;
    if (d == null || v == null) return null;
    final top = _gun(d.baslangic, v);
    if (top <= 0) return 1;
    return (_gun(d.baslangic, simdi) / top).clamp(0.0, 1.0);
  }

  /// Son vadeli dönemin VADE SONUNDA eklenecek net faizi (TL), [pay] için.
  ///
  /// Vadesizde ya da dönem başlamadıysa `null`. Vade içinde değer düz
  /// kaldığı için kart ve portföy paneli kazancı bu "beklenen" tutarla
  /// gösterir; vade gelince aynı tutar değere eklenir.
  static double? vadeSonuNetFaizi(List<MevduatDonemi> donemler, double pay) {
    final d = sonDonem(donemler);
    final v = d?.vadeSonu;
    if (d == null || v == null) return null;
    final bas = birimDeger(donemler, d.baslangic);
    final son = birimDeger(donemler, v);
    if (bas == null || son == null) return null;
    return pay * (son - bas);
  }

  /// Portföy panelindeki vade şeridinin verisi — son dönemin özeti.
  ///
  /// Vadeli: başlangıç, vade, ilerleme (0–1), kalan gün, vade sonunda
  /// eklenecek net faiz. Vadesiz: günlük net faiz ([pay] × bugünkü birim
  /// değer üzerinden). Dönem yoksa `null`.
  static ({
    DateTime baslangic,
    DateTime? vade,
    double? ilerleme,
    int? kalanGun,
    bool doldu,
    double? vadeSonuNet,
    double? gunlukNet,
    double yillikFaiz,
  })? ozet(List<MevduatDonemi> donemler, double pay, DateTime simdi) {
    final d = sonDonem(donemler);
    if (d == null) return null;
    final bugun = birimDeger(donemler, simdi);
    return (
      baslangic: d.baslangic,
      vade: d.vadeSonu,
      ilerleme: donemIlerlemesi(donemler, simdi),
      kalanGun: vadeyeKalanGun(donemler, simdi),
      doldu: vadesiDoldu(donemler, simdi),
      vadeSonuNet: vadeSonuNetFaizi(donemler, pay),
      gunlukNet: d.vadesiz && bugun != null
          ? pay * bugun * netOran(d) / 365
          : null,
      yillikFaiz: d.yillikFaiz,
    );
  }

  /// Son dönemde kazanılan net faiz (TL) — kartın "Bu dönem net" satırı.
  ///
  /// [akislar] mevduatın pay hareketleridir: `(tarih, pay)`, alış pozitif,
  /// çekim negatif.
  ///
  /// ## Neden pay × (bugün − dönem başı) değil (2026-10-01)
  /// Eski hesap bugünkü TOPLAM payı dönem başından beri faiz almış sayıyordu.
  /// Dönem içinde para eklenince (portföydeki "+" ile) yeni para dönem
  /// başından beri işlemiş gibi görünüyordu: ₺100.000 ile açılan %45'lik
  /// 32 günlük mevduata 16. gün ₺100.000 eklenince vade günü bu dönem net
  /// ₺4.856 iken ₺6.457 yazıyordu. Her hareket kendi gününden itibaren sayılır; dönem
  /// başından önceki hareketler dönem başından.
  static double donemKazanci(
    List<MevduatDonemi> donemler,
    Iterable<(DateTime, double)> akislar,
    DateTime simdi,
  ) {
    final son = sonDonem(donemler);
    if (son == null) return 0;
    final bugun = birimDeger(donemler, simdi);
    if (bugun == null) return 0;
    final donemBasi = birimDeger(donemler, son.baslangic) ?? 1;
    var toplam = 0.0;
    for (final (tarih, pay) in akislar) {
      if (tarih.isAfter(simdi)) continue;
      final giris = tarih.isAfter(son.baslangic)
          ? (birimDeger(donemler, tarih) ?? donemBasi)
          : donemBasi;
      toplam += pay * (bugun - giris);
    }
    return toplam;
  }

  /// [anapara] için bir vadeli dönemin NET faiz tutarı (TL).
  static double donemNetFaizi({
    required double anapara,
    required double yillikFaiz,
    required double stopaj,
    required int gun,
  }) =>
      anapara * yillikFaiz / 100 * (1 - stopaj / 100) * gun / 365;

  /// Vadesiz hesapta [anapara]'nın bir günlük net faizi (TL).
  static double gunlukNetFaiz({
    required double anapara,
    required double yillikFaiz,
    required double stopaj,
  }) =>
      anapara * yillikFaiz / 100 * (1 - stopaj / 100) / 365;
}

/// Mevduat stopaj oranları — TARİHLİ tablo (açılış/yenileme tarihine göre).
///
/// ## Neden tablo, neden öneri
/// Oranlar Cumhurbaşkanı kararıyla sık değişiyor; dönem açıldığı günkü
/// oran o dönem boyunca geçerlidir. Tablo en yeni karardan geriye aranır.
/// Değer formda ÖNERİDİR, kullanıcı değiştirebilir: bankalar kararın geçiş
/// hükümlerini farklı yorumlayabiliyor ve eski dönemler için elimizde
/// doğrulanmış tarihçe yok.
///
/// Kaynaklar (TL mevduat; vadesiz/ihbarlı hesaplar "6 aya kadar" grubunda):
///   · 10041 sayılı CK (RG 2025-07-09): 6 aya kadar %17,5; 1 yıla kadar
///     %15; 1 yıldan uzun %10.
///   · 9487 sayılı CK (2025-02-01'den açılan/yenilenen): %15 / %12 / %10.
///
/// ## Neden geçmiş satır (stopaj incelemesi, 2026-10-01)
/// Tablo yalnızca 2025-07-09 satırını taşıyordu ve daha eski açılışlar
/// `orElse` ile o satıra düşüyordu: 2025 Mart'ında açılmış 2 yıllık bir
/// mevduata doğru öneri %10, 1 yıllığa %12 iken uygulama %15 öneriyordu
/// (₺100.000, %48, 365 gün: net ₺42.240 yerine ₺40.800). 2025-02-01
/// öncesi oranlar (%10/%7,5/%5, daha önce %7,5/%5/%2,5) vadesiz hesap
/// için ayrı bir oran taşıdığından eklenmedi; o tarihlerde öneri en eski
/// satırdır ve form "bankan farklı uyguluyorsa düzelt" der.
///
/// Yeni karar çıkınca listenin BAŞINA satır eklenir (tarih + üç oran).
final List<({DateTime yururluk, double altiAy, double birYil, double uzun})>
    mevduatStopajTablosu = [
  (yururluk: DateTime(2025, 7, 9), altiAy: 17.5, birYil: 15, uzun: 10),
  (yururluk: DateTime(2025, 2, 1), altiAy: 15, birYil: 12, uzun: 10),
];

/// [baslangic]'ta açılan, [gun] günlük (vadesizde `null`) dönem için
/// önerilen stopaj yüzdesi.
///
/// Vade sınırları bankacılık teamülü: 6 ay ≈ 184 güne kadar (181/182/184
/// günlük ürünler 6 aylık sayılır), 1 yıl ≈ 366 güne kadar.
double onerilenStopaj(DateTime baslangic, int? gun) {
  // En yeni karar başta; açılış gününde yürürlükte olan ilk satır. Tablo
  // öncesi bir tarih için en eski satır önerilir (kullanıcı düzeltebilir).
  final satir = mevduatStopajTablosu.firstWhere(
    (s) => !baslangic.isBefore(s.yururluk),
    orElse: () => mevduatStopajTablosu.last,
  );
  if (gun == null || gun <= 184) return satir.altiAy;
  if (gun <= 366) return satir.birYil;
  return satir.uzun;
}

/// Hızlı Al/Sat'ta mevduat işleminin kaydedilecek payı ve birim fiyatı.
///
/// ## Neden tutarla (kullanıcı bildirimi, 2026-10-08)
/// *"Vadeli mevduatta lot değil TL değeri alıyor olmalı. Satış değeri de
/// direkt ne yazıldıysa o; stopaj zaten kesilip kâr olarak üstüne ekleniyor."*
/// Diyalog mevduatta da hisse gibi "Miktar" (pay) soruyordu: birim değer
/// 1,05 iken ₺10.000 çekmek isteyen 10.000 yazıyor, satış 10.000 × 1,05 =
/// ₺10.500 kaydediliyordu — kazanılmış net faiz bir kez daha "kâr payı"
/// olarak tutara biniyordu. Alışta da birim fiyat alanı birim değerle dolu
/// geliyor, yazılan tutar paya bölünmeden kaydediliyordu.
///
/// Kural: kullanıcı TL TUTARI yazar; pay = tutar / birim, fiyat = birim.
/// Böylece alışın maliyeti ve satışın değeri tam yazılan tutardır; faiz
/// birim değerde (sözleşmeden) kalır, iki kez sayılmaz.
///
/// Satışta "Hepsi": tutar eldeki bakiyeye kuruş payıyla eşitse pay eldekinin
/// TAMAMI olur — 1e-9'luk pay artığı pozisyonu açık bırakmasın. Bakiyeyi
/// aşan satış ya da geçersiz giriş `null` döner (çağıran hata gösterir).
({double pay, double birim})? mevduatTutarIslemi({
  required double tutar,
  required double birim,
  required double eldekiPay,
  required bool satis,
}) {
  if (!(tutar > 0) || !(birim > 0) || !tutar.isFinite) return null;
  if (!satis) return (pay: tutar / birim, birim: birim);
  final bakiye = eldekiPay * birim;
  if ((tutar - bakiye).abs() < 0.01) return (pay: eldekiPay, birim: birim);
  if (tutar > bakiye) return null;
  return (pay: tutar / birim, birim: birim);
}

/// Yahoo `range` → seri penceresinin süresi (mevduat sentetik serisi için).
Duration aralikSuresi(String range) => switch (range) {
      '1d' => const Duration(days: 1),
      '5d' => const Duration(days: 5),
      '1mo' => const Duration(days: 31),
      '3mo' => const Duration(days: 92),
      '6mo' => const Duration(days: 183),
      '1y' => const Duration(days: 366),
      '2y' => const Duration(days: 731),
      '3y' => const Duration(days: 1096),
      '5y' => const Duration(days: 1827),
      _ => const Duration(days: 3653),
    };

/// Yahoo `interval` → adım.
Duration aralikAdimi(String interval) {
  final m = RegExp(r'^(\d+)(m|h|d|wk|mo)$').firstMatch(interval.trim());
  if (m == null) return const Duration(days: 1);
  final n = int.parse(m.group(1)!);
  return switch (m.group(2)) {
    'm' => Duration(minutes: n),
    'h' => Duration(hours: n),
    'd' => Duration(days: n),
    'wk' => Duration(days: 7 * n),
    _ => Duration(days: 30 * n),
  };
}

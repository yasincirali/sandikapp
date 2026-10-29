import 'dart:math' as math;

import 'package:intl/intl.dart' show DateFormat;

import '../../config/magaza.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n.dart' show donemEtiketi;

/// Tam ekran grafiğin görsel paylaşımı: metin ve dönem (Ar-Ge 25 Eki §2,
/// rapor 13:15 §1).
///
/// ## Neden saf fonksiyon
/// Metin iki kurala bağlı ve ikisi de testle kilitli
/// (`tam_ekran_grafik_paylas_test`): (1) tavsiye dili yok — "sandık ile
/// çizildi" der, "sinyal / hedef / al / sat" demez; çizimi yapan
/// kullanıcıdır; (2) mağaza bağlantısı var olan paylaşım kartlarıyla aynı
/// kapıdan ([Magaza.indirBaglantisi]), yalnız kanal etiketi ayrı ki hangi
/// paylaşımın kurulum getirdiği ölçülsün.
///
/// ## Kişisel veri yok
/// Metin yalnız sembol ve dönem taşır: tutar, miktar, maliyet yok.
String grafikPaylasimMetni(
  AppLocalizations l, {
  required String ad,
  required String donem,
}) =>
    '${l.tegPaylasimMetni(ad, donem)}\n'
    '${Magaza.indirBaglantisi(kaynak: 'grafik_paylas', kampanya: 'grafik')}';

/// Görseldeki kısa bağlantı: indirme kapısının host + yolu, şemasız ve
/// UTM'siz ("yasincirali.github.io/sandikapp/indir") — görselde okunup
/// elle yazılabilsin (yasin 2026-10-29, marka şeridi). Kanal ölçümü
/// paylaşım METNİNDEKİ tam bağlantıda kalır.
String grafikPaylasimKisaBaglanti() {
  final u = Uri.parse(Magaza.indirKapisi);
  final yol = u.path.endsWith('/')
      ? u.path.substring(0, u.path.length - 1)
      : u.path;
  return '${u.host}$yol';
}

/// Ekranda görünen pencerenin dönem kimliği ('GÜNLÜK', '1H', '1A', '3A',
/// '6A', '1Y', '5Y'); gösterim [donemEtiketi] üzerinden.
///
/// Tam ekranda dönem seçici yok — kullanıcı yakınlaştırıp kaydırarak
/// pencereyi kendisi seçer. Paylaşımdaki "6A" bu pencerenin uzunluğuna EN
/// YAKIN uygulama dönemidir (log ölçekte: 4 ay "3A"ya, 5 ay "6A"ya yakın);
/// yeni bir dönem dili icat edilmez, Performans ekranının adları kullanılır.
String gorunurDonemKimligi(int basMs, int sonMs) {
  final gun = (sonMs - basMs).abs() / Duration.millisecondsPerDay;
  if (gun < 2) return 'GÜNLÜK';
  const donemler = <(String, double)>[
    ('1H', 7),
    ('1A', 30),
    ('3A', 90),
    ('6A', 180),
    ('1Y', 365),
    ('5Y', 1825),
  ];
  var enIyi = donemler.first;
  var fark = double.infinity;
  for (final d in donemler) {
    final f = (math.log(gun) - math.log(d.$2)).abs();
    if (f < fark) {
      fark = f;
      enIyi = d;
    }
  }
  return enIyi.$1;
}

/// Kimliği ekran diline çevirir (TR "6 ay", EN "6M").
String gorunurDonemEtiketi(AppLocalizations l, int basMs, int sonMs) =>
    donemEtiketi(l, gorunurDonemKimligi(basMs, sonMs));

/// Paylaşımda okunan pencere: görünen İLK ve SON mumun tarihi
/// ("22 Ağu – 29 Eki 2026"; gün içi aralıkta saatle).
///
/// ## Neden yaklaşık dönem değil (uçtan uca test 2026-10-29)
/// Görsel ve metin "THYAO · 3 ay" diyordu: [gorunurDonemKimligi] pencereyi
/// EN YAKIN uygulama dönemine yuvarlar, mum aralığını hiç söylemez. Günlük
/// mumlarla ~4 aylık pencere "3 ay", dört haftalık pencere "1 ay" okunuyor;
/// alan kişi neye baktığını bilemiyordu. Tarih aralığı ölçüm değil olgudur,
/// yuvarlanmaz; mum aralığını çağıran ([grafikPaylasimDonemi]) ekler.
String gorunurTarihAraligi(int basMs, int sonMs, String dil,
    {required bool gunIci}) {
  final a = DateTime.fromMillisecondsSinceEpoch(math.min(basMs, sonMs));
  final b = DateTime.fromMillisecondsSinceEpoch(math.max(basMs, sonMs));
  final ayniGun = a.year == b.year && a.month == b.month && a.day == b.day;
  final ayniYil = a.year == b.year;
  if (gunIci && ayniGun) {
    return '${DateFormat('d MMM y HH:mm', dil).format(a)}'
        '\u2013${DateFormat('HH:mm', dil).format(b)}';
  }
  if (gunIci) {
    final f = DateFormat(ayniYil ? 'd MMM HH:mm' : 'd MMM y HH:mm', dil);
    return '${f.format(a)} \u2013 ${f.format(b)}';
  }
  if (ayniGun) return DateFormat('d MMM y', dil).format(a);
  final bas = DateFormat(ayniYil ? 'd MMM' : 'd MMM y', dil).format(a);
  return '$bas \u2013 ${DateFormat('d MMM y', dil).format(b)}';
}

/// Paylaşımın "dönem" alanı: mum aralığı + görünen tarih aralığı
/// ("günlük mumlar, 22 Ağu – 29 Eki 2026"). Başlık, görseldeki şerit ve
/// paylaşım metni aynı cümleyi okur.
String grafikPaylasimDonemi(AppLocalizations l,
        {required String aralikAdi,
        required int basMs,
        required int sonMs,
        required String dil,
        required bool gunIci}) =>
    l.tegPaylasimDonem(
        aralikAdi, gorunurTarihAraligi(basMs, sonMs, dil, gunIci: gunIci));

/// Paylaşılan dosyanın adı: "sandik-thyao-grafik.png".
///
/// Neden: ortak `ShareCardService` her görsele "sandik-ozet.png" diyordu;
/// alıcının galerisinde grafik, özet kartıyla aynı adla duruyordu. Ad
/// yalnız ASCII küçük harf, rakam ve tire: bazı paylaşım hedefleri (e-posta
/// eki, Windows) Türkçe harfi ve noktayı bozar. Sembolden bir şey kalmazsa
/// "sandik-grafik.png".
String grafikPaylasimDosyaAdi(String ad) {
  const tr = {
    'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u',
    'â': 'a', 'î': 'i', 'û': 'u',
  };
  var k = ad.replaceAll('İ', 'i').replaceAll('I', 'i').toLowerCase();
  tr.forEach((a, b) => k = k.replaceAll(a, b));
  k = k
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return k.isEmpty ? 'sandik-grafik.png' : 'sandik-$k-grafik.png';
}

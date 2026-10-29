import 'dart:math' as math;

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

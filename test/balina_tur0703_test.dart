import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';

import 'helpers/kaynak.dart';

/// Ar-Ge 22 Kas 07:03 balina katmanı turu: kilitli kart dokunuşu, somut kilit
/// metni, not kilidi doğrudan paywall, tarih aralığı, yeniden dene.
/// Kaynak taramaları kasıtlı: widget'lar canlı sağlayıcı ister.
void main() {
  final akis = ekranKaynagiSync('lib/widgets/para_akisi_karti.dart');
  final hacim = ekranKaynagiSync('lib/widgets/hacim_radari_karti.dart');
  final kutu = ekranKaynagiSync('lib/widgets/analiz_notu_kutusu.dart');
  final hafta = ekranKaynagiSync('lib/screens/hafta_ozeti_screen.dart');
  final notEkrani = ekranKaynagiSync('lib/screens/analiz_notu_screen.dart');

  test('1: kilitliyken kart dokunuşu null değil, kilit satırıyla aynı yol', () {
    for (final k in [akis, hacim]) {
      expect(k.contains('onTap: kilitli ? null : ayrintiyaGit'), isFalse);
      expect(k.contains('KilitSatiri.ac(context'), isTrue);
      expect(k.contains('KilitliBirlesik('), isTrue);
    }
    expect(RegExp(r'KilitSatiri\.ac\(context').allMatches(hacim).length, 2);
    // Satır ve kart aynı statik yolu kullanır (premium_gate_shown dahil).
    expect(akis.contains('onTap: () => ac(context, kaynak: kaynak'), isTrue);
  });

  test('2: somut kilit metni; n == 0 sayısız, seri boşsa genel', () {
    expect(hacim.contains('l10n.prmKilitKriptoBaski'), isTrue);
    expect(hacim.contains('hacimKilitMetni(l10n, ozet)'), isTrue);
    expect(hacim.contains('if (gun == 0) return l.prmKilitAyrinti;'), isTrue);
    expect(hacim.contains('n == 0 ? l.prmKilitHacimSayisiz(gun)'), isTrue);
    final tr = AppLocalizationsTr();
    final en = AppLocalizationsEn();
    expect(tr.prmKilitHacim(30, 2),
        "30 günlük hacim grafiği ve 2 olağan dışı gün Premium'da");
    expect(tr.prmKilitHacimSayisiz(30), "30 günlük hacim grafiği Premium'da");
    expect(en.prmKilitHacim(30, 2),
        '30-day volume chart and 2 unusual days are in Premium');
    expect(tr.prmKilitKriptoBaski, "Saat saat alıcı baskısı Premium'da");
  });

  test('3: kilitli kutu KilitSatiri; hafta özeti satırı ekran itmez', () {
    expect(kutu.contains('radarKilitliProvider'), isTrue);
    expect(kutu.contains('l10n.anzKilitMaddeli(not.maddeSayisi)'), isTrue);
    expect(kutu.contains("ozellik: 'analiz_notu'"), isTrue);
    expect(hafta.contains('onPressed: notKilitli'), isTrue);
    expect(hafta.contains("KilitSatiri.ac(context,"), isTrue);
    expect(AppLocalizationsTr().anzKilitMaddeli(4),
        "4 maddelik notun tamamı Premium'da");
  });

  test('4: kilitli gövde tarih aralığı yazar', () {
    expect(notEkrani.contains('_kilitliAralik(context)'), isTrue);
    expect(notEkrani.contains("widget.tur == 'aylik'"), isTrue);
    expect(notEkrani.contains('widget.donem.add(const Duration(days: 6))'),
        isTrue);
  });

  test('5: başlıksız (bildirim) açılamadı yolunda yeniden dene', () {
    expect(notEkrani.contains('onRetry: widget.baslik == null'), isTrue);
    expect(notEkrani.contains('context.l10n.retry'), isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/services/yasal_adim_plani.dart';
import 'package:portfoy_takip/services/yasal_metin_katalogu.dart';
import 'package:portfoy_takip/services/yasal_onay_service.dart';
import 'package:portfoy_takip/widgets/yasal_adimlar.dart';

/// Adım düzeni (kullanıcı kararı 2026-10-05, seçenek "C · Adım adım") —
/// eksik kümesinden adımları kuran saf fonksiyonun kilidi. Kullanıcıya
/// anlatılan kural birebir: ekranda yalnız GÜNCEL sürümü onaylanmamış
/// metinlerin adımı görünür; sıra her yerde uyarı → Açık Rıza → kutu.
void main() {
  final l = AppLocalizationsTr();

  const uyari = YasalAdimTuru.yatirimUyarisi;
  const riza = YasalAdimTuru.acikRiza;
  const kutu = YasalAdimTuru.kutu;

  /// Kullanıcının etkin onayları: [eski]deki belgelerin ESKİ sürümü (1.0),
  /// diğerlerinin güncel sürümü; kutu güncel (ya da [kutuEski]).
  YasalKapiDurumu durum({
    Set<YasalBelge> eski = const {},
    bool kutuEski = false,
  }) =>
      YasalOnayService.eksikleriHesapla([
        for (final b in YasalBelge.values)
          (b.tur, eski.contains(b) ? '1.0' : b.surum),
        (YasalTur.kayitTekKutu,
            kutuEski ? '1.0' : YasalMetinKatalogu.kutuSurumu),
      ]);

  List<YasalAdimTuru> turler(YasalAdimPlani p) =>
      [for (final a in p.adimlar) a.tur];

  group('yeni kayıt', () {
    final p = YasalAdimPlani.kayit();

    test('3 adım: uyarı → Açık Rıza → kutu; diğer belgeler bilgi amaçlı üçü',
        () {
      expect(turler(p), [uyari, riza, kutu]);
      expect(p.adimlar.last.guncellenenler, isEmpty);
      expect(p.digerBelgeler,
          [YasalBelge.kosullar, YasalBelge.gizlilik, YasalBelge.kvkk]);
      expect(p.kapiBasligi, isNull);
      expect(yasalAdimAdi(l, p.adimlar.last), "Kullanım Koşulları'nı kabul et");
    });

    test('durumlar sırayla ilerler; son eylem yalnız hepsi tamamken', () {
      var onay = <String>{};
      var kutuVar = false;
      List<YasalAdimDurumu> d() =>
          p.durumlar(onaylananlar: onay, kutuIsaretli: kutuVar);
      bool tamam() => p.hepsiTamam(onaylananlar: onay, kutuIsaretli: kutuVar);

      expect(d(), [
        YasalAdimDurumu.aktif,
        YasalAdimDurumu.bekliyor,
        YasalAdimDurumu.bekliyor,
      ]);
      expect(tamam(), isFalse);
      onay = {YasalTur.yatirimUyarisi};
      expect(d(), [
        YasalAdimDurumu.tamam,
        YasalAdimDurumu.aktif,
        YasalAdimDurumu.bekliyor,
      ]);
      onay = {YasalTur.yatirimUyarisi, YasalTur.acikRiza};
      expect(d(), [
        YasalAdimDurumu.tamam,
        YasalAdimDurumu.tamam,
        YasalAdimDurumu.aktif,
      ]);
      expect(tamam(), isFalse, reason: 'kutu işaretsiz');
      kutuVar = true;
      expect(d(), everyElement(YasalAdimDurumu.tamam));
      expect(tamam(), isTrue);
      // İşaret kaldırılırsa kutu yeniden sıradaki adım olur.
      kutuVar = false;
      expect(d().last, YasalAdimDurumu.aktif);
    });

    test('eksikler adıyla, sırayla (hata metni bunu yazar)', () {
      final e = p.eksikler(
          onaylananlar: {YasalTur.acikRiza}, kutuIsaretli: false);
      expect([for (final a in e) a.tur], [uyari, kutu]);
    });
  });

  group('kapı — yalnız değişenler', () {
    test('yalnız Açık Rıza güncellendi: 1 adım, kutu YOK', () {
      final p = YasalAdimPlani.kapi(durum(eski: {YasalBelge.acikRiza}),
          yatirimUyarisiDahil: false);
      expect(turler(p), [riza]);
      expect(p.kutuVar, isFalse);
      expect(p.kapiBasligi, YasalKapiBasligi.tekBelge);
      expect(p.digerBelgeler,
          [YasalBelge.kosullar, YasalBelge.gizlilik, YasalBelge.kvkk]);
    });

    test(
        'yalnız Koşullar güncellendi: 1 adım (kutu), başlıkta "Kullanım '
        'Koşulları güncellendi", belge adımda bağlantı', () {
      final p = YasalAdimPlani.kapi(durum(eski: {YasalBelge.kosullar}),
          yatirimUyarisiDahil: false);
      expect(turler(p), [kutu]);
      expect(p.adimlar.single.guncellenenler, [YasalBelge.kosullar]);
      expect(yasalAdimAdi(l, p.adimlar.single),
          'Kullanım Koşulları güncellendi');
      expect(p.kapiBasligi, YasalKapiBasligi.tekBelge);
      // Adımdaki bağlantı ikinci kez "Diğer belgeler"de yer almaz.
      expect(p.digerBelgeler,
          [YasalBelge.gizlilik, YasalBelge.kvkk, YasalBelge.acikRiza]);
    });

    for (final b in [YasalBelge.gizlilik, YasalBelge.kvkk]) {
      test('yalnız ${b.name} güncellendi: 1 adım (kutu "bilgilendirildim"), '
          'belge adı vurgulu', () {
        final p = YasalAdimPlani.kapi(durum(eski: {b}),
            yatirimUyarisiDahil: false);
        expect(turler(p), [kutu]);
        expect(p.adimlar.single.guncellenenler, [b]);
        expect(yasalAdimAdi(l, p.adimlar.single),
            '${yasalBelgeAdaylari(l, b).first} güncellendi');
        expect(p.kapiBasligi, YasalKapiBasligi.tekBelge);
        expect(p.digerBelgeler, isNot(contains(b)));
      });
    }

    test('yalnız uyarı: 1 adım (oku/onayla), kutu yok', () {
      final p = YasalAdimPlani.kapi(durum(), yatirimUyarisiDahil: true);
      expect(turler(p), [uyari]);
      expect(p.kapiBasligi, YasalKapiBasligi.tekBelge);
      expect(p.digerBelgeler, YasalBelge.values);
    });

    test('yalnız kutu cümlesi güncellendi: 1 adım (kutu), belge yok', () {
      final p = YasalAdimPlani.kapi(durum(kutuEski: true),
          yatirimUyarisiDahil: false);
      expect(turler(p), [kutu]);
      expect(p.adimlar.single.guncellenenler, isEmpty);
      expect(p.kapiBasligi, YasalKapiBasligi.tekBelge);
    });

    test('birden çok: yalnız değişenler, sırayla; "Güncellenen belgeler"', () {
      final p = YasalAdimPlani.kapi(
          durum(eski: {YasalBelge.kosullar, YasalBelge.acikRiza}),
          yatirimUyarisiDahil: true);
      expect(turler(p), [uyari, riza, kutu]);
      expect(p.adimlar.last.guncellenenler, [YasalBelge.kosullar]);
      expect(p.kapiBasligi, YasalKapiBasligi.cokBelge);
    });

    test('dördü birden (1.3 → 1.4): rıza + kutu; üç belge kutu adımında', () {
      final p = YasalAdimPlani.kapi(
          durum(eski: YasalBelge.values.toSet(), kutuEski: true),
          yatirimUyarisiDahil: false);
      expect(turler(p), [riza, kutu]);
      expect(p.adimlar.last.guncellenenler,
          [YasalBelge.kosullar, YasalBelge.gizlilik, YasalBelge.kvkk]);
      expect(yasalAdimAdi(l, p.adimlar.last),
          'Kullanım Koşulları, Gizlilik Politikası ve KVKK Aydınlatma Metni '
          'güncellendi');
      expect(p.digerBelgeler, isEmpty);
      expect(p.kapiBasligi, YasalKapiBasligi.cokBelge);
    });

    test('hiç önceki onay yok (Apple/Google ilk giriş): "Yasal belgeler", '
        'kayıtla aynı adımlar', () {
      final p = YasalAdimPlani.kapi(YasalOnayService.eksikleriHesapla(const []),
          yatirimUyarisiDahil: true);
      expect(turler(p), [uyari, riza, kutu]);
      expect(p.adimlar.last.guncellenenler, isEmpty);
      expect(p.kapiBasligi, YasalKapiBasligi.ilk);
      expect(p.digerBelgeler, YasalAdimPlani.kayit().digerBelgeler);
    });

    test('sıra her bileşimde uyarı → Açık Rıza → kutu', () {
      for (var maske = 0; maske < 1 << YasalBelge.values.length; maske++) {
        for (final uyariVar in [false, true]) {
          final eski = {
            for (var i = 0; i < YasalBelge.values.length; i++)
              if (maske & (1 << i) != 0) YasalBelge.values[i],
          };
          final p = YasalAdimPlani.kapi(durum(eski: eski),
              yatirimUyarisiDahil: uyariVar);
          final t = turler(p);
          final sirali = [...t]..sort((a, b) => a.index.compareTo(b.index));
          expect(t, sirali, reason: '$eski uyarı=$uyariVar');
          // Onaylanmış metnin adımı hiç yok.
          expect(t.contains(riza), eski.contains(YasalBelge.acikRiza));
          expect(t.contains(uyari), uyariVar);
          expect(
              t.contains(kutu),
              eski.any((b) => b != YasalBelge.acikRiza),
              reason: '$eski');
        }
      }
    });
  });

  test('İngilizce adlar da tam (kutu adımı başlığı)', () {
    final en = AppLocalizationsEn();
    final p = YasalAdimPlani.kapi(
        durum(eski: {YasalBelge.gizlilik, YasalBelge.kvkk}),
        yatirimUyarisiDahil: false);
    expect(yasalAdimAdi(en, p.adimlar.single),
        'Privacy Policy and KVKK Privacy Notice updated');
    expect(en.yasalAdimKayitBaslik(3), '3 steps to sign up');
    expect(en.yasalAdimKapiBaslik(1), '1 step');
    expect(l.yasalAdimKayitBaslik(3), 'Kayıt için 3 adım');
  });
}

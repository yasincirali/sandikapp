import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/services/portfoy_yorumu_service.dart';
import 'package:portfoy_takip/widgets/portfoy_yorumu_karti.dart';

/// AI portföy yorumu hata metinleri (2026-11-13).
///
/// Kilitlenen: ortak aylık tavan (`tavan`) günlük hakla AYNI metne düşmez
/// (kullanıcı ay sonuna dek her gün "yarın dene" okuyordu); günlük hak
/// metni "yarın" vaat etmez; sunucunun `yeniden_dene` alanı varsa saat yazılır.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });
  final tr = lookupAppLocalizations(const Locale('tr'));
  final simdi = DateTime(2026, 11, 13, 20, 0);
  String metin(PortfoyYorumHatasi e) =>
      portfoyYorumHataMetni(tr, e, dil: 'tr_TR', simdi: simdi);

  group('govdeden', () {
    test('neden → tür', () {
      final ornek = {
        'riza': YorumHataTuru.riza,
        'premium': YorumHataTuru.premium,
        'gunluk_hak': YorumHataTuru.kota,
        'aylik_hak': YorumHataTuru.kotaAy,
        'tavan': YorumHataTuru.tavan,
        'reddedildi': YorumHataTuru.reddedildi,
        'kapali': YorumHataTuru.kapali,
        'sunucu': YorumHataTuru.diger,
      };
      ornek.forEach((neden, tur) {
        expect(PortfoyYorumHatasi.govdeden({'neden': neden}).tur, tur,
            reason: neden);
      });
      expect(PortfoyYorumHatasi.govdeden(null).tur, YorumHataTuru.diger);
      expect(PortfoyYorumHatasi.govdeden('bozuk').tur, YorumHataTuru.diger);
    });

    test('yeniden_dene yalnız günlük hakta okunur', () {
      final e = PortfoyYorumHatasi.govdeden(
          {'neden': 'gunluk_hak', 'yeniden_dene': '2026-11-14T06:30:00.000Z'});
      expect(e.yenidenDene, DateTime.utc(2026, 11, 14, 6, 30).toLocal());
      expect(
          PortfoyYorumHatasi.govdeden(
                  {'neden': 'tavan', 'yeniden_dene': '2026-11-14T06:30:00Z'})
              .yenidenDene,
          isNull);
      expect(
          PortfoyYorumHatasi.govdeden({'neden': 'gunluk_hak', 'yeniden_dene': 'x'})
              .yenidenDene,
          isNull);
    });
  });

  group('portfoyYorumHataMetni', () {
    test('tavan: nötr, kişisel hak değil, ayın 1’i', () {
      final m = metin(const PortfoyYorumHatasi(YorumHataTuru.tavan));
      expect(m, 'Yorumlar bu ay için geçici olarak durdu, 1 Aralık itibarıyla yeniden açılır.');
      expect(m, isNot(metin(const PortfoyYorumHatasi(YorumHataTuru.kota))));
      // Aralık → Ocak (yıl devri).
      expect(
          portfoyYorumHataMetni(tr, const PortfoyYorumHatasi(YorumHataTuru.tavan),
              dil: 'tr_TR', simdi: DateTime(2026, 12, 20)),
          contains('1 Ocak'));
    });

    test('günlük hak: "yarın" vaadi yok', () {
      final m = metin(const PortfoyYorumHatasi(YorumHataTuru.kota));
      expect(m, isNot(contains('yarın')));
      expect(m, contains('birkaç saat'));
    });

    test('günlük hak + yeniden_dene: saat, başka günse günüyle', () {
      expect(
          metin(PortfoyYorumHatasi(YorumHataTuru.kota,
              yenidenDene: DateTime(2026, 11, 13, 22, 40))),
          'Günlük yorum hakkın doldu, 22:40 itibarıyla yeniden deneyebilirsin.');
      expect(
          metin(PortfoyYorumHatasi(YorumHataTuru.kota,
              yenidenDene: DateTime(2026, 11, 14, 9, 5))),
          'Günlük yorum hakkın doldu, 14 Kas 09:05 itibarıyla yeniden deneyebilirsin.');
    });

    test('kişisel aylık hak ayrı metinde kalır', () {
      expect(metin(const PortfoyYorumHatasi(YorumHataTuru.kotaAy)),
          tr.pyzHataKotaAy);
    });
  });
}

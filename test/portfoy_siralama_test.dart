import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/config/pref_keys.dart';
import 'package:portfoy_takip/models/portfoy_siralama.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/utils/tr_katla.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// "Ada göre (A–Z)" (Ar-Ge 7 Kas 08:03 #2): Türkçe harf sırası, kalıcılık
/// ve eski sürümün bu kodu okuyuşu.
void main() {
  List<String> sirala(List<String> l) => [...l]..sort(trKarsilastir);

  group('trKarsilastir — Türkçe alfabe', () {
    test('Ç/Ğ/İ/Ö/Ş/Ü kendi harfinin ardında, Z\'nin önünde', () {
      expect(
        sirala(['Zorlu', 'Şişecam', 'Sasa', 'Çimsa', 'Cola', 'Ülker',
            'Ulusoy', 'Öztürk', 'Otokar', 'Ğ-test', 'Gübre']),
        ['Cola', 'Çimsa', 'Gübre', 'Ğ-test', 'Otokar', 'Öztürk', 'Sasa',
            'Şişecam', 'Ulusoy', 'Ülker', 'Zorlu'],
      );
    });

    test('I/ı önce, İ/i sonra; büyük/küçük harf sırayı bozmaz', () {
      expect(sirala(['İş Bankası', 'Isparta', 'ihlas', 'ılık']),
          ['ılık', 'Isparta', 'ihlas', 'İş Bankası']);
      expect(trKarsilastir('ISCTR', 'ısctr') != 0, isTrue,
          reason: 'eşitlikte ham sıra — kararlı');
    });

    test('kod adları: THYAO, ŞOK, SASA, GARAN, Gram Altın', () {
      expect(sirala(['THYAO', 'ŞOK', 'SASA', 'Gram Altın', 'GARAN', 'AKBNK']),
          ['AKBNK', 'GARAN', 'Gram Altın', 'SASA', 'ŞOK', 'THYAO']);
    });

    test('q/w/x komşusunun ardında, rakam harften önce', () {
      expect(sirala(['xyz', 'wolf', 'vadeli', 'yen', 'quartz', 'pera', 'rota']),
          ['pera', 'quartz', 'rota', 'vadeli', 'wolf', 'xyz', 'yen']);
      expect(sirala(['Altın', '1 Ons']), ['1 Ons', 'Altın']);
    });

    test('önek kısa olan önce', () {
      expect(sirala(['Türk Telekom', 'Türk']), ['Türk', 'Türk Telekom']);
    });
  });

  group('kod ve eski sürüm', () {
    test('"ad_artan" kendine döner', () {
      expect(PortfoySiralama.nameAsc.kod, 'ad_artan');
      expect(PortfoySiralama.kodla('ad_artan'), PortfoySiralama.nameAsc);
    });

    // Eski build'in enum'unda nameAsc yok; onun kodla()'sı tanımadığı kodu
    // varsayılana düşürür. Aynı davranışı bu build'in tanımadığı bir
    // gelecek koduyla kilitliyoruz: çökme değil, "Değere göre".
    test('tanınmayan gelecek kodu → varsayılan, çökme yok', () {
      expect(PortfoySiralama.kodla('gelecek_siralama'),
          PortfoySiralama.varsayilan);
    });
  });

  group('kalıcılık', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      setPreferencesUser(null);
    });
    tearDown(() => setPreferencesUser(null));

    test('ada göre seçimi soğuk açılışta geri gelir', () async {
      await initPreferencesCache();
      final ilk = ProviderContainer();
      setPreferencesUser('A');
      ilk.invalidate(portfoySiralamaProvider);
      await ilk
          .read(portfoySiralamaProvider.notifier)
          .set(PortfoySiralama.nameAsc.kod);
      ilk.dispose();

      await initPreferencesCache();
      final ikinci = ProviderContainer();
      addTearDown(ikinci.dispose);
      expect(PortfoySiralama.kodla(ikinci.read(portfoySiralamaProvider)),
          PortfoySiralama.nameAsc);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('${PrefKeys.portfoySiralama}_A'), 'ad_artan');
    });
  });

  test('Portföy ekranı ada göre seçeneğini sunar ve sıralar', () {
    final src = ekranKaynagiSync('lib/screens/portfolio_screen.dart');
    expect(src, contains('case PortfoySiralama.nameAsc:'));
    expect(src, contains('PortfoySiralama.nameAsc, l.sortName'));
    expect(src, contains('trKarsilastir('));
  });
}

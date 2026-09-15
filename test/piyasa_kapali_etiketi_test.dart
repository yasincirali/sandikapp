
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/utils/piyasa_kapali_etiketi.dart';
import 'helpers/kaynak.dart';

/// Rozet, portföydeki TÜRLERE göre dürüst olmalı.
///
/// ## Kullanıcının yakaladığı çelişki (2026-09-12)
/// "Piyasa kapalı dedik ama fiyatı değişen bir varlık var demek ki."
///
/// Haklıydı. Ölçüldü:
///   * Döviz/emtia/altın spot piyasaları Pazar akşamı açılıyor.
///   * Hisse/fon BIST ve TEFAS takvimine bağlı — hafta sonu kesin kapalı.
///
/// Hepsine birden "PİYASA KAPALI" demek, dövizi olan kullanıcı için
/// yanlış bilgiydi.
void main() {
  group('yalnızca borsa ürünleri', () {
    test('hisse → BORSA KAPALI', () {
      expect(piyasaKapaliEtiketi([AssetType.hisse]), 'BORSA KAPALI');
    });

    test('fon → BORSA KAPALI', () {
      expect(piyasaKapaliEtiketi([AssetType.fon]), 'BORSA KAPALI');
    });

    test('hisse + fon → BORSA KAPALI', () {
      expect(piyasaKapaliEtiketi([AssetType.hisse, AssetType.fon]),
          'BORSA KAPALI');
    });
  });

  group('karışık portföy — "kapalı" genellemesi YAPILMAZ', () {
    test('hisse + altın', () {
      // Asıl düzeltme: spot altın Pazar gecesi hareket ediyor.
      expect(
        piyasaKapaliEtiketi([AssetType.hisse, AssetType.altin]),
        'BORSA KAPALI · DİĞERLERİ SÜRÜYOR',
      );
    });

    test('fon + döviz', () {
      expect(
        piyasaKapaliEtiketi([AssetType.fon, AssetType.doviz]),
        'BORSA KAPALI · DİĞERLERİ SÜRÜYOR',
      );
    });

    test('hisse + altın + emtia', () {
      expect(
        piyasaKapaliEtiketi(
            [AssetType.hisse, AssetType.altin, AssetType.emtia]),
        'BORSA KAPALI · DİĞERLERİ SÜRÜYOR',
      );
    });
  });

  group('borsa ürünü YOK', () {
    test('yalnızca emtia → SON VERİ', () {
      // "Borsa kapalı" demek anlamsız: kullanıcının borsa ürünü yok.
      expect(piyasaKapaliEtiketi([AssetType.emtia]), 'SON VERİ');
    });

    test('yalnızca döviz → SON VERİ', () {
      expect(piyasaKapaliEtiketi([AssetType.doviz]), 'SON VERİ');
    });

    test('yalnızca altın → SON VERİ', () {
      expect(piyasaKapaliEtiketi([AssetType.altin]), 'SON VERİ');
    });
  });

  group('sınır durumları', () {
    test('boş liste ÇÖKMEZ', () {
      expect(() => piyasaKapaliEtiketi(const []), returnsNormally);
      expect(piyasaKapaliEtiketi(const []), 'PİYASA KAPALI');
    });

    test('`diger` türü tek başına', () {
      // Ne borsaya bağlı ne de kapalıda işleyen listede — genel ifadeye
      // düşer.
      expect(piyasaKapaliEtiketi([AssetType.diger]), 'PİYASA KAPALI');
    });

    test('tekrar eden türler sonucu değiştirmez', () {
      expect(
        piyasaKapaliEtiketi(
            [AssetType.hisse, AssetType.hisse, AssetType.hisse]),
        'BORSA KAPALI',
      );
    });

    test('HER tür için boş olmayan etiket döner', () {
      for (final t in AssetType.values) {
        final e = piyasaKapaliEtiketi([t]);
        expect(e.trim(), isNotEmpty, reason: '$t için boş etiket.');
      }
    });
  });

  group('YASAL/DİL', () {
    test('etiket "veri yok" DEMEZ', () {
      // Ayrı bir kavram zaten var (`gunIciVerisiYokTurler`): o, fiyat
      // ÇEKİLEMEDİĞİNİ söyler. Kuyruk ise fiyatın var olduğu ama
      // piyasanın kapalı olduğu durum.
      for (final t in AssetType.values) {
        expect(piyasaKapaliEtiketi([t]).toLowerCase().contains('veri yok'),
            isFalse);
      }
    });
  });

  test('ekran rozeti bu fonksiyondan besleniyor', () {
    final kaynak = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart')
        .replaceAll('\r\n', '\n');

    expect(kaynak.contains('piyasaKapaliEtiketiVarliklardan(targetAssets)'),
        isTrue,
        reason: 'Rozet hâlâ sabit metin kullanıyor.');
    expect(kaynak.contains("'PİYASA KAPALI',"), isFalse,
        reason: 'Sabit "PİYASA KAPALI" geri gelmiş — dövizi olan '
            'kullanıcıya yanlış bilgi.');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart';

/// Kullanıcı bildirimi: "Uygulama ilk açılışında ana ekran 2 kere load oluyor"
/// ve düzeltme sonrası "ilk login olunduğunda ekran hala 2 kez load oluyor".
///
/// Kök neden: splash kapısı, ortak listesi henüz çözülmemişken "ortak yok"
/// sanıp erken açılıyordu. Liste sonradan dolunca HomeScreen ortak varlıkları
/// için KENDİ loading'ini açıyor ve kullanıcı arka arkaya iki loading görüyordu.
void main() {
  group('splashVeriHazir — tek loading değişmezi', () {
    test('ortak listesi çözülmeden ASLA hazır sayılmaz (regresyon)', () {
      // Kritik senaryo: portföy gelmiş, ortak listesi hâlâ yolda.
      // `activePartnersProvider` bu anda boş liste döndürür — "ortak yok" gibi
      // görünür. Kapı burada açılırsa ikinci loading doğar.
      expect(
        splashVeriHazir(
          portfolioSettled: true,
          partnerListSettled: false,
          ortakVar: false, // yükleniyorken boş liste — yanıltıcı
          partnerAssetsSettled: false,
        ),
        isFalse,
        reason: 'Ortak listesi çözülmeden kapı açılmamalı',
      );
    });

    test('ortak yoksa ortak varlığı beklenmez', () {
      expect(
        splashVeriHazir(
          portfolioSettled: true,
          partnerListSettled: true,
          ortakVar: false,
          partnerAssetsSettled: false,
        ),
        isTrue,
      );
    });

    test('ortak varsa ortak varlıkları da beklenir', () {
      expect(
        splashVeriHazir(
          portfolioSettled: true,
          partnerListSettled: true,
          ortakVar: true,
          partnerAssetsSettled: false,
        ),
        isFalse,
      );
      expect(
        splashVeriHazir(
          portfolioSettled: true,
          partnerListSettled: true,
          ortakVar: true,
          partnerAssetsSettled: true,
        ),
        isTrue,
      );
    });

    test('portföy gelmeden hazır sayılmaz', () {
      expect(
        splashVeriHazir(
          portfolioSettled: false,
          partnerListSettled: true,
          ortakVar: false,
          partnerAssetsSettled: true,
        ),
        isFalse,
      );
    });

    test('her şey hazırsa kapı açılır', () {
      expect(
        splashVeriHazir(
          portfolioSettled: true,
          partnerListSettled: true,
          ortakVar: true,
          partnerAssetsSettled: true,
        ),
        isTrue,
      );
    });

    test('hata da "çözülmüş" sayılır — splash kilitlenmemeli', () {
      // Çağıran taraf hasError'ı settled olarak geçirir; HomeScreen kendi
      // hata görünümünü gösterir. Burada doğrulanan: settled=true geldiğinde
      // fonksiyon beklemeye devam etmez.
      expect(
        splashVeriHazir(
          portfolioSettled: true, // hasError → settled
          partnerListSettled: true, // hasError → settled
          ortakVar: false,
          partnerAssetsSettled: false,
        ),
        isTrue,
      );
    });
  });
}

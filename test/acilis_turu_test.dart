import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/tazelik_ritmi.dart';

/// Açılış fiyat turu iki yerden istenir: splash (`_AuthGateState._acilisiIsit`)
/// ve `MainNavigationScreen.initState`. Tur BİR kez koşmalı; ikincisi
/// `isLoading: true` yayınıyla ana ekranı "yenileniyor"a sokar ve aynı
/// kotasyonları ikinci kez çeker (2026-09-28).
void main() {
  final simdi = DateTime(2026, 9, 28, 9, 30);

  test('hiç tur olmadıysa gerekli', () {
    expect(PortfolioNotifier.acilisTuruGerekli(null, simdi), isTrue);
  });

  test('yüzey tazelik penceresi içinde biten tur varsa gereksiz', () {
    final az = simdi.subtract(const Duration(seconds: 2));
    expect(PortfolioNotifier.acilisTuruGerekli(az, simdi), isFalse);
    final sinir = simdi.subtract(TazelikRitmi.yuzey - const Duration(seconds: 1));
    expect(PortfolioNotifier.acilisTuruGerekli(sinir, simdi), isFalse);
  });

  test('pencere dolduysa yeniden gerekli — nabızla aynı ritim', () {
    expect(
      PortfolioNotifier.acilisTuruGerekli(simdi.subtract(TazelikRitmi.yuzey), simdi),
      isTrue,
    );
  });
}

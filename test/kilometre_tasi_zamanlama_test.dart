import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kilometre taşı kutlaması — DOĞRU YER VE ZAMAN korumaları (main.dart).
///
/// REGRESYON (2026-09-27): çıkış → giriş yapınca "2 yıldır takiptesin"
/// kutlaması ve hemen ardından puan istemi geldi. Karar mantığı saf
/// (`MilestoneService.ayir`, milestone_service_test); buradakiler ekran
/// katmanındaki korumalar — `_AuthGateState` içinde, pompalanması büyük bir
/// düzenek ister. Kaynak testi: her korumanın VAR ve DOĞRU SIRADA olduğunu
/// kilitler.
void main() {
  final src = File('lib/main.dart').readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
  final bas = src.indexOf('Future<void> _kilometreTasiKontrol(');
  final govde = src.substring(bas, src.indexOf('String _bucketAssetCount', bas));

  test('fiyatlar yerleşmeden ölçülmez (yarım fiyat sahte eşik üretir)', () {
    expect(govde.contains('if (state.isLoading || state.lastUpdated == null) return;'), isTrue);
  });

  test('girişten sonraki ilk ölçüm sessiz — giriş olayı soğuk açılıştan ayrılır', () {
    expect(src.contains('if (prev != null && prev.hasValue && prev.valueOrNull == null) '
        '{ _kilometreTasiSessizKullanici = user.id; }'), isTrue,
        reason: 'soğuk açılışta önceki değer yükleniyordur; girişte "kullanıcı yok" yerleşiktir');
    expect(govde.contains('girisSonrasi: girisSonrasi'), isTrue);
  });

  test('ilk kez ölçülen kullanıcı (mevcut portföyünü giriyor) sessiz', () {
    // Canlı veri 26–27 Eylül: iki yeni kullanıcı varlık girer girmez
    // "250 bin ₺ geçildi" gördü — geçilen eşik yok, veri girişi var.
    expect(govde.contains('ilkKez: onceden.isEmpty'), isTrue);
  });

  test('her await\'ten sonra kullanıcı yeniden doğrulanır (giriş ekranına sheet açılmaz)', () {
    final okuma = govde.indexOf('await repo.fetchReached(user.id);');
    expect(govde.indexOf('!ayniKullanici()', okuma), greaterThan(okuma));
    final sheet = govde.indexOf('MilestoneSheet.show(ctx, secilen)');
    expect(govde.lastIndexOf('ayniKullanici()', sheet), greaterThan(govde.indexOf('markShown')));
  });

  test('yer uygun değilse kutlanacaklar KAYDEDİLMEZ (sonra yeniden denenir)', () {
    final yer = govde.indexOf('!_kutlamaYeriUygun()) return;');
    final kayit = govde.indexOf('await repo.recordReached(user.id, ayrim.kutla);');
    expect(yer, greaterThan(0));
    expect(kayit, greaterThan(yer), reason: 'kayıt yer kontrolünden SONRA olmalı');
  });

  test('yer kontrolü kilit, onboarding, uyarı, tur, önplan ve üst rota içerir', () {
    final i = src.indexOf('bool _kutlamaYeriUygun()');
    final yer = src.substring(i, src.indexOf('}', src.indexOf('canPop()', i)));
    for (final k in ['_locked', '_onboardingDone != true', '_disclaimerAccepted != true',
                     'tanitimTuruAktif', 'AppLifecycleState.resumed', 'canPop() == false']) {
      expect(yer.contains(k), isTrue, reason: '$k eksik');
    }
  });
}

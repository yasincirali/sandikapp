import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Hesap silme uçarken ekran TAMAMEN kilitli olmalı.
///
/// 2026-09-14 elle regresyon (R-41) bulgusu: ikinci onaydan sonra istek
/// uçarken ekran etkileşime açık kalıyordu. `_deleting` bayrağı set
/// ediliyordu ama yalnızca `Scaffold.body`'yi saran bir `AbsorbPointer`'ı
/// besliyordu — app bar'ın geri oku ve sistem geri hareketi açıktı.
///
/// Neden önemli: hesap silme GERİ ALINAMAZ ve 30 sn'ye kadar sürebilir.
/// O pencerede kullanıcı ekrandan çıkarsa `_runDelete` içindeki
/// `Navigator.popUntil` yanlış ekranı kapatır ve kullanıcı "silindi mi?"
/// sorusuyla baş başa kalır.
///
/// Bu test kaynak metnine bakar (ratchet): `SettingsScreen` auth +
/// Supabase'e bağlı olduğu için widget testinde ayağa kaldırmak
/// orantısız; korunması gereken şey davranışın KURULUMU.
void main() {
  final kaynak =
      File('lib/screens/settings_screen.dart').readAsStringSync();
  // dart format satır sonlarını oynatabilir; boşlukları tekilleştir.
  final duz = kaynak.replaceAll(RegExp(r'\s+'), ' ');

  test('silme sırasında geri çıkış engellenir (PopScope)', () {
    expect(
      duz.contains('PopScope( canPop: !_deleting'),
      isTrue,
      reason: 'Silme uçarken sistem geri hareketi hesabı yarı silinmiş '
          'sanan bir kullanıcı bırakır. PopScope(canPop: !_deleting) kalmalı.',
    );
  });

  test('silme sırasında app bar geri oku gizlenir', () {
    expect(
      duz.contains('showBack: !_deleting'),
      isTrue,
      reason: 'AbsorbPointer yalnızca body\'yi sarıyor; app bar ondan '
          'bağımsız. Geri oku açık kalırsa kilit delinir.',
    );
  });

  test('gövde dokunuşu yutulur', () {
    expect(
      duz.contains('AbsorbPointer( absorbing: _deleting'),
      isTrue,
      reason: 'Liste öğeleri silme uçarken tıklanabilir kalmamalı.',
    );
  });

  test('kilit görünür bir örtüyle anlatılır', () {
    expect(
      duz.contains('if (_deleting) Positioned.fill'),
      isTrue,
      reason: 'AbsorbPointer dokunuşu sessizce yutar; ekran çalışır '
          'görünmeye devam eder ve kullanıcı donma sanıp uygulamayı '
          'kapatmaya çalışır. Görsel karşılığı olmalı.',
    );
    expect(
      duz.contains('Hesabın siliniyor'),
      isTrue,
      reason: 'Örtü ne olduğunu söylemeli.',
    );
  });

  test('çift tetikleme korunur', () {
    expect(
      duz.contains('Future<void> _confirmDeleteAccount() async { if (_deleting) return;'),
      isTrue,
      reason: '_exporting\'deki koruma burada da olmalı: ikinci bir silme '
          'akışı başlatılamaz.',
    );
  });
}

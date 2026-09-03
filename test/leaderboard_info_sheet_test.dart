import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Yarış ekranının iki çıkmaz sokağı.**
///
/// ## 1. Info sheet'inin kapatma düğmesi yoktu
/// "Getiri nasıl hesaplanıyor?" sayfası `showModalBottomSheet` ile açılıyor ve
/// içinde açık bir çıkış yolu yoktu. Üstteki tutamak dekoratif bir
/// `Container` — dokunma dinlemiyor. `isScrollControlled: true` + uzun içerik
/// olduğu için "dışarı dokun" alanı da ince bir şeride iniyordu. Geriye tek
/// yol aşağı sürüklemek kalıyordu; bunu bilmeyen kullanıcı sıkışıyor.
///
/// ## 2. Ortağı olmayan kullanıcı ekrana hiç giremiyordu
/// `LeaderboardHeroCard` opt-in açıldığı anda `partners.isEmpty` dalından
/// `SizedBox.shrink()` dönüyordu — kart kayboluyor, performans ekranındaki
/// chip de ortak şartı aradığı için `LeaderboardScreen`'e giden hiçbir yol
/// kalmıyordu. Oysa ekran tam bu durum için bir `_SoloPanel` çiziyor.
/// "Katıl"a basmanın ödülü kartın yok olması olamaz.
///
/// ## Bu testin sınırı
/// Kaynak metnine bakar, piksel ölçmez — `leaderboard_overflow_test` gibi
/// gerçek bir pump testi bu iki kuralı yakalayamaz, çünkü ikisi de "eksik
/// olan şey" hakkında. Amaç regresyonu kilitlemek.
String _yorumsuz(String src) => src
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    })
    .join('\n');

void main() {
  late String ekran;
  late String kart;

  setUpAll(() async {
    ekran = _yorumsuz(
        await File('lib/screens/leaderboard_screen.dart').readAsString());
    kart = _yorumsuz(
        await File('lib/widgets/leaderboard_hero_card.dart').readAsString());
  });

  group('info sheet kapatılabilir', () {
    test('sheet gövdesinde kapatma düğmesi var', () {
      final i = ekran.indexOf('class _RoiInfoSheet');
      expect(i, greaterThan(0),
          reason: 'sheet sınıfı yeniden adlandırılmış — bu testi güncelle');
      // Yalnızca sheet'in başlık bölgesi — dosyanın geri kalanındaki başka
      // bir `pop()` çağrısı bu testi yanlışlıkla geçirmesin.
      final govde = ekran.substring(i, i + 2500);

      expect(govde.contains('Icons.close_rounded'), isTrue,
          reason: 'açık bir çıkış düğmesi olmalı; sürükleme tek yol olamaz');
      expect(govde.contains('Navigator.of(context).pop()'), isTrue,
          reason: 'düğme sheet i gerçekten kapatmalı');
    });

    test('düğme 44pt dokunma hedefi sağlar', () {
      final i = ekran.indexOf('class _RoiInfoSheet');
      final govde = ekran.substring(i, i + 2500);
      expect(govde.contains('width: 44'), isTrue,
          reason: 'HIG minimum dokunma hedefi');
      expect(govde.contains('height: 44'), isTrue);
    });
  });

  group('ortağı olmayan kullanıcı Yarış ekranına girebilir', () {
    test('partner boşken kart GİZLENMEZ', () {
      expect(kart.contains('if (partners.isEmpty) return const SizedBox.shrink()'),
          isFalse,
          reason: 'kart kaybolunca LeaderboardScreen e giden yol kalmıyor');
    });

    test('partner boşken solo karta düşülür', () {
      expect(kart.contains('if (partners.isEmpty) return const _SoloHero()'),
          isTrue,
          reason: 'solo durum için ayrı bir kart olmalı');
    });

    test('solo kart LeaderboardScreen i açar', () {
      final i = kart.indexOf('class _SoloHero');
      expect(i, greaterThan(0));
      final govde = kart.substring(i, i + 1200);
      expect(govde.contains('LeaderboardScreen'), isTrue,
          reason: 'kart yalnızca bilgi vermez, ekranı AÇAR');
    });
  });
}

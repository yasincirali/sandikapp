import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Başarı snack'ı kuralı (TASARIM_DILI §6/5; Ar-Ge 11 Kas 19:04 #6).
///
/// "Kaydedildi / güncellendi" şeridi kullanıcı sonucu zaten ekranda
/// görürken çıkıyor, sekme çubuğunu örtüyordu. Kural: `SandikSnackKind.success`
/// yalnız geri alınabilir eylemde (`onUndo:`) ya da bir sonraki adımı öneren
/// eylem düğmesiyle (`action:`) kullanılır. Sayfayı kapatan kaydet düğmesinde
/// onay `SandikAsyncButton(basari:)` ✓ durumudur; sayfası açık kalan eylemde
/// `SandikHaptic.basari`.
///
/// Aşağıdaki izin listesi yalnız AZALIR. Her satır ya bilgi taşıdığı için
/// (sonuç ekranda görünmüyor, ya da snack ekranda olmayan bir şey söylüyor)
/// bilerek kalır ya da henüz tek tek incelenmedi ("sonraki tur"). Yeni başarı
/// snack'ı eklemek için önce sonucun ekranda görünmediğini gerekçesiyle buraya
/// yaz. Bir satır artık eşleşmiyorsa (snack kalktı) testi listeden silmen
/// ister — liste bayatlamasın.
const _izin = <String, Map<String, String>>{
  'lib/main.dart': {
    'pensionAutoSnack': 'Arka planda kendiliğinden yazılan BES katkısı: '
        'kullanıcı bir şey yapmadı, ekranda da değil.',
  },
  'lib/screens/add_asset/kayit.dart': {
    'priceFromHistorical': 'Tarihli kapanıştan atanan fiyatı söyler; form kapanır, '
        'atanan fiyat başka yerde yazmaz.',
  },
  'lib/widgets/alarm_kur_sheet.dart': {
    'gostergeAlarmKuruldu': 'Kurulan koşulu sözle tekrarlar; sayfa kapanır, '
        'gösterge alarmı çağıran yüzeyde görünmez.',
    'yuzdeAlarmKuruldu': 'Aynı gerekçe (yüzde alarmı).',
    'yonu(sonuc)': 'Kurulan fiyat alarmının yönü ve eşiği; kuran yüzeyde '
        '(grafik, sembol arama) alarm listesi yok.',
    'alarm.isAbove': 'Çalmış alarmı yerinde yeniden kurma: şerit kalkar, '
        'eşik başka yerde yazmaz.',
  },
  'lib/widgets/tek_dokunus_alarm.dart': {
    'tekDokunusYuzdeKuruldu': 'Tek dokunuşla sayfasız kurulan alarm: kurulan '
        'eşiği söyleyen tek yer.',
  },
  'lib/widgets/sozlesme_karti.dart': {
    'pensionAutoUpdated': 'Ar-Ge #6 incelemesi: tutarı gösteren soru kutusu '
        'kalkar, yeni tutar kartta ayrıca yazmaz.',
    'depositRateSavedMidTerm': 'Vade sonu kazancının yeni orandan '
        'hesaplanacağını söyler (ekranda olmayan bilgi).',
    'depositRenewSaved': 'Sonraki tur: yeni dönem kart başlığında görünür, '
        'kaldırma adayı.',
    'depositWithdrawn': 'Sonraki tur: incelenmedi.',
    'pensionContributionSaved': 'Sonraki tur: incelenmedi.',
    'pensionSwitch': 'Sonraki tur: incelenmedi.',
  },
  'lib/widgets/ekran_goruntusu_ekle.dart': {
    'mesaj.join': 'Ekran görüntüsünden okunan kalemlerin sayısı/özeti.',
  },
  'lib/widgets/bedelli_artirim_sheet.dart': {
    'bedelliKaydedildi': 'Eklenen pay adedini söyler.',
  },
  'lib/screens/analiz_notu_screen.dart': {
    'anzTesekkur': 'Gönderilen geri bildirimin sonucu ekranda görünmez.',
  },
  'lib/screens/partnership_requests_screen.dart': {
    'partnershipAcceptedShort': 'Sonraki tur: incelenmedi.',
  },
  'lib/screens/portfoy_yonetimi_screen.dart': {
    'portfoySilindi': 'Sonraki tur: satır listeden kalkar, kaldırma adayı.',
    'portfoyAktarilipSilindi': 'Aktarılan pozisyonların hedefini söyler.',
  },
  'lib/screens/halka_arz_screen.dart': {
    'ipoParticipationSaved': 'Sonraki tur: incelenmedi.',
  },
  'lib/widgets/portfoy_secim_sayfasi.dart': {
    'bildiri': 'Sonraki tur: incelenmedi.',
  },
  'lib/widgets/veri_kalitesi_seridi.dart': {
    'vkHepsiTamam': 'Sonraki tur: incelenmedi.',
  },
};

/// `sandikSnack(` çağrılarının argüman metni (parantez dengeli).
Iterable<String> _snackCagrilari(String kaynak) sync* {
  final desen = RegExp(r'\bsandikSnack\(');
  for (final m in desen.allMatches(kaynak)) {
    var i = m.end;
    var derinlik = 1;
    while (derinlik > 0 && i < kaynak.length) {
      final c = kaynak[i];
      if (c == '(') derinlik++;
      if (c == ')') derinlik--;
      i++;
    }
    yield kaynak.substring(m.end, i - 1);
  }
}

void main() {
  test('başarı snack\'ı yalnız geri al / eylem düğmesiyle (izin listesi azalır)',
      () {
    final kullanilan = <String>{};
    final ihlal = <String>[];
    final dosyalar = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in dosyalar) {
      final yol = f.path.replaceAll(r'\', '/');
      if (yol.endsWith('lib/utils/sandik_snack.dart')) continue;
      for (final arg in _snackCagrilari(f.readAsStringSync())) {
        if (!arg.contains('SandikSnackKind.success')) continue;
        if (arg.contains('onUndo:') || arg.contains('action:')) continue;
        final izin = _izin[yol] ?? const {};
        final capa = izin.keys.where(arg.contains).firstOrNull;
        if (capa == null) {
          ihlal.add('$yol: ${arg.split(RegExp(r'\s+')).join(' ')}');
        } else {
          kullanilan.add('$yol|$capa');
        }
      }
    }
    expect(ihlal, isEmpty,
        reason: 'Geri alınamayan başarı snack\'ı: sonuç ekranda görünüyorsa '
            'snack yerine SandikHaptic.basari (sayfayı kapatan düğmede '
            'SandikAsyncButton(basari:)). Görünmüyorsa gerekçesiyle izin '
            'listesine yaz.');
    final bayat = [
      for (final e in _izin.entries)
        for (final c in e.value.keys)
          if (!kullanilan.contains('${e.key}|$c')) '${e.key}|$c',
    ];
    expect(bayat, isEmpty,
        reason: 'Bu snack\'lar kalktı; izin listesinden de sil.');
  });

  test('Ar-Ge #6 ile kalkan snack\'lar geri gelmedi', () {
    final kaynak = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.dart') && !f.path.contains('l10n/generated'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    for (final anahtar in [
      'alarmGuncellendi',
      'ozgKaydedildi',
      'depositRateSaved',
      'kullaniciAdiKaydedildi',
      'cizgiAlarmiAdlandi',
    ]) {
      expect(RegExp('\\b$anahtar\\b').hasMatch(kaynak), isFalse,
          reason: anahtar);
    }
  });
}

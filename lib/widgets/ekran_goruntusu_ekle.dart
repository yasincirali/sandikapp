import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/l10n.dart';
import '../providers/bulk_cart_provider.dart';
import '../services/crash_reporter.dart';
import '../services/ekstre/ekran_goruntusu.dart';
import '../services/ekstre/ekran_goruntusu_sepeti.dart';
import '../services/ekstre/ekran_okuyucu.dart';
import '../services/ekstre/ekstre_tablosu.dart' show EkstreOkumaHatasi;
import '../services/tefas_service.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';

/// Ekran görüntüsünden Toplu Ekle sepetine — iki kapının ortak akışı
/// (Varlık Ekle formundaki "Ekran görüntüsünden" ve Toplu Ekle; 2026-10-19,
/// gerekçe `ekran_goruntusu_sepeti.dart`).
///
/// Birden çok görüntü seçilir, her biri telefonda okunur, aynı varlık
/// görüntüler arasında tekilleşir (`ekranVarliklariniBirlestir`). Ücretsiz
/// ve bayraksız: yeni kullanıcının ilk kapısı. Sonuç tek bildirimle
/// söylenir; maliyeti okunamayan satır sepette "maliyet sonra girilecek".
///
/// Sepete en az bir kalem girdiyse `true` (çağıran Toplu Ekle'yi açar).
Future<bool> ekranGoruntusundenSepete(
  BuildContext context,
  WidgetRef ref,
) async {
  final l = context.l10n;
  final List<XFile> gorseller;
  try {
    gorseller = await ImagePicker().pickMultiImage();
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'ekran_goruntusu_sepete.secici');
    if (context.mounted) showAppError(context, e);
    return false;
  }
  if (gorseller.isEmpty || !context.mounted) return false;
  try {
    final fonlar = await _fonListesiSessiz();
    final gruplar = <List<EkranVarligi>>[];
    for (final g in gorseller) {
      final hucreler = await ekranGoruntusunuOku(await g.readAsBytes());
      gruplar.add(ekranGoruntusunuAnla(hucreler, fonlar: fonlar));
    }
    final sonuc = ekranVarliklarindanSepet(ekranVarliklariniBirlestir(gruplar));
    if (!context.mounted) return false;
    final sepet = ref.read(bulkCartProvider.notifier);
    for (final k in sonuc.kalemler) {
      sepet.add(k);
    }
    final mesaj = <String>[
      if (sonuc.kalemler.isEmpty)
        l.importScreenshotNone
      else
        l.bulkScreenshotAdded(sonuc.kalemler.length),
      if (sonuc.maliyetiSonraGirilecek > 0)
        l.bulkScreenshotCostLater(sonuc.maliyetiSonraGirilecek),
      if (sonuc.adediOkunamayan.isNotEmpty)
        l.bulkScreenshotNoQuantity(sonuc.adediOkunamayan.join(', ')),
      for (final ad in sonuc.taninmayanFonlar) l.importFundNotRecognized(ad),
    ];
    sandikSnack(
      context,
      mesaj.join('\n'),
      kind: sonuc.kalemler.isEmpty
          ? SandikSnackKind.warning
          : SandikSnackKind.success,
    );
    return sonuc.kalemler.isNotEmpty;
  } catch (e, st) {
    if (e is! EkstreOkumaHatasi) {
      CrashReporter.report(e, st, reason: 'ekran_goruntusu_sepete.okuma');
    }
    if (context.mounted) showAppError(context, e);
    return false;
  }
}

/// Görüntüdeki fon kodlarını/adlarını tanımak için TEFAS listesi; alınamazsa
/// yalnız BIST hisseleri tanınır (içe aktarma ekranıyla aynı karar).
Future<List<({String kod, String unvan})>> _fonListesiSessiz() async {
  try {
    final fonlar = await TefasService.instance.fetchAllFunds();
    return [for (final f in fonlar) (kod: f.code, unvan: f.name)];
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'ekran_goruntusu_sepete.fon_listesi');
    return const [];
  }
}

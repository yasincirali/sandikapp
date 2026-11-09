import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../services/tefas_service.dart';
import '../theme/sandik.dart';
import '../utils/fon_fiyat_gunu.dart';

/// Fon mu (fiyatı TEFAS'tan, günde bir kez gelen tür)? BES de TEFAS
/// fiyatıyla fiyatlanır.
bool fonFiyatliMi(AssetType tur) =>
    tur == AssetType.fon || tur == AssetType.bes;

/// Fonun son fiyatının günü — TefasService'ten; bilinmiyorsa null.
DateTime? fonFiyatGunu(String kod) => TefasService.instance.fiyatTarihi(kod);

/// Uzun biçim: "Fiyat 30 Eki", iki gün ve üstünde gün adıyla
/// "Fiyat 30 Eki (Cuma)" (hafta sonu/tatilde "hangi gün" sorusunun cevabı).
/// Bugünün fiyatıysa null.
String? fonFiyatGunuUzun(BuildContext context, DateTime? tarih,
    {DateTime? simdi}) {
  final fark = fonFiyatGunFarki(tarih, simdi ?? DateTime.now());
  if (fark == null) return null;
  final l = context.l10n;
  final t = tarih!.toLocal();
  final bicim = fark >= 2 ? 'd MMM (EEEE)' : 'd MMM';
  return l.fundPriceDate(DateFormat(bicim, l.localeName).format(t));
}

/// Kısa biçim (dar satır): "dünkü fiyat", bir hafta içinde "Cuma fiyatı",
/// daha eskiyse "23 Eki fiyatı". Bugünün fiyatıysa null.
String? fonFiyatGunuKisa(BuildContext context, DateTime? tarih,
    {DateTime? simdi}) {
  final fark = fonFiyatGunFarki(tarih, simdi ?? DateTime.now());
  if (fark == null) return null;
  final l = context.l10n;
  if (fark == 1) return l.fundPriceYesterday;
  final t = tarih!.toLocal();
  final gun = DateFormat(fark < 7 ? 'EEEE' : 'd MMM', l.localeName).format(t);
  return l.fundPriceOfDay(gun);
}

/// Varlık sayfası / varlık detayında "GÜNCEL FİYAT" etiketinin yanındaki
/// gri not. Bugünün fiyatıysa ya da gün bilinmiyorsa yer kaplamaz.
///
/// Renk gri (text36): uyarı değil bilgi — fon için dünün fiyatı olağan
/// durumdur (kripto gecikmesi gibi arıza değil). Anlam metinde, renkte değil.
class FonFiyatGunuEtiketi extends StatelessWidget {
  const FonFiyatGunuEtiketi({super.key, required this.tarih, this.simdi});

  final DateTime? tarih;

  /// Test için sabit saat.
  final DateTime? simdi;

  @override
  Widget build(BuildContext context) {
    final metin = fonFiyatGunuUzun(context, tarih, simdi: simdi);
    if (metin == null) return const SizedBox.shrink();
    return Text(
      '· $metin',
      key: const ValueKey('fonFiyatGunu'),
      // Büyük yazıda etiketin yanında iki satıra sarar; kırpılmaz.
      maxLines: 2,
      semanticsLabel: metin,
      style: context.t.labelSmall?.copyWith(color: context.c.text36),
    );
  }
}

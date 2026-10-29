import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/price_alert.dart';
import '../models/seviye_alarmi.dart';
import '../models/yuzde_alarmi.dart';
import 'price_alert_provider.dart';
import 'seviye_alarmi_provider.dart';
import 'yuzde_alarmi_provider.dart';

/// Bir sembolün dört alarm türü birlikte (Ar-Ge 29 Eki 16:45 #1, yasin
/// "yap").
///
/// Neden tek yer: her yüzey kendi sayımını yapıyordu ve her yeni tür bir
/// yüzeyi unutuyordu. Yüzde alarmı (0169) takip çanına girmişti ama varlık
/// şeridi ve Portföy rozeti onu görmüyordu; gösterge/çizgi alarmı (0170)
/// şeride girmişti ama rozete girmemişti. Aynı varlık bir ekranda "alarm
/// var", ötekinde "yok" diyordu. Yeni tür buraya eklenir, yüzeyler kendiliğinden
/// görür.
///
/// Veri zaten yüklenmiş provider'lardan; yeni sunucu çağrısı yok. Yüklenmemiş
/// liste boş sayılır (uydurma sayı yok, yüklendiğinde yeniden çizilir).
class SembolAlarmlari {
  final List<PriceAlert> fiyat;
  final List<YuzdeAlarmi> yuzde;
  final List<GostergeAlarmi> gosterge;
  final List<CizimAlarmi> cizim;

  const SembolAlarmlari({
    this.fiyat = const [],
    this.yuzde = const [],
    this.gosterge = const [],
    this.cizim = const [],
  });

  /// Bekleyen (kurulu ve henüz sönmemiş) alarm sayısı, dört tür birlikte.
  /// Bugün çalmış yüzde alarmı da sayılır: yarın yine nöbette.
  int get aktif =>
      fiyat.where((a) => a.isActive).length +
      yuzde.where((a) => a.isActive).length +
      gosterge.where((a) => a.isActive).length +
      cizim.where((a) => a.isActive).length;

  bool get bos =>
      fiyat.isEmpty && yuzde.isEmpty && gosterge.isEmpty && cizim.isEmpty;
}

final sembolAlarmlariProvider =
    Provider.family<SembolAlarmlari, String>((ref, sembol) {
  List<T> suz<T>(List<T>? hepsi, String Function(T) s) => [
        for (final a in hepsi ?? <T>[])
          if (s(a) == sembol) a
      ];
  return SembolAlarmlari(
    fiyat: ref.watch(symbolAlertsProvider(sembol)),
    yuzde: suz(ref.watch(yuzdeAlarmlariProvider).valueOrNull,
        (YuzdeAlarmi a) => a.symbol),
    gosterge: suz(ref.watch(gostergeAlarmlariProvider).valueOrNull,
        (GostergeAlarmi a) => a.symbol),
    cizim: suz(ref.watch(cizimAlarmlariProvider).valueOrNull,
        (CizimAlarmi a) => a.symbol),
  );
});

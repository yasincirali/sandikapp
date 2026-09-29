import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/fon_karnesi.dart';
import '../services/remote_config_service.dart';
import '../services/tefas_service.dart';

/// Fon karnesi (F4) bayrağı — `fund_report_card_enabled`.
///
/// Provider olarak sarıldı ki widget testi bayrağı açık/kapalı override
/// edebilsin; `RemoteConfigService` tekil nesnesi testte debug varsayılanına
/// (açık) sabit kalırdı.
final fonKarnesiAcikProvider =
    Provider<bool>((ref) => RemoteConfigService.instance.fundReportCardEnabled);

/// TEFAS fon kataloğu — fon araması ve karşılaştırma seçicisinin KULLANDIĞI
/// aynı çağrı (`fetchAllFunds`); yeni bir uç nokta ya da istek türü yok.
///
/// `fetchAllFunds` önbellek öncelikli: RAM'de 1 saatten, diskte 24 saatten
/// taze liste varsa ağa çıkmaz. Liste yoksa ağ turu olur — fon aramasını
/// açan kullanıcının zaten yaşadığı istekle aynı.
///
/// autoDispose + 1 saat tutma (servisin RAM TTL'iyle aynı): portföyde
/// kartları açıp kapatmak her seferinde listeyi yeniden süzmesin. BOŞ liste
/// (ağ hatası) tutulmaz; sonraki açılış yeniden dener.
final fonKatalogProvider =
    FutureProvider.autoDispose<List<TefasFund>>((ref) async {
  final liste = await TefasService.instance.fetchAllFunds();
  if (liste.isNotEmpty) {
    final link = ref.keepAlive();
    final zamanlayici = Timer(const Duration(hours: 1), link.close);
    ref.onDispose(zamanlayici.cancel);
  }
  return liste;
});

/// Bir fonun karnesi. Hesap `build()` dışında, burada bir kez yapılır.
///
/// Katalog yüklenirken `AsyncLoading`, karne kurulamıyorsa `data(null)`.
/// Hata sessizdir (`data(null)` gibi davranılır, bkz. widget): karne ek
/// bilgidir, fiyatı ya da pozisyonu etkilemez; `fetchAllFunds` hatayı zaten
/// kendi içinde yutup boş liste döndürür.
final fonKarnesiProvider = Provider.autoDispose
    .family<AsyncValue<FonKarnesi?>, String>((ref, fonKodu) => ref
        .watch(fonKatalogProvider)
        .whenData((liste) => fonKarnesi(fonKodu, liste)));

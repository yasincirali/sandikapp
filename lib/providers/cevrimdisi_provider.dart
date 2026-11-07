import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';

/// "İnternet yok · fiyatlar 14:32'deki hâli" şeridinin durumu (Ar-Ge
/// 7 Kas 08:03 #3).
///
/// Neden ayrı sağlayıcı: bağlantı kopunca uyarılar dağınıktı (ekran ekran
/// farklı hata metni); metroda/uçakta kullanıcı "uygulama bozuk" sanıyordu.
/// Karar tek yerde: son fiyat turu ağ hatasıyla bittiyse durum dolu, ilk
/// yanıt alınan turda kendiliğinden `null`. Ana sayfa ve Portföy aynı
/// durumu okur. Yeni paket yok (connectivity eklenmedi): sinyal fiyat
/// turunun kendisi — uygulamanın gerçekten ağa çıktığı an.
class CevrimdisiDurum {
  const CevrimdisiDurum({this.sonFiyat});

  /// Ekrandaki fiyatların son başarılı güncellemesi; bilinmiyorsa `null`
  /// (şerit saat yazmaz — uydurma saat yok).
  final DateTime? sonFiyat;
}

class CevrimdisiNotifier extends Notifier<CevrimdisiDurum?> {
  @override
  CevrimdisiDurum? build() => null;

  /// Fiyat turu ağ hatasıyla bitti.
  void agHatasi({DateTime? sonFiyat}) =>
      state = CevrimdisiDurum(sonFiyat: sonFiyat);

  /// Turda en az bir yanıt alındı → şerit kalkar.
  void baglandi() {
    if (state != null) state = null;
  }
}

final cevrimdisiProvider =
    NotifierProvider<CevrimdisiNotifier, CevrimdisiDurum?>(
        CevrimdisiNotifier.new);

/// Bir fiyat turunun bağlantı kararı, tur öncesi/sonrası sayaç farkından
/// (`PriceService.agSayaci`): yanıt varsa bağlı (`false`), yanıt yok ama
/// ağ hatası varsa kopuk (`true`), ağa hiç çıkılmadıysa (hepsi önbellekten)
/// karar yok (`null`) — önceki durum korunur.
bool? turBaglantiKarari({required int hata, required int yanit}) {
  if (yanit > 0) return false;
  if (hata > 0) return true;
  return null;
}

/// Ekrandaki fiyatların son güncellenme anı: ağdan fiyat alan (elle fiyatlı
/// olmayan, sembollü) aktif lotların en yeni `lastUpdated`'ı. Elle fiyatın
/// tarihi "fiyatlar güncellendi" demek değil, sayılmaz.
DateTime? sonFiyatZamani(Iterable<Asset> assets) {
  DateTime? enYeni;
  for (final a in assets) {
    if (!a.isActive || a.isManualPrice || a.ticker.isEmpty) continue;
    final t = a.lastUpdated;
    if (t == null) continue;
    if (enYeni == null || t.isAfter(enYeni)) enYeni = t;
  }
  return enYeni;
}

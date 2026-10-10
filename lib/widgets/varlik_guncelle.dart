import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart';
import '../screens/add_asset_screen.dart';
import '../screens/paywall_screen.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
import 'delete_asset_dialog.dart' show sahipsizAlarmlariSor;

export '../services/varlik_yeniden_kur.dart' show silVeYenidenEkle;

/// "Varlığı güncelle": yanlış girilmiş bir varlığı tek kayıtla düzeltmek.
///
/// ## Ne yapar (yasin, 2026-10-10)
/// *"Eklenen varlığın direkt düzeltme amacıyla … varlık güncelleme
/// eklemeliyiz, ama burada var olan adımlı hareketlerin kaybolacağı ve o
/// varlıkta nihai kaydın güncellenecek kayıt kalacağını iletmeliyiz. Bu
/// güncellemenin bizim tarafta varlığı silme ve yeniden ekleme gibi
/// davranması gerekmektedir."*
///
/// Bu yüzden yeni bir sunucu yolu YOK: pozisyon Sil'in yaptığı gibi
/// yumuşak silinir (`deletePositionLots`: damga + tek "Silindi" satırı),
/// ardından Varlık Ekle'nin yaptığı gibi tek alım yazılır (`addAsset`).
/// Bağımlı her şey (ortak görünümü, Zirve'nin geriye tarihli kayıt kuralı,
/// birikim serisi, takip listesi, hareket geçmişi) bu iki işlemi zaten
/// tanıyor; güncelleme onlara "sildi, sonra ekledi" diye görünür. Ayrı bir
/// "düzenleme" anlamı icat etmek bu yüzeylerin her birinde yeni bir kural
/// isterdi. Tek fark geri alma: ekleme düşerse silme geri alınır
/// (`silVeYenidenEkle`) — kullanıcı varlığını kaybetmez.
///
/// ## Kim görür
/// Bayrak `goz_alici` (varsayılan kapalı; yeni bayrak açılmadı, yasin
/// 2026-10-09 "aşırı fazla flag olmasın"). Yeni özellikler Premium'dur
/// (yasin 2026-10-10): paywall açıkken ücretsiz kullanıcı eylemi kilitli
/// görür ve paywall'a gider; paywall kapalıyken Premium özellikleri gibi
/// yalnız admin görür (tek anahtar kuralı, `premiumOzellikleriGorunur`).
enum VarlikGuncellemeDurumu { gizli, acik, kilitli }

/// Görünürlük kararı — SAF (test: `varlik_guncelle_test`).
VarlikGuncellemeDurumu varlikGuncellemeDurumu({
  required bool bayrak,
  required bool demo,
  required bool paywall,
  required bool admin,
  required bool premiumKilitli,
}) {
  if (demo || !bayrak) return VarlikGuncellemeDurumu.gizli;
  if (!paywall && !admin) return VarlikGuncellemeDurumu.gizli;
  return premiumKilitli
      ? VarlikGuncellemeDurumu.kilitli
      : VarlikGuncellemeDurumu.acik;
}

final varlikGuncellemeProvider = Provider<VarlikGuncellemeDurumu>((ref) {
  ref.watch(rcEtkinlesmeProvider);
  return varlikGuncellemeDurumu(
    bayrak: RemoteConfigService.instance.gozAlici,
    demo: DemoModu.aktif,
    paywall: ref.watch(paywallVisibleProvider),
    admin: ref.watch(isPushAdminProvider).valueOrNull == true,
    premiumKilitli: ref.watch(premiumKilitliProvider),
  );
});

/// Bu pozisyon güncellenebilir mi.
///
/// · Sözleşmeli lot (mevduat, BES) genel formdan girilmez; dönemleri ve
///   birim değeri sözleşmeden gelir. Tek kayda indirmek sözleşmeyi koparırdı.
/// · Lotları birden çok portföye dağılmış ("Tümü" görünümünde karışık)
///   pozisyon tek kayda indirilirse portföy ayrımı kaybolur. Kullanıcı önce
///   portföyünü seçip o görünümden günceller.
bool varlikGuncellenebilir(Asset gorunum, List<Asset> lotlar) =>
    !gorunum.portfoyKarisik &&
    !gorunum.type.sozlesmeli &&
    !lotlar.any((l) => l.sozlesmeId != null);

/// Portföy kaydırması ve varlık ekranının üst çubuğu bunu çağırır.
///
/// Kilitliyse paywall; değilse Varlık Ekle formu "güncelle" kipinde, lotlar
/// [lotlar] ile açılır. Form kayıttan sonra kapanınca, sembol değiştiyse
/// sahipsiz kalan alarmlar Sil'deki gibi sorulur (aynı fonksiyon).
Future<void> varligiGuncelleAkisi(
  BuildContext context,
  WidgetRef ref, {
  required Asset gorunum,
  required List<Asset> lotlar,
}) async {
  if (DemoModu.yazmaKapisi('varlik_guncelle')) return;
  final durum = ref.read(varlikGuncellemeProvider);
  if (durum == VarlikGuncellemeDurumu.gizli) return;
  if (durum == VarlikGuncellemeDurumu.kilitli) {
    await PaywallScreen.show(context, source: 'varlik_guncelle');
    return;
  }
  final silinecek = [
    for (final l in lotlar)
      if (!l.isDeleteLog) l,
  ];
  if (silinecek.isEmpty) return;
  final sonuc = await pushGuarded<Object>(
    context,
    adaptiveRoute(
      builder: (_) => AddAssetScreen(
        editingAsset: gorunum,
        yerineGecenLotlar: silinecek,
      ),
    ),
  );
  if (sonuc == null || !context.mounted) return;
  await sahipsizAlarmlariSor(context, ref, silinecek, gorunum.name);
}

/// Formun üstündeki kalıcı uyarı: kaydetmeden ÖNCE ne olacağını söyler.
/// Kayıt anındaki onay ([AddAssetScreen]) aynı şeyi sayıyla tekrarlar.
class VarlikGuncelleUyarisi extends StatelessWidget {
  const VarlikGuncelleUyarisi({super.key, required this.hareketSayisi});

  final int hareketSayisi;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(SandikSpace.smd),
        decoration: BoxDecoration(
          color: context.c.amberFill.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: context.c.amberFill.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Renk tek başına anlam taşımaz: ikon + başlık da "uyarı" der.
            Icon(Icons.info_outline_rounded,
                size: 20, color: context.c.amberText),
            const SizedBox(width: SandikSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.varlikGuncelleUyariBaslik,
                    style: context.t.titleSmall?.copyWith(
                        color: context.c.text90, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: SandikSpace.xs),
                  Text(
                    l.varlikGuncelleUyariGovde(hareketSayisi),
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text90, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

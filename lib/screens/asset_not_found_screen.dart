import 'package:flutter/material.dart';

import '../theme/sandik.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_error_view.dart';
import '../l10n/l10n.dart';

/// Dışarıdan gelen `sandik://asset/<id>` bağlantısının hedefi bu hesabın
/// portföyünde yoksa gösterilir.
///
/// Neden sessiz geçilmiyor: bağlantı dış kaynaktan (mesaj, tarayıcı) gelir;
/// kullanıcı bir şeye dokundu ve hiçbir şey olmazsa "uygulama bozuk" sanır.
/// Push bildirimi yolu ise sessiz kalır — silinmiş varlığın eski bildirimi
/// için hata ekranı açmak yanıltıcı olur (`openAssetPerformance` yorumu).
///
/// Metin bilerek "sana ait olmayabilir" diyor: id başka bir kullanıcıya ait
/// olsa da sunucu RLS ile zaten vermez; istemci yalnızca "portföyde yok"u
/// bilir. Hangi durum olduğunu söyleyemeyiz ve söylememeliyiz — varlık
/// id'lerinin varlığı hakkında bilgi sızdırmamak için.
class AssetNotFoundScreen extends StatelessWidget {
  const AssetNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.background,
      appBar: SandikAppBar(title: context.l10n.assetNotFound, transparent: true),
      body: const SandikErrorView(error: VarlikBulunamadiHatasi()),
    );
  }
}

/// `friendlyError` Türkçe karakter içeren kısa mesajı olduğu gibi geçirir;
/// bu sınıf o kuralı kullanır. Ham `$e` gösterimi değildir — mesaj sabittir.
class VarlikBulunamadiHatasi implements Exception {
  const VarlikBulunamadiHatasi();

  @override
  String toString() =>
      'Bu varlık portföyünde yok. Bağlantı eski olabilir ya da varlık sana '
      'ait olmayabilir.';
}

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';

/// iOS sayı klavyesinin üstünde "Sonraki / Bitti" çubuğu (2026-11-11).
///
/// ## Neden
/// iOS'un ondalık/sayı klavyesinde Enter/Bitti tuşu yok: kullanıcı klavyeyi
/// kapatmak için boşluğa dokunmak zorunda ([KlavyeKapatici]), alt sayfalarda
/// klavye alttaki Kaydet'i örtüyor, birden çok tutar alanında bir sonrakine
/// geçmenin yolu yok. Sistem uygulamalarının çözümü klavye üstü aksesuar
/// çubuğu; Android klavyesinde Bitti/İleri tuşu zaten var, orada hiçbir şey
/// değişmez.
///
/// ## Neden kökte tek katman, alan alan sarmalayıcı değil
/// Sayı alanı 10 dosyaya dağılmış (Varlık Ekle tutarları, hızlı düzelt,
/// alarm, hedef, temettü, sözleşme, kısmi aktarım, veri kalitesi, OTP) ve
/// her yeni alana sarmalayıcı yazmak unutulur. Odaktaki düğümün bağlamı
/// `EditableText`'in İÇİNDE (alanın `Focus`'u onun çocuğu), dolayısıyla
/// klavye türü `findAncestorWidgetOfExactType<EditableText>()` ile kesin
/// okunur — `TextField`, `TextFormField`, `CupertinoTextField` hepsi aynı
/// yoldan geçer. `MaterialApp.builder` Navigator'ı sardığı için alt sayfalar
/// ve diyaloglar dahil her yüzey kapsanır. Navigator'ın üstünde `Overlay`
/// yok; çubuk bir `Stack` katmanıdır.
///
/// ## Neden yalnız klavye görünürken
/// `viewInsets.bottom == 0` iken (iPad donanım klavyesi, klavye inmiş ama
/// odak kalmış) ekranın dibinde yüzen bir çubuk anlamsız; gösterilmez.
///
/// ## Neden içeriğin `viewInsets`'i çubuk kadar büyütülür
/// Çubuk klavyenin üstüne biner; içerik bunu bilmezse Scaffold/alt sayfa
/// yalnız klavye kadar küçülür ve dipteki Kaydet çubuğun ALTINDA kalır —
/// çözmeye çalıştığımız sorun geri gelir. İçeriğe "klavye çubuk kadar daha
/// uzun" denir; her ekran kendi mevcut klavye kaçınmasıyla doğru yere çıkar.
/// Çubuk yüksekliği yazı boyutuna göre değiştiği için sabit yazılmaz,
/// çizildikten sonra ölçülür (ilk kare klavye animasyonunun içinde kalır).
///
/// ## Neden "Sonraki" kendi sırasını kurar
/// `FocusScope.nextFocus` sıradaki HER odaklanabilir öğeye gider (düğme,
/// anahtar) ve sonda başa sarar; klavye çubuğundaki "Sonraki"nin anlamı ise
/// "bir sonraki giriş alanı". Aynı kapsamdaki düzenlenebilir alanlar okuma
/// sırasına (yukarıdan aşağı, soldan sağa) dizilir; sonda olan alanda düğme
/// gizlenir, başa sarmaz.
class SayiKlavyesiKatmani extends StatefulWidget {
  const SayiKlavyesiKatmani({super.key, required this.child});

  final Widget child;

  @override
  State<SayiKlavyesiKatmani> createState() => _SayiKlavyesiKatmaniState();
}

class _SayiKlavyesiKatmaniState extends State<SayiKlavyesiKatmani> {
  final _cubukAnahtari = GlobalKey();
  double _cubukBoyu = 0;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_odakDegisti);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_odakDegisti);
    super.dispose();
  }

  void _odakDegisti() {
    if (mounted) setState(() {});
  }

  static bool _sayiAlaniMi(FocusNode? dugum) {
    final alan = _alanOf(dugum);
    if (alan == null || alan.readOnly) return false;
    // `numberWithOptions(decimal/signed)` aynı `index`'i taşır; eşitlik
    // karşılaştırması seçenekleri de karşılaştırdığı için kullanılmaz.
    return alan.keyboardType.index == TextInputType.number.index;
  }

  static EditableText? _alanOf(FocusNode? dugum) {
    final ctx = dugum?.context;
    if (ctx == null || !ctx.mounted) return null;
    return ctx.findAncestorWidgetOfExactType<EditableText>();
  }

  /// Aynı kapsamda, okuma sırasında odaktakinden sonra gelen ilk
  /// düzenlenebilir alan; yoksa `null` ("Sonraki" gizlenir).
  static FocusNode? _sonrakiAlan(FocusNode odak) {
    final kapsam = odak.nearestScope;
    if (kapsam == null) return null;
    final alanlar = [
      for (final d in kapsam.traversalDescendants)
        if (d.canRequestFocus &&
            (identical(d, odak) || (_alanOf(d)?.readOnly == false)))
          d,
    ]..sort((a, b) {
        final ra = a.rect, rb = b.rect;
        // Aynı satırdaki alanlar (yan yana adet/fiyat) soldan sağa.
        if ((ra.top - rb.top).abs() > SandikSpace.sm) {
          return ra.top.compareTo(rb.top);
        }
        return ra.left.compareTo(rb.left);
      });
    final i = alanlar.indexOf(odak);
    return (i >= 0 && i + 1 < alanlar.length) ? alanlar[i + 1] : null;
  }

  void _boyuOlc() {
    final kutu = _cubukAnahtari.currentContext?.findRenderObject();
    if (kutu is! RenderBox || !kutu.hasSize) return;
    final boy = kutu.size.height;
    if (boy != _cubukBoyu && mounted) setState(() => _cubukBoyu = boy);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final odak = FocusManager.instance.primaryFocus;
    final goster = Theme.of(context).platform == TargetPlatform.iOS &&
        mq.viewInsets.bottom > 0 &&
        _sayiAlaniMi(odak);
    if (!goster) return widget.child;

    final sonraki = _sonrakiAlan(odak!);
    SchedulerBinding.instance.addPostFrameCallback((_) => _boyuOlc());
    return Stack(
      children: [
        Positioned.fill(
          child: MediaQuery(
            data: mq.copyWith(
              viewInsets: mq.viewInsets
                  .copyWith(bottom: mq.viewInsets.bottom + _cubukBoyu),
            ),
            child: widget.child,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: mq.viewInsets.bottom,
          child: SayiKlavyesiCubugu(
            key: _cubukAnahtari,
            onSonraki: sonraki?.requestFocus,
            onBitti: () => FocusManager.instance.primaryFocus?.unfocus(),
          ),
        ),
      ],
    );
  }
}

/// Çubuğun görünüşü; katmandan ayrı ki HIG vitrinine tek başına girsin.
/// `onSonraki` `null` ise "Sonraki" hiç çizilmez (sonraki alan yok):
/// pasif düğme "neden basamıyorum" sorusu doğurur, iOS da gizler.
class SayiKlavyesiCubugu extends StatelessWidget {
  const SayiKlavyesiCubugu({super.key, this.onSonraki, required this.onBitti});

  final VoidCallback? onSonraki;
  final VoidCallback onBitti;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    final stil = TextButton.styleFrom(minimumSize: SandikTouch.minSize);
    // Çubuğun boş yerine dokunuş kökteki [KlavyeKapatici]'ya gitmesin:
    // düğmeyi ıskalayan parmak klavyeyi beklenmedik biçimde kapatmasın.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: () {},
      child: Material(
        color: c.surface1,
        child: DecoratedBox(
          decoration:
              BoxDecoration(border: Border(top: BorderSide(color: c.hairline))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SandikSpace.sm),
            child: Row(
              children: [
                if (onSonraki != null)
                  TextButton(
                    style: stil,
                    onPressed: onSonraki,
                    child: Text(l10n.klavyeSonraki,
                        style: context.t.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w400)),
                  ),
                const Spacer(),
                TextButton(
                  style: stil,
                  onPressed: onBitti,
                  child: Text(l10n.klavyeBitti,
                      style: context.t.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

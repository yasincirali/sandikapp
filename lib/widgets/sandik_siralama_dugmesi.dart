import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';

/// Sıralama seçicisinin bir satırı: değer, başlık, açıklama, ikon.
class SandikSiralamaSecenegi<T> {
  const SandikSiralamaSecenegi({
    required this.deger,
    required this.baslik,
    required this.ikon,
    this.altBaslik,
  });

  final T deger;
  final String baslik;
  final String? altBaslik;
  final IconData ikon;
}

/// Listenin sırasını seçtiren TEK ortak düğme + alt sayfa
/// (`docs/TASARIM_DILI.md` §4 "bir iş = bir bileşen").
///
/// Neden (Ar-Ge 2026-10-25 12:45 #3, kabul 13:15 #2): Portföy
/// (`_SortButton`/`_SortSheet`) ile takip listesi
/// (`_SiralamaDugmesi`/`_SiralamaSayfasi`) aynı işi iki kopyayla yapıyordu;
/// görünüm, metin ve davranış ayrı ayrı bakım istiyordu. Yeni bir listeye
/// sıralama gelirse (Zirve, takvim) bu bileşen kullanılır.
///
/// Kayan segment (`SandikSegment`) DEĞİL: seçim ekranın ne gösterdiğini
/// değiştirmez, yalnız sırasını; 3–6 seçenek liste başında yer kaplamasın.
///
/// İki biçim, ikisi de geçişten ÖNCEKİ görünümü birebir korur (kullanıcının
/// alışkanlığı ve tanıtım turu etkilenmesin):
/// - [SandikSiralamaDugmesi.ikon] — üst çubukta 44 pt ikon kutusu; seçim
///   varsayılandan farklıysa amber vurgulu (Portföy). Sayfası sık satırlı.
/// - [SandikSiralamaDugmesi.etiketli] — ikon + seçili sıranın adı (takip
///   listesi başlık satırı).
///
/// Davranış ikisinde ortak: sayfayı kendisi açar ([showSandikSheet]),
/// seçili satır amber + onay işareti (yalnız renk değil) ve ekran okuyucuya
/// "seçili", aynı satıra dokunmak hiçbir şey değiştirmez, değişen seçim
/// `selection` titreşimi verir ve [onSec] sayfa kapandıktan sonra çağrılır.
class SandikSiralamaDugmesi<T> extends StatelessWidget {
  /// Üst çubuk ikon kutusu. [varsayilan] dışındaki seçim kutuyu vurgular
  /// ki liste "olağan" sırada değilken bu görünsün.
  const SandikSiralamaDugmesi.ikon({
    super.key,
    required this.secenekler,
    required this.secili,
    required this.onSec,
    required this.semantikEtiket,
    required T this.varsayilan,
  }) : _ikon = true;

  /// İkon + seçili seçeneğin başlığı.
  const SandikSiralamaDugmesi.etiketli({
    super.key,
    required this.secenekler,
    required this.secili,
    required this.onSec,
    required this.semantikEtiket,
  })  : varsayilan = null,
        _ikon = false;

  final List<SandikSiralamaSecenegi<T>> secenekler;
  final T secili;
  final ValueChanged<T> onSec;

  /// Ekran okuyucu etiketi (ör. "Varlıkları sırala", "Sıralama: Benim sıram").
  final String semantikEtiket;
  final T? varsayilan;
  final bool _ikon;

  SandikSiralamaSecenegi<T> get _seciliSecenek => secenekler
      .firstWhere((s) => s.deger == secili, orElse: () => secenekler.first);

  void _ac(BuildContext context) {
    showSandikSheet<void>(
      context: context,
      backgroundColor: context.c.surface1,
      shape: _ikon
          ? const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop)
          : null,
      builder: (sayfa) => _SiralamaSayfasi<T>(
        secenekler: secenekler,
        secili: secili,
        yogun: _ikon,
        onSec: (d) {
          Navigator.pop(sayfa);
          if (d == secili) return;
          SandikHaptic.selection.perform();
          onSec(d);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (_ikon) {
      final vurgulu = secili != varsayilan;
      return CupertinoButton(
        minimumSize: SandikTouch.minSize,
        padding: EdgeInsets.zero,
        onPressed: () => _ac(context),
        child: Container(
          width: SandikTouch.min,
          height: SandikTouch.min,
          decoration: BoxDecoration(
            color: vurgulu ? c.amberFill.withValues(alpha: 0.15) : c.overlay,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(
              color: vurgulu ? c.amberFill.withValues(alpha: 0.5) : c.overlay,
            ),
          ),
          child: Icon(
            Icons.sort_rounded,
            semanticLabel: semantikEtiket,
            size: SandikSpace.lgs,
            color: vurgulu ? c.amberText : c.text58,
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: semantikEtiket,
      excludeSemantics: true,
      child: CupertinoButton(
        minimumSize: SandikTouch.minSize,
        padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xs),
        onPressed: () => _ac(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, size: SandikSpace.md, color: c.text58),
            const SizedBox(width: SandikSpace.xs),
            Text(
              _seciliSecenek.baslik,
              style: context.t.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600, color: c.text58),
            ),
          ],
        ),
      ),
    );
  }
}

/// [yogun]: Portföy'ün sık sayfası (başlık altı çizgi, 18 pt ikon, seçili
/// satır zemini). Kapalıyken takip listesinin sayfası. Fark yalnız görünüm;
/// iki ekran geçişten önceki hâliyle aynı görünsün diye korundu.
class _SiralamaSayfasi<T> extends StatelessWidget {
  const _SiralamaSayfasi({
    required this.secenekler,
    required this.secili,
    required this.yogun,
    required this.onSec,
  });

  final List<SandikSiralamaSecenegi<T>> secenekler;
  final T secili;
  final bool yogun;
  final ValueChanged<T> onSec;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ikonBoyu = yogun ? 18.0 : null;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SandikSpace.lgs,
                SandikSpace.lgs, SandikSpace.lgs, SandikSpace.xs),
            child: Text(
              context.l10n.sortCriterion,
              style: context.t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: c.text58),
            ),
          ),
          if (yogun) Divider(color: c.hairline, height: 1),
          for (final s in secenekler)
            ListTile(
              dense: yogun,
              minTileHeight: SandikTouch.min,
              // `selected` ekran okuyucuya "seçili" der; zemin rengi
              // `selectedTileColor`'dan (seçiliyken `tileColor` okunmaz).
              selected: s.deger == secili,
              selectedTileColor:
                  yogun ? c.amberFill.withValues(alpha: 0.07) : null,
              leading: Icon(s.ikon,
                  size: ikonBoyu,
                  color: s.deger == secili ? c.amberText : c.text58),
              title: Text(
                s.baslik,
                style: context.t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: s.deger == secili ? c.amberText : c.text90),
              ),
              subtitle: s.altBaslik == null
                  ? null
                  : Text(
                      s.altBaslik!,
                      style: context.t.bodySmall?.copyWith(color: c.text36),
                    ),
              // Seçili bilgisi yalnız renkte kalmasın: onay işareti.
              trailing: s.deger == secili
                  ? Icon(Icons.check_rounded,
                      color: c.amberText, size: ikonBoyu)
                  : null,
              onTap: () => onSec(s.deger),
            ),
          const SizedBox(height: SandikSpace.sm),
        ],
      ),
    );
  }
}

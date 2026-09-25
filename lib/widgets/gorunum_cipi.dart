// Görünüm çipi — Ben / ortak / Birlikte, toplam kartının başlığında.
//
// 2026-09-21 sadeleştirme: `ModernTabSelector` ana ekranda kendi satırını
// tutuyordu; aynı seçim artık hero kartın başlığında tek çip. Üç sekmelik
// seçici 320pt'te başlıkla yan yana sığmazdı; çip + alt sayfa hem sığar hem
// Performans'taki kapsam çipiyle aynı dili konuşur. Anlam ve kimlik
// sözleşmesi ModernTabSelector ile AYNI: '' = Ben, ortak id = ortak,
// null = Birlikte (`home_screen._view`).
//
// 2026-09-21 (2. tur, kullanıcı isteği): "hızlı geçiş, çok daha fazla
// ortak, zekice ve anlaşılır".
//   · Çip avatar taşır: Ben = amber baş harf, ortak = kendi rengiyle baş
//     harf, Birlikte = üst üste iki avatar + kişi sayısı. Kime baktığın
//     yazıyı okumadan belli.
//   · Alt sayfa her görünümün TOPLAMINI yazar — geçmeden görürsün; en
//     üstte Birlikte (herkes), sonra Ben, sonra son kullanılan ortaklar
//     (oturum içi LRU), sonra alfabetik. Altı ve üzeri ortakta arama
//     kutusu; liste kaydırılabilir (ekranın %70'i).
//   · Hızlı geçiş: toplam kartını sağa/sola kaydırmak sıradaki görünüme
//     geçer (Ben → ortaklar → Birlikte → Ben). Çip bunun görünür ipucu,
//     alt sayfada da bir satırlık not var.
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/user_model.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

class GorunumCipi extends StatelessWidget {
  const GorunumCipi({
    super.key,
    required this.partners,
    required this.selectedId,
    required this.onChanged,
    this.toplamlar = const {},
    this.gizli = false,
  });

  final List<AppUser> partners;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  /// Görünüm kimliği → TRY toplam ('' Ben, ortak id, null Birlikte).
  /// Verilmeyen görünümün satırında tutar yazılmaz.
  final Map<String?, double> toplamlar;

  /// Bakiye gizli: tutarlar "••••".
  final bool gizli;

  /// Arama kutusunun göründüğü ortak sayısı eşiği.
  static const int aramaEsigi = 6;

  /// Son kullanılan ortaklar (oturum içi). Kalıcı değil: bir tercih
  /// değil, "az önce baktığım kimdi" hafızası; uygulama yeniden açılınca
  /// alfabetik sıra yeter.
  static final List<String> _sonKullanilan = [];

  static void _kullanildi(String? id) {
    if (id == null || id.isEmpty) return;
    _sonKullanilan
      ..remove(id)
      ..insert(0, id);
    if (_sonKullanilan.length > 8) _sonKullanilan.removeLast();
  }

  /// Test için: LRU'yu sıfırlar.
  @visibleForTesting
  static void hafizayiSifirla() => _sonKullanilan.clear();

  /// Görünüm sırası: Ben → ortaklar (verilen sırayla) → Birlikte.
  static List<String?> sira(List<AppUser> partners) =>
      ['', for (final p in partners) p.id, null];

  /// Kaydırma ile hızlı geçiş: [ileri] sıradaki, değilse önceki görünüm;
  /// uçlarda sarar. Tek ortaksız kullanıcıda (`partners` boş) çip zaten
  /// çizilmez, yine de güvenli: '' → null → ''.
  static String? sonraki(List<AppUser> partners, String? selectedId,
      {required bool ileri}) {
    final s = sira(partners);
    var i = s.indexOf(selectedId);
    if (i < 0) i = 0;
    final n = s.length;
    return s[(i + (ileri ? 1 : -1) + n) % n];
  }

  /// Alt sayfa sırası: Birlikte, Ben, son kullanılanlar, kalan ortaklar
  /// alfabetik. Arama metni ortak adlarını süzer (Ben/Birlikte her zaman).
  @visibleForTesting
  static List<String?> listeSirasi(List<AppUser> partners, String arama) {
    final q = arama.trim().toLowerCase();
    final ortaklar = [
      for (final p in partners)
        if (q.isEmpty || p.displayName.toLowerCase().contains(q)) p,
    ]..sort((a, b) {
        final ia = _sonKullanilan.indexOf(a.id);
        final ib = _sonKullanilan.indexOf(b.id);
        if (ia >= 0 || ib >= 0) {
          if (ia < 0) return 1;
          if (ib < 0) return -1;
          return ia.compareTo(ib);
        }
        return a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase());
      });
    return [null, '', for (final p in ortaklar) p.id];
  }

  static String ilkAd(String ad) {
    final t = ad.trim();
    return t.isEmpty ? '?' : t.split(' ').first;
  }

  static String basHarf(String ad) {
    final t = ad.trim();
    return t.isEmpty ? '?' : t.characters.first.toUpperCase();
  }

  AppUser? _ortak(String? id) {
    for (final p in partners) {
      if (p.id == id) return p;
    }
    return null;
  }

  String _etiket(BuildContext context) =>
      etiketi(context, partners, selectedId);

  /// Görünümün kısa adı: Ben / ilk ad / Birlikte. Kaydırma ipucu da bunu
  /// kullanır ki çip ile kenar etiketi aynı kelimeyi söylesin.
  static String etiketi(
      BuildContext context, List<AppUser> partners, String? id) {
    final l = context.l10n;
    if (id == '') return l.scopeMe;
    if (id == null) return l.scopeTogether;
    for (final p in partners) {
      if (p.id == id) return ilkAd(p.displayName);
    }
    return l.scopeMe;
  }

  /// Ortak avatar rengi — kimlikten türetilir ki aynı kişi her yerde aynı
  /// renkte olsun. Yalnızca tema token'ları.
  static Color ortakRengi(BuildContext context, String id) {
    final c = context.c;
    final renkler = [c.info, c.gain, c.gold, c.loss];
    return renkler[id.hashCode.abs() % renkler.length];
  }

  Future<void> _ac(BuildContext context) async {
    // Sheet `null` döndürünce iptal; Birlikte (id null) ' ' ile taşınır.
    final secim = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (ctx) => _GorunumSayfasi(
        partners: partners,
        selectedId: selectedId,
        toplamlar: toplamlar,
        gizli: gizli,
      ),
    );
    if (secim == null) return; // iptal
    final id = secim == ' ' ? null : secim;
    _kullanildi(id);
    onChanged(id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final etiket = _etiket(context);
    final Widget avatar;
    if (selectedId == null) {
      // Birlikte: ben + ilk ortak üst üste.
      final ilk = partners.isEmpty ? null : partners.first;
      avatar = SizedBox(
        width: 28,
        height: 18,
        child: Stack(
          children: [
            Positioned(
              left: 10,
              child: _Avatar(
                harf: ilk == null ? '?' : basHarf(ilk.displayName),
                renk: ilk == null ? c.text36 : ortakRengi(context, ilk.id),
                boy: 18,
              ),
            ),
            _Avatar(
                harf: context.l10n.scopeMe.characters.first,
                renk: c.amberFill,
                boy: 18),
          ],
        ),
      );
    } else if (selectedId == '') {
      avatar = _Avatar(
          harf: context.l10n.scopeMe.characters.first,
          renk: c.amberFill,
          boy: 18);
    } else {
      final p = _ortak(selectedId);
      avatar = _Avatar(
        harf: basHarf(p?.displayName ?? '?'),
        renk: ortakRengi(context, selectedId!),
        boy: 18,
      );
    }
    final sayi = selectedId == null && partners.length > 1
        ? ' · ${partners.length + 1}'
        : '';
    final gorunumler = sira(partners);
    final konum =
        gorunumler.indexOf(selectedId).clamp(0, gorunumler.length - 1);
    return Semantics(
      button: true,
      label: '${context.l10n.scopeWho}: $etiket',
      hint: context.l10n.scopeSwipeHint,
      value: '${konum + 1} / ${gorunumler.length}',
      child: ExcludeSemantics(
        child: SandikTappable(
          semanticLabel: etiket,
          onTap: () => _ac(context),
          child: Container(
            constraints: const BoxConstraints(minHeight: SandikTouch.min),
            padding: const EdgeInsets.symmetric(horizontal: SandikSpace.sm2),
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.fromLTRB(SandikSpace.xs, SandikSpace.xs,
                  SandikSpace.sm, SandikSpace.xs),
              decoration: BoxDecoration(
                color: c.amberFill.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(SandikRadius.lg),
                border: Border.all(color: c.amberFill.withValues(alpha: 0.45)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  avatar,
                  const SizedBox(width: SandikSpace.xs2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 88),
                    child: Text(
                      '$etiket$sayi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.amberText,
                      ),
                    ),
                  ),
                  Icon(Icons.unfold_more_rounded, size: 16, color: c.amberText),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kaydırma dilinin kalıcı işareti — toplam kartının ALTINDA, ortada
/// (2026-09-21, kullanıcı: "çipin altında değil, tüm kartın altında;
/// kaydırırken canlı güncellensin"). Hangi görünümdesin, kaç görünüm var.
///
/// [ilerleme] sürükleme oranıdır (−1..1; eksi = sıradakine). Seçili hap
/// parmakla birlikte komşu noktaya AKAR: genişlik ve renk iki nokta
/// arasında oranla paylaşılır; bırakınca ya tamamlanır ya geri döner.
/// Animasyon widget'ı yok — değer kullanıcının parmağından gelir.
/// Dörde kadar nokta; daha çok ortakta noktalar sayılamaz, "3 / 9" yazısı.
class SayfaNoktalari extends StatelessWidget {
  const SayfaNoktalari({
    super.key,
    required this.sayi,
    required this.secili,
    this.ilerleme = 0,
  });

  final int sayi;
  final int secili;
  final double ilerleme;

  static const int noktaSiniri = 4;
  static const double _kisa = SandikSpace.xs;
  static const double _uzun = SandikSpace.smd;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (sayi <= 1) return const SizedBox.shrink();
    if (sayi > noktaSiniri) {
      return Text(
        '${secili + 1} / $sayi',
        style: context.t.labelSmall?.copyWith(
          color: c.text36,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }
    final p = ilerleme.clamp(-1.0, 1.0);
    final hedef = (secili + (p < 0 ? 1 : -1) + sayi) % sayi;
    final oran = p.abs();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < sayi; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : SandikSpace.xs),
            child: Container(
              key: ValueKey('nokta-$i'),
              width: i == secili
                  ? _uzun - (_uzun - _kisa) * oran
                  : i == hedef
                      ? _kisa + (_uzun - _kisa) * oran
                      : _kisa,
              height: _kisa,
              decoration: BoxDecoration(
                color: i == secili
                    ? Color.lerp(c.amberText, c.text20, oran)
                    : i == hedef
                        ? Color.lerp(c.text20, c.amberText, oran)
                        : c.text20,
                borderRadius: BorderRadius.circular(SandikRadius.sm),
              ),
            ),
          ),
      ],
    );
  }
}

/// Baş harfli yuvarlak avatar. Harf koyu zemin üstüne `onStatus` ile
/// yazılır (light'ta beyaz, dark'ta koyu yeşil — token'ın işi).
class _Avatar extends StatelessWidget {
  const _Avatar({required this.harf, required this.renk, required this.boy});
  final String harf;
  final Color renk;
  final double boy;

  @override
  Widget build(BuildContext context) => Container(
        width: boy,
        height: boy,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: renk,
          shape: BoxShape.circle,
          border: Border.all(color: context.c.surface1, width: 1),
        ),
        child: Text(
          harf,
          style: (boy >= 32 ? context.t.titleMedium : context.t.labelSmall)
              ?.copyWith(
            color: context.c.onStatus,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      );
}

// ── Alt sayfa ────────────────────────────────────────────────────────────────

class _GorunumSayfasi extends StatefulWidget {
  const _GorunumSayfasi({
    required this.partners,
    required this.selectedId,
    required this.toplamlar,
    required this.gizli,
  });

  final List<AppUser> partners;
  final String? selectedId;
  final Map<String?, double> toplamlar;
  final bool gizli;

  @override
  State<_GorunumSayfasi> createState() => _GorunumSayfasiState();
}

class _GorunumSayfasiState extends State<_GorunumSayfasi> {
  String _arama = '';

  AppUser? _ortak(String? id) {
    for (final p in widget.partners) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l10n;
    final aramaVar = widget.partners.length >= GorunumCipi.aramaEsigi;
    final sira = GorunumCipi.listeSirasi(widget.partners, _arama);
    final yukseklik = MediaQuery.sizeOf(context).height * 0.7;

    return SafeArea(
      child: Padding(
        // Klavye açılınca liste üstte kalsın.
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: yukseklik),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(SandikSpace.lg,
                    SandikSpace.lg, SandikSpace.lg, SandikSpace.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.scopeWho,
                        style: context.t.titleMedium?.copyWith(
                          color: c.text90,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      l.scopePeopleCount(widget.partners.length + 1),
                      style: context.t.bodySmall?.copyWith(color: c.text58),
                    ),
                  ],
                ),
              ),
              if (aramaVar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(SandikSpace.lg,
                      SandikSpace.xs, SandikSpace.lg, SandikSpace.xs),
                  child: TextField(
                    autofocus: false,
                    onChanged: (v) => setState(() => _arama = v),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: l.scopeSearch,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      // Dolgu/çerçeve temadan (`inputDecorationTheme` = `inputFill` kuralı).
                    ),
                  ),
                ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
                  itemCount: sira.length,
                  itemBuilder: (ctx, i) {
                    final id = sira[i];
                    final secili = id == widget.selectedId;
                    final String ad;
                    final String? alt;
                    final Widget avatar;
                    if (id == null) {
                      ad = l.scopeTogether;
                      alt = l.scopePeopleCount(widget.partners.length + 1);
                      avatar = _Avatar(
                          harf: l.scopeTogether.characters.first,
                          renk: c.text58,
                          boy: 32);
                    } else if (id == '') {
                      ad = l.scopeMe;
                      alt = null;
                      avatar = _Avatar(
                          harf: l.scopeMe.characters.first,
                          renk: c.amberFill,
                          boy: 32);
                    } else {
                      final p = _ortak(id);
                      ad = p?.displayName.trim().isEmpty ?? true
                          ? l.scopePartners
                          : p!.displayName.trim();
                      alt = null;
                      avatar = _Avatar(
                        harf: GorunumCipi.basHarf(p?.displayName ?? ''),
                        renk: GorunumCipi.ortakRengi(ctx, id),
                        boy: 32,
                      );
                    }
                    final toplam = widget.toplamlar[id];
                    return _Satir(
                      avatar: avatar,
                      ad: ad,
                      alt: alt,
                      tutar: toplam == null
                          ? null
                          : (widget.gizli ? '••••' : fmtTRYCompact(toplam)),
                      secili: secili,
                      onTap: () => Navigator.pop(ctx, id ?? ' '),
                    );
                  },
                ),
              ),
              if (sira.length == 2 && _arama.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
                  child: Text(
                    l.scopeNoMatch,
                    style: context.t.bodySmall?.copyWith(color: c.text58),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(SandikSpace.lg,
                    SandikSpace.xs, SandikSpace.lg, SandikSpace.smd),
                child: Row(
                  children: [
                    Icon(Icons.swipe_rounded, size: 14, color: c.text36),
                    const SizedBox(width: SandikSpace.xs2),
                    Expanded(
                      child: Text(
                        l.scopeSwipeHint,
                        style: context.t.bodySmall?.copyWith(color: c.text36),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({
    required this.avatar,
    required this.ad,
    required this.alt,
    required this.tutar,
    required this.secili,
    required this.onTap,
  });

  final Widget avatar;
  final String ad;
  final String? alt;
  final String? tutar;
  final bool secili;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      selected: secili,
      label: '$ad${tutar == null ? '' : ', $tutar'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
              horizontal: SandikSpace.lg, vertical: SandikSpace.sm),
          color: secili ? c.amberFill.withValues(alpha: 0.10) : null,
          child: Row(
            children: [
              avatar,
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodyLarge?.copyWith(
                        color: c.text90,
                        fontWeight: secili ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (alt != null)
                      Text(
                        alt!,
                        style: context.t.bodySmall?.copyWith(color: c.text58),
                      ),
                  ],
                ),
              ),
              if (tutar != null) ...[
                const SizedBox(width: SandikSpace.sm),
                Text(
                  tutar!,
                  style: context.t.bodyMedium?.copyWith(
                    color: c.text58,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              const SizedBox(width: SandikSpace.sm),
              Icon(
                secili ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 20,
                color: secili ? c.amberText : c.text20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

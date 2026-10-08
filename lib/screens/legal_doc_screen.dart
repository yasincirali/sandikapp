import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/legal_block.dart';
import '../services/disclaimer_service.dart';
import '../services/sunucu_secimi.dart';
import '../services/yasal_adim_plani.dart';
import '../services/yasal_metin_katalogu.dart';
import '../theme/sandik.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sigan_metin.dart';
import '../widgets/yasal_adimlar.dart';
import '../widgets/zorunlu_okuma.dart';

export '../models/legal_block.dart';
export '../widgets/zorunlu_okuma.dart' show ZorunluOkumaSonucu;

// ─── Belgeler ─────────────────────────────────────────────────────────────────

/// Uygulamada gösterilen yasal belgeler — gösterim cephesi.
///
/// ## Tek kaynak: `legal/tr/*.md` (kullanıcı kararı 2026-10-04)
/// *"Webdekiyle de her zaman eşleyelim."* 1.1'e kadar bu sınıf belgeleri
/// elle yazılmış `const LegalBlock` listeleri olarak taşıyordu — web
/// metninin kısaltılmış bir kopyası (Koşullar web'de 19, burada 14 bölüm).
/// Artık metin YOK: bloklar md'den ayrıştırılır ([YasalBelge.sablonBloklari],
/// `yasal_md.dart`), burada yalnız yer tutucular doldurulur. Yöntemin
/// gerekçesi `yasal_metin_katalogu.dart` başında.
class LegalDocs {
  static const _web = 'yasincirali.github.io/sandikapp';

  // ── Verinin durduğu ülke (köprü sürümü, K1 — 2026-09-27) ────────────────
  //
  // Metin eskiden "ABD" yazıyordu; proje aslında Japonya'daydı (Tokyo),
  // Frankfurt'a taşınıyor. Rıza (KVKK 9) verinin GERÇEK yerine verilir, bu
  // yüzden ülke bağlanılan projeden gelir. md ŞABLON kalır (`{SUPABASE_ULKE}`,
  // `{SUPABASE_ULKEDE}`); yer tutucular gösterimde doldurulur. Bilinmeyen
  // proje (test, yerel yığın) için ülke uydurulmaz — genel ifade. Web aynı
  // yer tutucuyu iki sunucunun durumunu anlatan ifadeyle doldurur
  // (`docs/_build_legal.py` → `YER_TUTUCULAR`).
  // ⚠️ Hukuki metin: metnin tamamı bir hukukçuya gösterilmeli (7499 s.
  // Kanun, 1 Haziran 2024).

  /// Gösterimde yer tutuculara giren değerler — anahtar süslü parantezsiz
  /// ad (`SUPABASE_ULKE`). Yasal onay kaydı (`YasalOnayService`) bunu
  /// `degiskenler` olarak saklar: veritabanındaki metin ŞABLON hâlidir,
  /// kullanıcının gördüğü ülke ayrıca bilinmeli.
  static Map<String, String> yerTutucuDegerleri() {
    final aktif = SunucuSecimi.instance.aktifOrNull;
    return {
      'SUPABASE_ULKE': aktif?.ulke ?? 'Yurt dışı',
      'SUPABASE_ULKEDE': aktif?.ulkede ?? 'yurt dışında',
    };
  }

  /// [belge]'nin gösterim blokları — yer tutucular bağlı sunucunun
  /// ülkesiyle doldurulmuş. Yer tutucusu olmayan belge şablonun KENDİSİNİ
  /// döner (aynı nesne).
  static List<LegalBlock> bloklar(YasalBelge belge) {
    final sablon = belge.sablonBloklari;
    if (!belge.md.contains('{')) return sablon;
    final d = yerTutucuDegerleri();
    String f(String s) {
      var r = s;
      d.forEach((ad, deger) => r = r.replaceAll('{$ad}', deger));
      return r;
    }

    return [for (final b in sablon) b.doldur(f)];
  }

  static List<LegalBlock> get terms => bloklar(YasalBelge.kosullar);
  static List<LegalBlock> get privacy => bloklar(YasalBelge.gizlilik);
  static List<LegalBlock> get kvkk => bloklar(YasalBelge.kvkk);
  static List<LegalBlock> get acikRiza => bloklar(YasalBelge.acikRiza);
}

// ─── Zorunlu okuma: onay istenen metinler ─────────────────────────────────────

/// Bir yasal metnin ekrandaki kimliği — ad, ikon, bloklar ve (zorunlu
/// okumada) sonundaki onay düğmesinin yazımı. Sonuna kadar okutulanlar
/// [liste]'dedir (1.4: Açık Rıza Metni + yatırım uyarısı). Kimlik `YasalTur`; gösterim blokları
/// tek kaynaktan gelir: belgeler `legal/tr/*.md`, yatırım uyarısı
/// `disclaimerText` (onay kaydına hash'lenen metnin KENDİSİ). Burada yeni
/// metin yazılmaz; yalnız ad, ikon ve onay düğmesi etiketi seçilir.
@immutable
class ZorunluMetin {
  const ZorunluMetin({
    required this.tur,
    required this.adaylar,
    required this.ikon,
    required this.surum,
    required this.bloklar,
    required this.onayAdaylari,
  });

  final String tur;

  /// Liste satırında ve başlıkta adı — sığan yazım adayları (uzundan kısaya).
  final List<String> adaylar;
  final IconData ikon;
  final String surum;

  /// Gösterim blokları — açılış anında kurulur (ülke yer tutucusu bağlı
  /// sunucudan dolar).
  final List<LegalBlock> Function() bloklar;

  /// Metnin sonundaki onay düğmesinin yazımları.
  final List<String> onayAdaylari;

  /// Belgenin adı ve ikonu — adım listesindeki adla aynı kaynaktan
  /// ([yasalBelgeAdaylari], [yasalBelgeIkonu]).
  static ZorunluMetin belge(AppLocalizations l, YasalBelge b) {
    final adaylar = yasalBelgeAdaylari(l, b);
    final ikon = yasalBelgeIkonu(b);
    return ZorunluMetin(
      tur: b.tur,
      adaylar: adaylar,
      ikon: ikon,
      surum: b.surum,
      bloklar: () => LegalDocs.bloklar(b),
      // Açık rıza metninin sonunda verilen şey rızadır; düğme bunu söyler
      // (iki kutulu düzenin eski "Okudum ve açık rıza veriyorum" diliyle).
      onayAdaylari: b == YasalBelge.acikRiza
          ? [l.zorunluOkumaRizaVer, l.zorunluOkumaRizaVerKisa]
          : [l.zorunluOkumaOnayla, l.zorunluOkumaOnaylaKisa],
    );
  }

  /// Yatırım uyarısının TAM metni — `disclaimer_acceptances`'a ve
  /// `yasal_onaylar`'a hash'i yazılan gövdenin aynısı.
  static ZorunluMetin yatirimUyarisi(AppLocalizations l) => ZorunluMetin(
        tur: YasalTur.yatirimUyarisi,
        adaylar: [l.yasalBelgeYatirimUyarisi],
        ikon: Icons.warning_amber_rounded,
        surum: disclaimerVersion,
        bloklar: () => const [LegalBlock.p(disclaimerText)],
        onayAdaylari: [l.zorunluOkumaOnayla, l.zorunluOkumaOnaylaKisa],
      );

  /// Okuma adımının metni ([YasalAdimTuru.okunur]): uyarı ya da Açık Rıza
  /// Metni. 1.4'ten (okuma sadeleştirme, 2026-10-05) beri sonuna kadar
  /// okunanlar YALNIZ bu ikisi; Koşullar, Gizlilik ve KVKK [belgeyiAc] ile
  /// salt okunur açılır. Hangisinin sorulacağına `YasalAdimPlani` karar
  /// verir (2026-10-05 adım düzeni; eskiden `liste`).
  static ZorunluMetin adim(AppLocalizations l, YasalAdimTuru tur) =>
      switch (tur) {
        YasalAdimTuru.yatirimUyarisi => yatirimUyarisi(l),
        YasalAdimTuru.acikRiza => belge(l, YasalBelge.acikRiza),
        YasalAdimTuru.kutu =>
          throw ArgumentError.value(tur, 'tur', 'kutu okunmaz'),
      };
}

/// [b]'yi SALT OKUNUR açar (onay düğmesi yok, okuma şartı yok) — kayıt ve
/// kapıdaki bilgilendirme/kabul belgeleri (Koşullar, Gizlilik, KVKK) ve
/// geçerli rızası olan kullanıcıda Açık Rıza Metni. Ayarlar'daki belgelerle
/// aynı görünüş; ad ve ikon [ZorunluMetin.belge]'den (liste satırıyla aynı).
Future<void> belgeyiAc(BuildContext context, YasalBelge b) {
  final m = ZorunluMetin.belge(context.l10n, b);
  return pushGuarded<void>(
    context,
    adaptiveRoute(
      builder: (_) => LegalDocScreen(
        title: m.adaylar.first,
        icon: m.ikon,
        blocks: m.bloklar(),
      ),
    ),
  );
}

/// [m]'yi zorunlu okuma kipinde açar. `null`: kullanıcı onaylamadan geri
/// döndü (ya da çift dokunma koruması ikinci açılışı düşürdü).
Future<ZorunluOkumaSonucu?> zorunluOkumaAc(
        BuildContext context, ZorunluMetin m) =>
    pushGuarded<ZorunluOkumaSonucu>(
      context,
      adaptiveRoute(
        builder: (_) => LegalDocScreen(
          title: m.adaylar.first,
          icon: m.ikon,
          blocks: m.bloklar(),
          zorunluOkuma: true,
          onayAdaylari: m.onayAdaylari,
        ),
      ),
    );

// ─── Ekran ────────────────────────────────────────────────────────────────────

class LegalDocScreen extends StatefulWidget {
  final String title;
  final List<LegalBlock> blocks;
  final IconData icon;

  /// Zorunlu okuma (2026-10-04): onay düğmesi metnin EN SONUNDA, listenin
  /// son öğesidir ve ancak sona ulaşılınca açılır; okurken altta ilerleme +
  /// "sona kadar oku" ipucu durur. Dönüş [ZorunluOkumaSonucu]. Açmak için
  /// [zorunluOkumaAc]. `false` = yalnız okuma (Ayarlar'daki belgeler;
  /// 1.4'ten beri kayıt/kapıdaki Koşullar, Gizlilik, KVKK — [belgeyiAc]).
  ///
  /// 2026-10-05: eski onay kipi `confirmMode` (alt sabit "Okudum ve
  /// onaylıyorum" çubuğu, `true` dönüşü) yalnız bayrak `zorunlu_okuma`
  /// kapalıyken kayıt ekranında kullanılıyordu; bayrakla birlikte silindi.
  final bool zorunluOkuma;

  /// Zorunlu okumada onay düğmesinin yazımları (uzundan kısaya, sığan ilki
  /// — `SiganMetin`). Boşsa "Okudum ve onaylıyorum".
  final List<String> onayAdaylari;

  const LegalDocScreen({
    super.key,
    required this.title,
    required this.blocks,
    required this.icon,
    this.zorunluOkuma = false,
    this.onayAdaylari = const [],
  });

  @override
  State<LegalDocScreen> createState() => _LegalDocScreenState();
}

class _LegalDocScreenState extends State<LegalDocScreen> {
  final _scrollCtrl = ScrollController();
  bool _reachedBottom = false;

  /// Zorunlu okumada ipucu çubuğunun değeri (0..1).
  double _ilerleme = 0;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Bütün ekran TEMA TOKENLARIYLA çizilir ────────────────────────────
    //
    // Eski sürüm baştan sona sabit açık renklerle yazılmıştı
    // (`0xFFF7F5F0` zemin, `0xFF1A1A2E` bantlar, `0xFF2C3E50` gövde) ama
    // METİN renkleri temadan geliyordu (`context.c.text90`). Koyu temada
    // bu ikisi çarpışıyor: neredeyse beyaz metin, neredeyse beyaz zemine
    // yazılıyor ve belge OKUNAMIYORDU. Kullanıcı bunu doğrudan bildirdi
    // (2026-09-10): "yasal dokümanların olduğu sayfalar eski ve dark/light
    // mode'a göre değil."
    //
    // Belgenin "resmî evrak" hissi korunuyor — ama tonlar artık tek
    // kaynaktan: zemin `background`, kâğıt `surface1`, başlık bandı
    // `surface2`, vurgu `amberText`.
    return Scaffold(
      backgroundColor: context.c.background,
      appBar: SandikAppBar(
        titleWidget: Row(
          children: [
            Icon(widget.icon, color: context.c.amberText, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.title,
                style: context.t.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.c.text90,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: context.c.surface2,
      ),
      body: Column(
        children: [
          // ── Üst bant ────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            color: context.c.surface2,
            padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 0, SandikSpace.screenH(context), 16),
            // Rozet + adres dar ekranda tek satıra sığmıyordu ("sandık ·
            // yasincirali.github.io/sandikapp" tek başına ~200pt).
            // `Wrap` gerektiğinde alt satıra iner, taşma çizgisi çıkmaz.
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.c.amberFill.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                    border: Border.all(
                      color: context.c.amberFill.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'Resmi Belge',
                    style: context.t.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.c.amberText,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Text(
                  'sandık · ${LegalDocs._web}',
                  style: context.t.bodySmall?.copyWith(color: context.c.text58),
                ),
              ],
            ),
          ),
          // ── İçerik ──────────────────────────────────────────────────────
          if (widget.zorunluOkuma) ...[
            Expanded(
              child: SonaKadarOkumaIzleyici(
                // Düğmeden sonraki boşluk: bölüm alt boşluğu + liste alt
                // boşluğu + güvenli alan (bkz. OkumaOlcumu.sonaUlasti).
                sonPay: SandikSpace.md +
                    SandikSpace.sm +
                    MediaQuery.paddingOf(context).bottom,
                onSonaUlasti: () => setState(() => _reachedBottom = true),
                onIlerleme: (v) => setState(() => _ilerleme = v),
                // Tembel liste (ListView.builder) DEĞİL: onun uzunluğu
                // kurulmamış öğeler için TAHMİNDİR. Tahmini sona varınca
                // "okundu" yapışıyor, gerçek metnin sonu daha aşağıda
                // kalıyordu (test yakaladı: 250 pt okunmadan onay açıldı).
                // Tek sütun bütün metni bir kez yerleştirir; `extentAfter`
                // kesin olur. Belge birkaç yüz paragraf — maliyeti ilk
                // yerleşimde bir kez.
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.only(bottom: SandikSpace.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < widget.blocks.length; i++)
                        _buildBlock(widget.blocks[i], i),
                      // Son öğe onay bölümü: onay metnin SONUNDA verilir.
                      _sondakiOnay(context),
                    ],
                  ),
                ),
              ),
            ),
            if (!_reachedBottom) OkumaIpucu(ilerleme: _ilerleme),
          ] else
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.only(bottom: 48),
              itemCount: widget.blocks.length,
              itemBuilder: (_, i) => _buildBlock(widget.blocks[i], i),
            ),
          ),
        ],
      ),
    );
  }

  /// Zorunlu okumada metnin sonundaki onay bölümü: amber dolgu, kilit →
  /// onay ikonu (silinen alt sabit onay çubuğuyla aynı dil); yüksekliği
  /// sabit değil: yazı ×2'de etiket iki satıra inebilir.
  Widget _sondakiOnay(BuildContext context) {
    final active = _reachedBottom;
    final adaylar = widget.onayAdaylari.isEmpty
        ? [context.l10n.zorunluOkumaOnayla, context.l10n.zorunluOkumaOnaylaKisa]
        : widget.onayAdaylari;
    final renk = active
        ? context.c.onAmber
        : context.c.onAmber.withValues(alpha: 0.45);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            _kPH, SandikSpace.lg, _kPH, SandikSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Divider(color: context.c.hairline, height: 1),
            const SizedBox(height: SandikSpace.md),
            Semantics(
              // Kendi düğümü: ekran okuyucu düğmeye odaklanınca liste onu
              // ekrana getirir (`showOnScreen`) → sona ulaşıldı sayılır.
              container: true,
              button: true,
              enabled: active,
              child: SandikBasma(
                behavior: HitTestBehavior.opaque,
                onTap: active
                    ? () => Navigator.pop(
                        context,
                        const ZorunluOkumaSonucu(
                            onaylandi: true, sonunaKadarOkundu: true))
                    : null,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                      horizontal: SandikSpace.md, vertical: SandikSpace.sm2),
                  decoration: BoxDecoration(
                    color: active
                        ? context.c.amberFill
                        : context.c.amberFill.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        active
                            ? Icons.check_circle_rounded
                            : Icons.lock_outline_rounded,
                        size: 18,
                        color: renk,
                      ),
                      const SizedBox(width: SandikSpace.sm),
                      Flexible(
                        child: SiganMetin(
                          adaylar,
                          textAlign: TextAlign.center,
                          style: context.t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: renk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlock(LegalBlock block, int index) {
    switch (block.type) {
      case LegalBlockType.h1:
        return _DocH1(block.text);
      case LegalBlockType.h2:
        return _DocH2(block.text);
      case LegalBlockType.h3:
        return _DocH3(block.text);
      case LegalBlockType.paragraph:
        return _DocParagraph(block.text);
      case LegalBlockType.meta:
        return _DocMeta(block.text);
      case LegalBlockType.divider:
        return const _DocDivider();
      case LegalBlockType.tableHeader:
        return _DocTableRow(block.cells, isHeader: true);
      case LegalBlockType.tableRow:
        // Her satır için index tabanlı zebra rengi
        return _DocTableRow(block.cells, isHeader: false, isEven: index.isEven);
    }
  }
}

// ─── Blok widget'ları ─────────────────────────────────────────────────────────
//
// Hepsi tema tokenı kullanır; hiçbirinde sabit renk yoktur. Belge
// hiyerarşisi renkle DEĞİL, ağırlık + boyut + amber vurgu çizgisiyle
// kurulur — bu, iki temada da aynı şekilde çalışan tek yoldur.

const _kPH = 20.0;

class _DocH1 extends StatelessWidget {
  final String text;
  const _DocH1(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(_kPH, 28, _kPH, 8),
        child: Text(
          text,
          style: context.t.headlineLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: context.c.text90,
            height: 1.2,
          ),
        ),
      );
}

class _DocH2 extends StatelessWidget {
  final String text;
  const _DocH2(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(_kPH, 24, _kPH, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: context.t.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.c.text90,
              ),
            ),
            const SizedBox(height: 6),
            Container(height: 2, width: 32, color: context.c.amberText),
          ],
        ),
      );
}

class _DocH3 extends StatelessWidget {
  final String text;
  const _DocH3(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(_kPH, 16, _kPH, 4),
        child: Text(
          text,
          // Alt başlık eskiden koyu YEŞİLDİ (`0xFF1B5E20`). Yeşil bu
          // uygulamada "kazanç" demek; hukuki bir alt başlıkta anlamı yok
          // ve koyu temada da okunmuyordu. Vurgu artık marka amberi.
          style: context.t.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.c.amberText,
          ),
        ),
      );
}

class _DocParagraph extends StatelessWidget {
  final String text;
  const _DocParagraph(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(_kPH, 8, _kPH, 0),
        child: Text(
          text,
          // Gövde metni tam kontrastta (`text90`): hukuki metin "ikincil"
          // değildir, kullanıcının okuması beklenen asıl içeriktir.
          style: context.t.bodyMedium?.copyWith(
            color: context.c.text90,
            height: 1.65,
          ),
        ),
      );
}

class _DocMeta extends StatelessWidget {
  final String text;
  const _DocMeta(this.text);
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(_kPH, 8, _kPH, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.c.overlay,
          borderRadius: BorderRadius.circular(SandikRadius.sm),
        ),
        child: Text(
          text,
          style: context.t.bodySmall?.copyWith(
            color: context.c.text58,
            height: 1.5,
          ),
        ),
      );
}

class _DocDivider extends StatelessWidget {
  const _DocDivider();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(_kPH, 20, _kPH, 4),
        child: Divider(color: context.c.hairline, height: 1),
      );
}

class _DocTableRow extends StatelessWidget {
  final List<String> cells;
  final bool isHeader;
  final bool isEven;
  const _DocTableRow(this.cells, {required this.isHeader, this.isEven = false});

  @override
  Widget build(BuildContext context) {
    // Zebra deseni iki temada da çalışsın diye SURFACE katmanlarından
    // kurulur: başlık en üst katman (`surface2`), satırlar `surface1` ve
    // onun üstüne ince bir overlay. Sabit krem tonları koyu temada
    // beyaz bir blok gibi patlıyordu.
    final rowBg = isHeader
        ? context.c.surface2
        : isEven
            ? context.c.surface1
            : context.c.background;

    return Container(
      margin: EdgeInsets.only(
        top: isHeader ? 16 : 0,
        left: _kPH,
        right: _kPH,
      ),
      decoration: BoxDecoration(
        color: rowBg,
        border: Border(
          bottom: BorderSide(color: context.c.hairline),
          left: BorderSide(
            color: isHeader ? context.c.amberFill : context.c.hairline,
            width: isHeader ? 3 : 1,
          ),
          right: BorderSide(color: context.c.hairline),
          top: isHeader
              ? BorderSide.none
              : BorderSide(color: context.c.hairline),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(cells.length, (i) {
            final isLast = i == cells.length - 1;
            return Expanded(
              flex: i == 0 ? 2 : 3,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: isLast
                    ? null
                    : BoxDecoration(
                        border: Border(
                          right: BorderSide(color: context.c.hairline),
                        ),
                      ),
                child: Text(
                  cells[i],
                  style:
                      (isHeader ? context.t.labelLarge : context.t.bodyMedium)
                          ?.copyWith(
                    fontWeight: isHeader ? FontWeight.w700 : FontWeight.w400,
                    // Başlık hücresi eskiden `Colors.white` idi ve açık
                    // temada da beyaz zemine yakın bir bant üstüne
                    // yazılıyordu. Artık her iki temada da okunur.
                    color: isHeader ? context.c.text90 : context.c.text58,
                    height: 1.4,
                    letterSpacing: isHeader ? 0.4 : 0,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

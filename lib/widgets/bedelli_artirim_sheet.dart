// Bedelli sermaye artırımı sayfası ve varlık ekranının "⋯" menüsü
// (Ar-Ge 2026-11-07 16:06#1, müşteri raporu 16:30 YAP 1).
//
// Hesap saf fonksiyonda (`BedelliArtirim.hesapla`); bu dosya yalnız girdiyi
// toplar, önizlemeyi yazar ve kaydı mevcut alış yoluna (`addAsset`) verir.
// Sunucu değişmez: kayıt fiyatı 1 ₺ olan sıradan bir alış lotudur, notu
// "Bedelli artırım". Ücretsiz: doğruluk düzeltmesidir, kota kapısı aynı
// pozisyona eklenen lotu yeni varlık saymaz.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../models/bedelli_artirim.dart';
import '../providers/portfolio_provider.dart';
import '../services/crash_reporter.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import 'sandik_async_button.dart';
import 'sozlesme_formu_ortak.dart';

/// Varlık ekranının "⋯" menüsü. Bugün tek satır (bedelli artırım);
/// bedelsiz/bölünme düzeltmesi geldiğinde aynı sayfaya satır olarak girer
/// (fikir 6 Kas 20:04#1). Menü ayrı sayfa çünkü ekranda `PopupMenuButton`
/// yok (`varlik_islem_cubugu_test` madde 11) ve platform menüsü iOS'ta
/// yabancı durur; satırlar 44 pt.
Future<void> showVarlikDigerIslemler(
  BuildContext context,
  WidgetRef ref, {
  required Asset varlik,
  required List<Asset> lotlar,
}) async {
  final secim = await showSandikSheet<bool>(
    context: context,
    baslik: context.l10n.digerIslemler,
    builder: (sayfa) => Padding(
      padding: EdgeInsets.fromLTRB(
        SandikSpace.screenH(sayfa),
        SandikSpace.sm,
        SandikSpace.screenH(sayfa),
        SandikSpace.lg,
      ),
      child: SingleChildScrollView(
        child: MenuSatiri(
          key: const ValueKey('menu-bedelli-artirim'),
          ikon: Icons.add_card_rounded,
          baslik: sayfa.l10n.bedelliBaslik,
          altMetin: sayfa.l10n.bedelliSatirAlt,
          onTap: () => Navigator.pop(sayfa, true),
        ),
      ),
    ),
  );
  if (secim != true || !context.mounted) return;
  await showBedelliArtirimSheet(context, ref, varlik: varlik, lotlar: lotlar);
}

/// Bedelli artırım sayfasını açar; kullanıcı kaydederse lotu yazar.
Future<void> showBedelliArtirimSheet(
  BuildContext context,
  WidgetRef ref, {
  required Asset varlik,
  required List<Asset> lotlar,
}) async {
  if (DemoModu.yazmaKapisi('bedelli')) return; // Demo: kayıt hesap ister.
  final l10n = context.l10n;
  // Notifier ŞİMDİ alınır: kayıt sürerken ekran kapanabilir.
  final notifier = ref.read(portfolioProvider.notifier);
  final eklenen = await showSandikSheet<int>(
    context: context,
    isScrollControlled: true,
    baslik: l10n.bedelliBaslik,
    altMetin: l10n.bedelliAciklama(fmtTRY(BedelliArtirim.nominal)),
    builder: (_) => BedelliArtirimSheet(
      lotlar: lotlar,
      kaydet: (hesap, tarih) => notifier.addAsset(
        name: varlik.name,
        ticker: varlik.ticker,
        type: varlik.type,
        quantity: hesap.yeniLot.toDouble(),
        purchasePrice: BedelliArtirim.nominal,
        currency: 'TRY',
        // Not etiketi: hareket listesinde bu lotun neden 1 ₺ olduğunu
        // söyler (kullanıcı notu gibi düzenlenebilir).
        notes: l10n.bedelliBaslik,
        isManualPrice: varlik.isManualPrice,
        subCategory: varlik.subCategory,
        unitType: varlik.unitType,
        addedDate: tarih,
        portfoyId: varlik.portfoyId,
        yol: 'bedelli',
      ),
    ),
  );
  if (eklenen == null || !context.mounted) return;
  sandikSnack(context, l10n.bedelliKaydedildi(fmtNumFlex(eklenen.toDouble())),
      kind: SandikSnackKind.success);
}

/// Menü sayfasının satırı: ikon, başlık, bir satır açıklama, ok. 44 pt.
class MenuSatiri extends StatelessWidget {
  const MenuSatiri({
    super.key,
    required this.ikon,
    required this.baslik,
    required this.altMetin,
    required this.onTap,
  });

  final IconData ikon;
  final String baslik;
  final String altMetin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SandikTappable(
        onTap: onTap,
        semanticLabel: '$baslik. $altMetin',
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
            child: Row(
              children: [
                Icon(ikon, size: 22, color: context.c.text90),
                const SizedBox(width: SandikSpace.smd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(baslik,
                          style: context.t.bodyLarge
                              ?.copyWith(color: context.c.text90)),
                      const SizedBox(height: SandikSpace.xxs),
                      Text(altMetin,
                          style: context.t.bodySmall
                              ?.copyWith(color: context.c.text58)),
                    ],
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: context.c.text58),
              ],
            ),
          ),
        ),
      );
}

/// Sayfanın gövdesi. Açık sınıf: widget testi doğrudan pump edebilsin.
class BedelliArtirimSheet extends StatefulWidget {
  const BedelliArtirimSheet({
    super.key,
    required this.lotlar,
    required this.kaydet,
    this.ilkTarih,
  });

  /// Pozisyonun defter satırları; eldeki lot seçilen tarihe göre sayılır.
  final List<Asset> lotlar;

  /// Kaydı yazar. Başarıda sayfa eklenen lot sayısıyla kapanır; hata
  /// olursa açık kalır (girilen oran kaybolmaz).
  final Future<void> Function(BedelliArtirim hesap, DateTime tarih) kaydet;

  /// Testte "bugün" yerine verilen başlangıç tarihi.
  final DateTime? ilkTarih;

  @override
  State<BedelliArtirimSheet> createState() => _BedelliArtirimSheetState();
}

class _BedelliArtirimSheetState extends State<BedelliArtirimSheet> {
  final _oran = TextEditingController();
  late DateTime _tarih = widget.ilkTarih ?? DateTime.now();

  @override
  void dispose() {
    _oran.dispose();
    super.dispose();
  }

  BedelliArtirim get _hesap => BedelliArtirim.hesapla(
        lotlar: widget.lotlar,
        oranYuzde: parseTrNumber(_oran.text),
        tarih: _tarih,
      );

  /// Tarih seçici gece yarısını döner. Geçmiş günde lot öğlene yazılır:
  /// kayıt UTC'ye çevrilir (`added_date`), gece yarısı saat dilimi farkıyla
  /// önceki güne kayabilirdi. Bugünse şimdiki an (sıradan alışla aynı).
  DateTime get _kayitTarihi {
    final s = DateTime.now();
    final t = _tarih;
    final bugun = t.year == s.year && t.month == s.month && t.day == s.day;
    return bugun ? s : DateTime(t.year, t.month, t.day, 12);
  }

  Future<void> _kaydet(BedelliArtirim hesap) async {
    try {
      await widget.kaydet(hesap, _kayitTarihi);
    } catch (e) {
      if (!mounted) return;
      // Snackbar sayfanın altında kalırdı; hata sayfanın üstünde.
      CrashReporter.arkaPlan(
          showSandikDialog(
            context: context,
            kind: SandikDialogKind.error,
            title: context.l10n.bedelliBaslik,
            message: context.l10n.transactionFailed(friendlyError(e)),
          ),
          reason: 'bedelli.hataDiyalogu');
      return;
    }
    if (mounted) Navigator.pop(context, hesap.yeniLot);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hesap = _hesap;
    final oranVar = (parseTrNumber(_oran.text) ?? 0) > 0;

    // Önizleme yalnız oran yazılınca; tarihte lot yoksa onu söyler.
    String? onizleme;
    String? yuvarlama;
    if (hesap.eldekiLot <= 0) {
      onizleme = l10n.bedelliLotYok;
    } else if (oranVar) {
      onizleme = l10n.bedelliOnizleme(
        fmtNumFlex(hesap.eldekiLot),
        fmtNumFlex(hesap.yeniLot.toDouble()),
        fmtTRY(BedelliArtirim.nominal),
        fmtTRY(hesap.toplamTutar),
      );
      if (hesap.yuvarlandi) {
        yuvarlama = l10n.bedelliYuvarlama(
          fmtNumFlex(hesap.hakSayisi),
          fmtNumFlex(hesap.yeniLot.toDouble()),
        );
      }
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        SandikSpace.screenH(context),
        SandikSpace.md,
        SandikSpace.screenH(context),
        SandikSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SozlesmeEtiketi(l10n.bedelliOran),
          SozlesmeAlani(
            key: const ValueKey('bedelli-oran'),
            controller: _oran,
            ipucu: l10n.bedelliOranIpucu,
            sonek: '%',
            sayi: true,
            degisti: (_) => setState(() {}),
          ),
          const SizedBox(height: SandikSpace.md),
          SozlesmeTarihi(
            etiket: l10n.bedelliTarih,
            tarih: _tarih,
            degisti: (t) => setState(() => _tarih = t),
          ),
          if (onizleme != null) ...[
            const SizedBox(height: SandikSpace.md),
            // Tam cümle: ekran okuyucu tek parça okur, anlam renkte değil.
            Text(
              onizleme,
              key: const ValueKey('bedelli-onizleme'),
              style: context.t.bodyLarge?.copyWith(color: context.c.text90),
            ),
          ],
          if (yuvarlama != null) SozlesmeNotu(yuvarlama),
          const SizedBox(height: SandikSpace.lg),
          SandikAsyncButton.kompakt(
            key: const ValueKey('bedelli-kaydet'),
            style: FilledButton.styleFrom(
              backgroundColor: context.c.amberFill,
              foregroundColor: context.c.onAmber,
              minimumSize: const Size.fromHeight(SandikTouch.min),
            ),
            // Oran yazılmadan ya da lot çıkmıyorsa kapalı.
            onPressed: hesap.kaydedilebilir ? () => _kaydet(hesap) : null,
            child: Text(l10n.bedelliKaydet),
          ),
        ],
      ),
    );
  }
}

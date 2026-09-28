import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../providers/portfolio_provider.dart';
import '../utils/money_format.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../l10n/l10n.dart';

/// Portföy hareketleri listesindeki tek satır.
///
/// `home_screen.dart` içinde private bir metottu; Riverpod + Supabase + auth
/// gerektirdiği için widget testiyle pump edilemiyordu ve taşma testi ağacın
/// yapısal kopyasını doğrulamak zorunda kalıyordu (kopya bayatlarsa test
/// yeşil kalırken uygulama taşar). Artık saf widget: veriyi parametre olarak
/// alır, provider okumaz — çağıran taraf okur.
///
/// **2026-09-28 yeniden tasarımı (kullanıcı kararı, seçenek A "gruplu
/// liste").** Eski satır kendi kartıydı: sol renk şeridi, tür rozeti,
/// miktar rozeti ve "Alım/Satım" pili. Aynı bilgi üç kez kodlanıyordu
/// (şerit + pil + işaret hepsi "alım" diyordu) ve her satır ayrı kutu
/// olduğu için göz kayıtları birlikte okuyamıyordu. Yeni satır DÜZ:
/// arka planı ve kenarı yok, çağıran taraf bir kaba (SandikCard) koyar ve
/// satırlar arasına [HareketAyraci] çizer (iOS gruplu liste). Tek renk
/// sinyali tutarın kendisi; işlem türü ve miktar sağ altta düz metin.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.asset,
    required this.portfolioState,
    this.hideBalance = false,
    this.baz = const BazPara.lira(),
    this.yilGoster = true,
  });

  final Asset asset;
  final PortfolioState portfolioState;
  final bool hideBalance;

  /// Gösterim birimi (Faz 3.2). Geçmiş bir hareket de BUGÜNKÜ kurla
  /// çevrilir — uygulamanın her yerinde geçerli sadeleştirme
  /// (`money_format.dart`); tutarın ₺ değeri defterde değişmez.
  final BazPara baz;

  /// Tarihte yıl yazılsın mı. Ana sayfada satır tek başına durur, yıl
  /// gerekir. Tüm hareketler ekranında satırlar ay kaplarında ("EYLÜL
  /// 2026") toplanır; yıl başlıkta olduğu için satırda tekrarı gürültüdür.
  final bool yilGoster;

  /// Avatar çapı. 36pt: 44pt dokunma hedefinden küçük (satır dokunulabilir
  /// değil), ikonun 18pt'i etrafında nefes payı bırakır. [HareketAyraci]
  /// girintisi bu sayıya bağlıdır.
  static const double avatarCap = 36;

  /// Yatay iç boşluk — [HareketAyraci] girintisi buradan hesaplanır.
  static const double yatayBosluk = SandikSpace.md2;

  /// Avatar ile metin bloğu arası.
  static const double avatarAraligi = SandikSpace.smd;

  @override
  Widget build(BuildContext context) {
    // Portföy ekranındaki pozisyon detayıyla birebir tutar gösterimi —
    // ikisi de 2 ondalık (kuruş).
    //
    // 2026-09-23 denetimi U14: eskiden 3 ondalıktı. "+₺10.000,000" tutarı
    // Türkçe ayraçlarla "on milyon" diye okunuyordu (üç haneli grup binlik
    // sanılır). Para kuruştan ince yazılmaz; 3 hane yalnızca BİRİM fiyat
    // hassasiyeti için anlamlıdır (fon fiyatları), toplam tutar için değil.
    final tryFmt = baz.formatter(digits: 2);
    final l10n = context.l10n;
    final bool isSell = asset.isSell;
    final bool isDelete = asset.isDeleteLog;
    final bool isDividend = asset.isDividend;

    final unitPrice = asset.isSell
        ? (asset.sellPrice ?? asset.currentPrice)
        : asset.purchasePrice;
    // Temettüde miktar 0'dır; tutar `dividendAmount` alanında taşınır.
    final txValue =
        isDividend ? asset.dividendAmount : asset.quantity * unitPrice;
    final txValueTRY = portfolioState.toTRY(txValue, asset.currency);

    // Tek renk sinyali: tutar. Alım yeşil, satım kırmızı, temettü amber,
    // silme kaydı soluk. Başka hiçbir öğe renkle tür anlatmaz — eski
    // tasarımda şerit + pil + tutar üçü birden anlatıyordu.
    final Color tutarRengi = isDelete
        ? context.c.text58
        : (isSell
            ? context.c.loss
            : (isDividend ? context.c.amberText : context.c.gain));
    final String sign = isSell || isDelete ? '−' : '+';

    // "Eklendi/Çıkarıldı" envanter diliydi; kayıtlar aslında fiyatlı
    // alım/satım işlemleri. Swipe aksiyonları ve hızlı işlem dialogu da
    // "Al/Sat" diline geçti — geçmiş listesi onlarla aynı dili konuşmalı.
    //
    // Silme artık pozisyon başına TEK kayıttır ve kaç ledger satırının
    // gittiğini taşır. Tek kayıt silindiyse sayı bilgi vermez ("Silindi ·
    // 1 kayıt" gürültü olurdu); eski kayıtlarda `deletedCount` 0'dır, o da
    // sayı bilinmiyor demektir. Her iki durumda düz "Silindi".
    //
    // Miktar artık rozet değil, tür etiketinin devamı: "Alım · 5 gr".
    // Temettüde miktar 0'dır — "· 0 adet" anlamsız olurdu, yalnızca tür.
    final String turEtiketi;
    if (isDelete) {
      turEtiketi = asset.deletedCount > 1
          ? l10n.deletedNRecords(asset.deletedCount)
          : l10n.txDeleted;
    } else if (isDividend) {
      turEtiketi = l10n.txDividend;
    } else {
      final miktar =
          qtyFormatter(maxDigits: asset.azamiOndalik).format(asset.quantity);
      final miktarMetni = asset.unitIsPrefix
          ? '${asset.unitLabel}$miktar'
          : '$miktar ${asset.unitLabel}';
      turEtiketi = '${isSell ? l10n.txSell : l10n.txBuy} · $miktarMetni';
    }

    // Yumuşak silinmiş lot: kayıt geçmişte DURUR ama artık portföye
    // dahil değil. Satırı soluklaştırıyoruz — okunabilir kalır, aktif
    // işlemlerle karışmaz. Gizlemek yanlış olurdu: kullanıcı "ne aldım,
    // ne sattım, sonra sildim" zincirini görebilmeli. Opacity tek başına
    // yetmez (renk körlüğü, parlak ekran); etiketin sonuna metinle de
    // yazılır. Eski köşe rozeti + Stack/Positioned bunun içindi, kalktı.
    final bool isVoided = asset.isDeleted;
    final String sagAltEtiket =
        isVoided ? '$turEtiketi · ${l10n.txVoided}' : turEtiketi;

    final row = Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: yatayBosluk, vertical: SandikSpace.smd),
      child: Row(
        // Avatar, metin bloğu ve tutar kolonu ortak eksende hizalansın.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Avatar(asset: asset),
          const SizedBox(width: avatarAraligi),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              // Satır yüksekliği içeriğe göre belirlensin. Varsayılan
              // `MainAxisSize.max` bu Column'u satırın (sağ kolonun
              // belirlediği) yüksekliğine zorluyordu; iki satırlık fon
              // başlığı buna sığmayınca taşıyordu.
              mainAxisSize: MainAxisSize.min,
              children: [
                // Fon/hisse: başlık olarak yalnızca KOD (THYAO).
                //
                // Önceden kod bir rozette, tam ad da altında ayrı
                // satırdaydı; uzun fon adları (45 karaktere kadar)
                // satırı taşırıyordu. Artık kod başlığın kendisi —
                // hem tekrar yok hem de tek satır garanti.
                // Tam ad, varlığın detay ekranında görünür.
                Text(
                  asset.showTicker ? asset.displayTicker! : asset.name,
                  maxLines: asset.showTicker ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    letterSpacing: asset.showTicker ? 0.2 : null,
                    color: context.c.text90,
                  ),
                ),
                const SizedBox(height: SandikSpace.xxs),
                // Saat de yazılır (kullanıcı isteği 2026-09-24); tarih
                // seçiciyle girilen işlemde saat bilinmediği için yalnızca
                // tarih kalır (`fmtTarihSaat`).
                Text(
                  fmtTarihSaat(asset.addedDate, yilsiz: !yilGoster),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodySmall?.copyWith(color: context.c.text36),
                ),
              ],
            ),
          ),
          const SizedBox(width: SandikSpace.sm),
          // Sağ kolon sabit genişlikte: sınırsız bırakılırsa genişliği
          // en uzun tutar belirler ve soldaki isim alanını yer. Sabit
          // tutmak hem bunu önler hem tüm satırların sağ kenarını
          // hizalar. Sığmayan tutar kırpılmaz, FittedBox ile küçülür.
          SizedBox(
            width: 116,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    hideBalance
                        ? '$sign${baz.gizliTutar}'
                        : '$sign${tryFmt.format(txValueTRY)}',
                    maxLines: 1,
                    // İşlem tutarı — alt alta listelenir, tabular figür.
                    // `numSmall` 13pt; burada bir kademe büyük (bodyLarge
                    // 15pt) çünkü tutar satırın tek vurgusu.
                    style: (context.t.bodyLarge ?? const TextStyle()).copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: tutarRengi,
                    ),
                  ),
                ),
                const SizedBox(height: SandikSpace.xxs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    sagAltEtiket,
                    maxLines: 1,
                    style: context.t.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: context.c.text36,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (!isVoided) return row;
    return Opacity(opacity: 0.55, child: row);
  }
}

/// Satırın solundaki tür avatarı: varlık türünün rengiyle boyanmış daire,
/// içinde tür ikonu ya da döviz sembolü. Tür bilgisini yalnızca bu taşır;
/// eski "Altın" rozeti kalktı (tür filtresi zaten listenin üstünde).
class _Avatar extends StatelessWidget {
  const _Avatar({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final symbol = asset.currencySymbol;
    final Color on = asset.type.onSurface(context);
    return Container(
      width: TransactionRow.avatarCap,
      height: TransactionRow.avatarCap,
      decoration: BoxDecoration(
        color: asset.type.color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: symbol == null
            ? Icon(asset.type.icon, size: 18, color: on)
            : Text(
                symbol,
                // Tek karakter ($, €) rahat okunur; "CHF" gibi üç harfli
                // sembol daireye ancak etiket boyutunda sığar.
                style: (symbol.length > 1
                        ? context.t.labelSmall
                        : context.t.titleSmall)
                    ?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                  height: 1,
                  color: on,
                ),
              ),
      ),
    );
  }
}

/// İki hareket satırı arasındaki saç teli çizgi.
///
/// Avatar hizasından başlar (iOS gruplu liste girintisi): çizgi metin
/// bloğunun altını çizer, avatar kolonunu kesmez. Girinti satırın kendi
/// sabitlerinden hesaplanır; satır dolgusu değişirse burası da değişir.
class HareketAyraci extends StatelessWidget {
  const HareketAyraci({super.key});

  static const double girinti = TransactionRow.yatayBosluk +
      TransactionRow.avatarCap +
      TransactionRow.avatarAraligi;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: girinti),
      child: Divider(height: 1, thickness: 1, color: context.c.hairline),
    );
  }
}

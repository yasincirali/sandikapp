import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/varlik_monogrami.dart';
import '../services/remote_config_service.dart';
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
/// satırlar arasına [HareketAyraci] çizer (iOS gruplu liste). İşlem türü
/// ve miktar sağ altta düz metin. Tutar 2026-11-01'den beri nötr (yalnız
/// temettü amber): renk kâr/zarara ayrıldı, bkz. `tutarRengi`.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.asset,
    required this.portfolioState,
    this.hideBalance = false,
    this.baz = const BazPara.lira(),
    this.yilGoster = true,
    this.silinenGorunumu = false,
    this.not,
    this.bakiye,
    this.portfoyDegeri,
    this.onTap,
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

  /// "Silinenler" alanında mı (kullanıcı kararı 2026-09-29). Satır işlem
  /// tarihinin yerine iki tarih yazar: işlemin kendisi ("Alım: 12 Mar
  /// 2026") ve silinme anı ("Silinme: 3 Eyl 2026"). Alanın başlığı zaten
  /// "silindi" dediği için soluklaştırma ve "· silindi" eki yok; tutar
  /// renk sinyali taşımaz (artık portföyde olmayan bir kazanç/kayıp).
  final bool silinenGorunumu;

  /// Kullanıcının bu işleme yazdığı not — çağıran `islemNotu(...)` ile
  /// hesaplar (eski kopyalar orada ayıklanır). Doluysa tarih satırının
  /// sonunda soluk bir not ikonu çizilir; metin satırda YAZMAZ.
  ///
  /// Neden yalnızca ikon (kullanıcı isteği 2026-09-29: "çok göz önünde
  /// olmamalı ama tamamen de kaybolmamalı"): not metni üçüncü bir satır
  /// olsaydı notlu satırlar notsuzlardan uzun olur, gruplu listenin ritmi
  /// bozulurdu. İkon satır yüksekliğini değiştirmez; metin dokununca açılan
  /// not sayfasında okunur.
  final String? not;

  /// Bu işlemden hemen önce ve sonra pozisyonda tutulan miktar — çağıran
  /// `hareketBakiyeleri(...)` ile TÜM kapsam defterinden hesaplar (satır
  /// saf kalır, defteri görmez). `null` ise ikinci satır çizilmez.
  ///
  /// Kullanıcı isteği (2026-10-29): "Portföy hareketlerinde önceki ve
  /// sonraki bakiye de yazmalı." Tarihin ALTINDA, solda ikinci küçük satır:
  /// sağ kolon 116pt sabit ve tutar + tür etiketiyle dolu; oraya eklenseydi
  /// "Alım · 5 gr" ile "12 → 17 gr" iki miktar yan yana karışırdı. Solda
  /// isim alanı esnek; satır bir metin satırı uzar, gruplu liste ritmi
  /// tüm bakiyeli satırlarda aynı kalır.
  final ({double once, double sonra})? bakiye;

  /// İşlemden hemen önce ve sonra kapsamın TOPLAM portföy değeri (TRY) —
  /// çağıran `hareketPortfoyDegerleriProvider`'dan okur; satır hesaplamaz.
  ///
  /// yasin (2026-10-29): "alım satım öncesi ve sonrası toplam bakiyeleri
  /// görelim … tutarsızlık olmamalı". Sayı Performans grafiğinin o işlemi
  /// içeren noktasıdır (karar kaydı `hareketPortfoyDegerleri`). Bakiye
  /// satırının devamında, "Portföy" önekiyle: varlığın değeri sanılmasın.
  /// Sağ kolon 116pt kalır; sığmazsa `Wrap` bütün parçayı alt satıra
  /// indirir. Kompakt yazılır (₺1,24M) — satırın ikinci bilgisi, kuruş
  /// gürültü olurdu; ekran okuyucu tam tutarı okur. Bakiye gizliyse ya da
  /// değer yoksa (seri yüklenmedi, pencere dışı) yalnız miktar.
  final ({double once, double sonra})? portfoyDegeri;

  /// Satıra dokununca — işlem notu sayfası. `null` ise satır eskisi gibi
  /// dokunulmaz (ör. ortak kaydının notu yoksa açılacak bir şey yok).
  final VoidCallback? onTap;

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

    // Tutar NÖTR (yasin 1 Kas 2026: "global örneklere bak, yap diyorsa
    // ekle"; 28 Eyl'deki "tek renk sinyali: tutar" kararının yerine).
    // Alım yeşil yazılınca uygulamanın geri kalanındaki "yeşil = kazandın"
    // anlamıyla çakışıyordu: alım kazanç değil, paranın varlığa geçişi.
    // Robinhood, Freetrade, Trade Republic işlem geçmişinde alım/satım
    // nötr; yeşil/kırmızı yalnız fiyat performansında. Tür metinle (sağ
    // altta "Alım · 100 lot") okunur; renk körlüğüne de daha uygun.
    // İstisnalar: temettü gerçekten gelen para, amber ve "+" kalır; silme
    // kaydı soluk.
    final Color tutarRengi = isDelete || silinenGorunumu
        ? context.c.text58
        : (isDividend ? context.c.amberText : context.c.text90);
    // İşaret yalnız temettüde: alımdaki "+" de kazanç gibi okunuyordu.
    final String sign = isDividend && !isDelete ? '+' : '';

    final String turEtiketi = hareketTurEtiketi(l10n, asset);

    // Yumuşak silinmiş lot: kayıt geçmişte DURUR ama artık portföye
    // dahil değil. Satırı soluklaştırıyoruz — okunabilir kalır, aktif
    // işlemlerle karışmaz. Gizlemek yanlış olurdu: kullanıcı "ne aldım,
    // ne sattım, sonra sildim" zincirini görebilmeli. Opacity tek başına
    // yetmez (renk körlüğü, parlak ekran); etiketin sonuna metinle de
    // yazılır. Eski köşe rozeti + Stack/Positioned bunun içindi, kalktı.
    final bool isVoided = asset.isDeleted && !silinenGorunumu;
    final String sagAltEtiket =
        isVoided ? '$turEtiketi · ${l10n.txVoided}' : turEtiketi;

    // Portföy önce → sonra satırı, metin kolonu yerine satırın TAM
    // genişliğinde (tutar kolonunun altına da uzanır): tutarlar kısaltmasız
    // yazıldığı için (yasin 2026-10-30) 116 pt'lik sağ kolonun yanındaki dar
    // alanda büyük yazıda kesiliyordu.
    final portfoySatiri = silinenGorunumu ? null : _portfoySatiri(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: yatayBosluk, vertical: SandikSpace.smd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
      Row(
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
                if (silinenGorunumu) ...[
                  // Mezar taşının (fiziksel silmeden kalan iz) kendi tarihi
                  // silinme anıdır; işlem tarihi bilinmez, yazılmaz.
                  if (!isDelete)
                    _tarihSatiri(
                      context,
                      l10n.txDateLabeled(
                        isSell
                            ? l10n.txSell
                            : (isDividend ? l10n.txDividend : l10n.txBuy),
                        fmtTarihSaat(asset.addedDate, yilsiz: !yilGoster),
                      ),
                    ),
                  _tarihSatiri(
                    context,
                    l10n.deletedOnDate(fmtTarihSaat(
                        asset.deletedAt ?? asset.addedDate,
                        yilsiz: !yilGoster)),
                    notIsareti: not != null,
                  ),
                ] else ...[
                  _tarihSatiri(
                    context,
                    fmtTarihSaat(asset.addedDate, yilsiz: !yilGoster),
                    notIsareti: not != null,
                  ),
                  if (bakiye case final b?)
                    if (hareketBakiyeMetni(l10n, asset, b) case final m?)
                      _bakiyeSatiri(context, m),
                ],
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
          if (portfoySatiri != null)
            Padding(
              padding: const EdgeInsets.only(
                  left: avatarCap + avatarAraligi, top: SandikSpace.xxs),
              child: portfoySatiri,
            ),
        ],
      ),
    );

    final Widget gorunen =
        isVoided ? Opacity(opacity: 0.55, child: row) : row;
    if (onTap == null) return gorunen;
    return SandikTappable(
      semanticLabel: not != null
          ? l10n.txOpenNoteWithNote(
              asset.showTicker ? asset.displayTicker! : asset.name)
          : l10n.txOpenNote(
              asset.showTicker ? asset.displayTicker! : asset.name),
      onTap: onTap,
      child: gorunen,
    );
  }

  /// Bakiye satırı: işlemden önce → sonra miktar.
  Widget _bakiyeSatiri(
          BuildContext context, ({String gorunen, String okunan}) m) =>
      Padding(
        padding: const EdgeInsets.only(top: SandikSpace.xxs),
        child: Semantics(
          label: m.okunan,
          excludeSemantics: true,
          child: _bakiyeMetni(context, m.gorunen),
        ),
      );

  /// Portföy önce → sonra (yasin 2026-10-29), TAM tutar (2026-10-30: "tam
  /// yazılmalı, karmaşa olmamalı"): Performans ipucuyla aynı biçim (₺,
  /// kuruşsuz). Okun iki yanı bölünmez boşluk: dar ekranda ya da büyük
  /// yazıda satır yalnız "Portföy"den sonra kırılır, iki tutar ayrılmaz.
  /// Bakiye gizliyken ya da değer bilinmiyorsa (92 günden eski) yok.
  Widget? _portfoySatiri(BuildContext context) {
    final p = hideBalance || baz.gizli ? null : portfoyDegeri;
    final l10n = context.l10n;
    // Bakiye satırı çıkan hareketlerde (alım/satım; temettüde değil).
    final b = bakiye;
    if (p == null || b == null || hareketBakiyeMetni(l10n, asset, b) == null) {
      return null;
    }
    return Semantics(
      label: l10n.txPortfolioValueSemantics(baz.fmt(p.once), baz.fmt(p.sonra)),
      excludeSemantics: true,
      child: _bakiyeMetni(
        context,
        l10n.txPortfolioValueChange(baz.fmt(p.once), baz.fmt(p.sonra)),
        satir: 3,
      ),
    );
  }

  /// Bakiye satırının bir parçası. Tarihten bir ton açık (text58 > text36):
  /// satırın ikinci bilgisi, ama tutarla yarışmaz. Alt alta sayılar hizalı
  /// okunsun diye tabular figür. İki satıra kadar kırılır; daha uzunu
  /// (aşırı büyük yazı) kırpılır, taşmaz.
  Widget _bakiyeMetni(BuildContext context, String metin, {int satir = 2}) =>
      Text(
        metin,
        maxLines: satir,
        overflow: TextOverflow.ellipsis,
        style: context.t.labelSmall?.copyWith(
          color: context.c.text58,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );

  /// Tarih satırı; [notIsareti] ise sonunda not ikonu.
  ///
  /// İkon ekleme formundaki "Not ekle" satırının ikonuyla AYNI
  /// (`Icons.notes_rounded`) — kullanıcı yazdığı yerde gördüğü işareti
  /// burada tanır. Renk tarihle aynı `text36`: satırda yeni bir vurgu
  /// değil, tarihin bir parçası gibi okunur.
  Widget _tarihSatiri(BuildContext context, String metin,
      {bool notIsareti = false}) {
    final metinW = Text(
      metin,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.t.bodySmall?.copyWith(color: context.c.text36),
    );
    if (!notIsareti) return metinW;
    return Row(
      children: [
        Flexible(child: metinW),
        const SizedBox(width: SandikSpace.xs),
        Icon(
          Icons.notes_rounded,
          size: 13,
          color: context.c.text36,
          semanticLabel: context.l10n.txHasNote,
        ),
      ],
    );
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
    // Bayrak `goz_alici`: hisse/fon/kripto satırında sembolün kendisi
    // (gerekçe `varlik_monogrami.dart`); tür rengi dairede kaldığı için tür
    // bilgisi kaybolmaz. Kapalıyken birebir eski ikon.
    final symbol = asset.currencySymbol ??
        (RemoteConfigService.instance.gozAlici
            ? varlikMonogrami(type: asset.type, ticker: asset.ticker)
            : null);
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
            : Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: SandikSpace.xs),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    symbol,
                    maxLines: 1,
                    // Tek karakter ($, €) rahat okunur; "CHF" gibi üç
                    // harfli sembol daireye ancak etiket boyutunda sığar.
                    // Büyük yazıda kırpılmasın diye küçülür.
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

/// Satırın sağ altındaki tür etiketi ("Alım · 5 gr", "Satım · 2 adet",
/// "Temettü", "Silindi"). İşlem notu sayfasının başlığında da aynı etiket
/// kullanılır — iki yerde ayrı yazılsaydı ilk değişiklikte ayrışırdı.
///
/// "Eklendi/Çıkarıldı" envanter diliydi; kayıtlar aslında fiyatlı
/// alım/satım işlemleri. Swipe aksiyonları ve hızlı işlem dialogu da
/// "Al/Sat" diline geçti — geçmiş listesi onlarla aynı dili konuşmalı.
///
/// Silme artık pozisyon başına TEK kayıttır ve kaç ledger satırının
/// gittiğini taşır. Tek kayıt silindiyse sayı bilgi vermez ("Silindi ·
/// 1 kayıt" gürültü olurdu); eski kayıtlarda `deletedCount` 0'dır, o da
/// sayı bilinmiyor demektir. Her iki durumda düz "Silindi".
///
/// Miktar artık rozet değil, tür etiketinin devamı: "Alım · 5 gr".
/// Temettüde miktar 0'dır — "· 0 adet" anlamsız olurdu, yalnızca tür.
String hareketTurEtiketi(AppLocalizations l10n, Asset asset) {
  if (asset.isDeleteLog) {
    return asset.deletedCount > 1
        ? l10n.deletedNRecords(asset.deletedCount)
        : l10n.txDeleted;
  }
  if (asset.isDividend) return l10n.txDividend;
  // Mevduatta miktar iç hesabın birim payıdır ("100.000 birim"), kullanıcıya
  // bir şey söylemez; tutar zaten solda yazılı. Varlık paneli bunu
  // 2026-10-01'de kaldırmıştı, hareket satırı geride kalmıştı (2026-10-02
  // müşteri testi).
  if (asset.type == AssetType.mevduat) {
    return asset.isSell ? l10n.txSell : l10n.txBuy;
  }
  final miktar =
      qtyFormatter(maxDigits: asset.azamiOndalik).format(asset.quantity);
  final miktarMetni = asset.unitIsPrefix
      ? '${asset.unitLabel}$miktar'
      : '$miktar ${birimMetni(l10n, asset.unitLabel)}';
  return '${asset.isSell ? l10n.txSell : l10n.txBuy} · $miktarMetni';
}

/// "12 → 17 gr" ve ekran okuyucu cümlesi; gösterilmeyecekse `null`.
///
/// Birim kuralı [hareketTurEtiketi] ile aynı (`qtyFormatter` +
/// `azamiOndalik`, döviz sembolü önde): satırın sağındaki "Alım · 5 gr" ile
/// soldaki bakiye aynı sayı dilini konuşur. Sonek birim yalnız sonda
/// ("12 → 17 gr"); önek sembol iki sayıda da ("$100 → $150") çünkü
/// "$100 → 150" ikinci sayıyı birimsiz bırakır. Mevduat/BES ve silme/
/// temettü için `null` (2026-10-29) — `hareketBakiyeleri` onlara zaten
/// bakiye üretmez; bu ikinci kapı satırın kendi başına da doğru kalması
/// için.
///
/// İlk alımda (önceki bakiye 0) da `null` (UX raporu 30 Eki §4, yasin
/// "yap"): "0 → 550 lot" sağdaki "Alım · 550 lot"u ikinci kez söylüyordu;
/// bilgi yalnız bakiye ÖNCEDEN varken yenidir. Portföy önce → sonra satırı
/// ayrıdır, kalır.
({String gorunen, String okunan})? hareketBakiyeMetni(
  AppLocalizations l10n,
  Asset asset,
  ({double once, double sonra}) bakiye,
) {
  if (asset.isDeleteLog || asset.isDividend || asset.isDeleted) return null;
  if (asset.type == AssetType.mevduat || asset.type == AssetType.bes) {
    return null;
  }
  final fmt = qtyFormatter(maxDigits: asset.azamiOndalik);
  // Biçimlenmiş 0 ("0", "$0"): sayının kendisi değil gösterilen değer —
  // 0,00001 BTC "0" yazılırsa o da yeni bilgi taşımaz.
  if (bakiye.once.abs() < 1e-9 || fmt.format(bakiye.once) == fmt.format(0)) {
    return null;
  }
  final once = fmt.format(bakiye.once);
  final sonra = fmt.format(bakiye.sonra);
  if (asset.unitIsPrefix) {
    final b = asset.unitLabel;
    final gorunen = l10n.txBalanceChange('$b$once', '$b$sonra');
    return (
      gorunen: gorunen,
      okunan: l10n.txBalanceSemantics('$b$once', '$b$sonra'),
    );
  }
  final birim = birimMetni(l10n, asset.unitLabel);
  return (
    gorunen: l10n.txBalanceChange(once, '$sonra $birim'),
    okunan: l10n.txBalanceSemantics('$once $birim', '$sonra $birim'),
  );
}

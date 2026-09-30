import ActivityKit
import SwiftUI
import WidgetKit

/// Sandık Live Activity — kilit ekranı banner'ı + Dynamic Island.
///
/// ## Tasarım kısıtı
/// Bu yüzey kilit ekranında saatlerce durur. Marka brief'inin "tek soru
/// kuralı": yüzey yalnızca *"portföyüm bugün ne durumda?"* sorusunu
/// yanıtlar. Yanıp sönen, dikkat çekmeye çalışan, veri kusan bir borsa
/// terminali estetiği marka dışıdır — bu yüzden burada animasyon yoktur,
/// amber yalnızca TEK bir öğede kullanılır ve ikincil veri alt satıra iner.
///
/// ## Erişilebilirlik değişmezi
/// Kazanç/kayıp yönü renkle BİRLİKTE her zaman ▲/▼ işareti taşır. Renk
/// körlüğü bir yana, kilit ekranında Dynamic Island öğeleri çok küçüktür ve
/// renk tek sinyal olamaz. `directionArrow` bunu tek yerde toplar.
/// Canlı Etkinlik dokunuşunun taşıdığı URI.
///
/// Dart tarafındaki `DeepLinkRouter.liveActivityHost` ile aynı olmalı —
/// yönlendirme bu eşleşmeye dayanıyor. Ana ekran widget'ından AYRI bir
/// host kullanılıyor: ikisi aynı yere gitse de, hangi yüzeyin kullanıldığı
/// atıfta ayırt edilebilmeli.
///
/// ## `?homeWidget` neden ZORUNLU
/// URL'yi Dart'a taşıyan `home_widget` eklentisi, gelen her URL'yi
/// `isWidgetUrl` ile süzüyor ve **yalnızca `homeWidget` adlı bir query
/// parametresi taşıyanları** kabul ediyor (`HomeWidgetPlugin.swift:462`).
/// Parametre olmadan URL sessizce düşer: uygulama açılır ama dokunuş
/// Dart'a hiç ulaşmaz, yani hata görünmez.
private let liveActivityClickURL =
    URL(string: "sandik://live-activity/summary?homeWidget=1")

@available(iOS 17.0, *)
struct SandikLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SandikActivityAttributes.self) { context in
            // Palet, Dart tarafından ÇÖZÜLMÜŞ gelen tema bayrağından seçilir.
            // `@Environment(\.colorScheme)` burada yanlış cevabı verirdi:
            // cihazın görünümünü söyler, uygulamanın tercihini değil.
            let palette = SandikPalette.resolved(isLight: context.state.isLightTheme)

            // ---- Kilit ekranı / banner ----
            //
            // Açık `return` YOK: bu kapanış `@ViewBuilder`'lı ve tek bir
            // görünüm üretiyor. Yukarıdaki `let` bir bildirimdir, result
            // builder onu olduğu gibi geçirir.
            SandikLockScreenView(context: context)
                // Sistem, arka planı kendi materyaliyle boyamasın: marka
                // zemini yeşildir, nötr siyah kullanılmaz.
                .activityBackgroundTint(palette.background)
                .activitySystemActionForegroundColor(SandikTheme.amber)
                // **Görünüm şeması SABİTLENİR — yoksa tema TERS görünür.**
                //
                // Palet doğru seçiliyor ama uzantı CİHAZIN görünümünü miras
                // alıyor. SwiftUI de sisteme uyarlanan her şeyi (materyal
                // katmanları, `activityBackgroundTint`'in üzerine bindirdiği
                // chrome, vibrancy) o mirasa göre çözüyor. Cihaz koyuyken
                // sistem bizim zeminimizi açıyor, açıkken koyultuyordu:
                // kullanıcı bulgusu "koyu moda alınca canlı aktivite açık
                // oluyor, açık moda alınca koyu" tam olarak buydu.
                //
                // `isLightTheme` zaten Dart tarafında ÇÖZÜLMÜŞ karardır
                // ("Sistem" dahil, bkz. `utils/theme_resolution.dart`);
                // şemayı ona bağlamak paletle sistemin aynı şeyi söylemesini
                // sağlar. `@Environment(\.colorScheme)` OKUMUYORUZ — burada
                // yazıyoruz.
                .environment(
                    \.colorScheme,
                    context.state.isLightTheme ? .light : .dark
                )
                // Dokunuş → uygulamanın performans ekranı (günlük grafik).
                // Kullanıcı kilit ekranındaki toplamı görüp ayrıntıya
                // inmek istediğinde varsayılan olarak uygulamanın en son
                // bırakıldığı sekme açılıyordu — banner'daki sayıyla
                // ilgisiz bir yer.
                .widgetURL(liveActivityClickURL)

        } dynamicIsland: { context in
            let palette = SandikPalette.resolved(isLight: context.state.isLightTheme)

            return DynamicIsland {
                // ---- Expanded (basılı tutunca) ----
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 7) {
                        SandikLogoMark(width: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("sandık")
                                .font(.sandikLabel(15, weight: .semibold))
                                .foregroundStyle(palette.gold)
                            // Kilit ekranıyla aynı gerekçe: rakam hangi
                            // güne ait, expanded görünümde de okunmalı.
                            if !context.state.dateText.isEmpty {
                                Text(context.state.dateText)
                                    .font(.sandikLabel(9, weight: .medium))
                                    .foregroundStyle(palette.text58)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isMarketOpen
                         ? "Son: \(context.state.updatedAtText)"
                         : "Kapalı • \(context.state.updatedAtText)")
                        .font(.sandikNumber(12, weight: .medium))
                        .foregroundStyle(palette.text58)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    // Kilit ekranıyla AYNI kural: tutar yalnızca kullanıcı
                    // açıkça izin verdiyse. Dynamic Island da kilitliyken
                    // görünür bir yüzeydir.
                    let showsAmount =
                        context.state.showAmounts && !context.state.isHidden

                    VStack(alignment: .leading, spacing: 3) {
                        Text(showsAmount ? "TOPLAM PORTFÖY DEĞERİ" : "BUGÜN")
                            .font(.sandikLabel(10, weight: .semibold))
                            // Küçük punto etiketlerde harf aralığı açılır;
                            // sıkışık kapitaller okunmaz.
                            .tracking(0.6)
                            .foregroundStyle(palette.text58)

                        if showsAmount {
                            Text(context.state.totalText)
                                .font(.sandikNumber(20, weight: .bold))
                                // Başlık boyutlarında -0.01em sıkılaştırma.
                                .tracking(-0.2)
                                .foregroundStyle(palette.gold)
                                .lineLimit(1)
                                // Dar cihazlarda (mini) uzun tutar
                                // kırpılmasın; küçülsün ama okunur kalsın.
                                .minimumScaleFactor(0.75)
                        } else {
                          HStack(spacing: 8) {
                            // Renkli yön halkası (2026-09-30) — dar
                            // görünümle aynı dil, büyük ölçekte.
                            if let y = SandikYonHalkasi.yuzde(state: context.state) {
                                SandikYonHalkasi(yuzde: y, palette: palette,
                                                 kalinlik: 3.5)
                                    .frame(width: 30, height: 30)
                            }
                            HStack(spacing: 5) {
                                // Ok YALNIZCA gerçek bir yön varken.
                                // Koşulsuz basıldığında iki durumda
                                // yanlış bilgi veriyordu: değişim
                                // ölçülemediğinde (`changePctText == "—"`)
                                // ekranda `▲ —`, sıfır değişimde ise
                                // `▲ %0,00` çıkıyor ve olmayan bir
                                // hareketi varmış gibi gösteriyordu.
                                // Renk zaten `hasDirection`'a bakıyordu;
                                // ok ile renk aynı koşula bağlanır.
                                if context.state.hasDirection {
                                    Text(directionArrow(
                                        context.state.isPositive))
                                        .font(.sandikLabel(11, weight: .black))
                                }
                                Text(context.state.changePctText)
                                    .font(.sandikNumber(20, weight: .bold))
                                    .tracking(-0.2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .foregroundStyle(context.state.hasDirection
                                ? palette.statusColor(
                                    isPositive: context.state.isPositive)
                                : palette.text58)
                          }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        // Gün içi grafik — tutar gizliyken de görünür.
                        if !context.state.sparkline.isEmpty {
                            SandikSparkline(
                                points: context.state.sparkline,
                                palette: palette,
                                color: context.state.hasDirection
                                    ? palette.statusColor(
                                        isPositive: context.state.isPositive)
                                    : palette.text58,
                                // Dar alanda gradient dolgu gürültüye
                                // dönüşüyor; yalnızca çizgi bırakılır.
                                showsFill: false
                            )
                            .frame(height: 26)
                        }
                        SandikChangePill(state: context.state)
                    }
                    .padding(.top, 4)
                }

            } compactLeading: {
                // Piyasa kapalıyken logo SOLUKLAŞIR.
                //
                // Compact alanda "Piyasa kapalı" yazacak yer yok, ama
                // donuk bir yüzde kullanıcıya "bozuk mu?" dedirtiyordu —
                // kilit ekranı banner'ı bu ayrımı kelimeyle yapıyor
                // (`isMarketOpen`), Ada'nın compact hâli hiç yapmıyordu.
                // Soluk logo, rakamın neden hareketsiz olduğunu tek bir
                // görsel ipucuyla söyler.
                //
                // Opaklık TEK sinyal değil: yüzdenin yanında durur ve
                // ayrıntı genişletildiğinde yazıyla tekrarlanır.
                //
                // ## Renkli yön halkası (2026-09-30, ikinci tur)
                // Kullanıcı: "kilit ekranındaki yuvarlak tasarım renkli
                // olacak şekilde dinamik ada için". Kilit ekranı widget'ı
                // sistem tarafından TEK RENK çizilir; Ada tam renkli — aynı
                // gösterge burada rengiyle yaşar. Yay −%3…+%3; merkezden
                // değere kadar dolar (yeşil/kırmızı), ucunda nokta: yön ve
                // büyüklük tek bakışta. İlk turdaki mini grafik genişletilmiş
                // görünümde duruyor (orada zaten vardı).
                //
                // Logoya DÜŞÜLÜR: ölçüm yokken ve bakiye gizliyken (ana ekran
                // widget'ıyla aynı gizlilik kuralı). Seans kapalıyken aynı
                // soluklaştırma.
                if let y = SandikYonHalkasi.yuzde(state: context.state) {
                    SandikYonHalkasi(yuzde: y, palette: palette, kalinlik: 3)
                        .frame(width: 24, height: 24)
                        .opacity(context.state.isMarketOpen ? 1.0 : 0.55)
                } else {
                    SandikLogoMark(width: 20)
                        .opacity(context.state.isMarketOpen ? 1.0 : 0.55)
                }

            } compactTrailing: {
                // Yön oku + yüzde. Tutar BURAYA girmez: compact alan dar,
                // uzun bir rakam sistem tarafından kırpılır.
                HStack(spacing: 2) {
                    // Ok, rengiyle AYNI koşula bağlı. Koşulsuz basıldığında
                    // veri yokken `▲ —`, sıfır değişimde `▲ %0,00`
                    // görünüyordu: nötr renkte ama yanıltıcı bir yukarı oku.
                    if context.state.hasDirection {
                        Text(directionArrow(context.state.isPositive))
                            .font(.sandikLabel(9, weight: .black))
                    }
                    Text(context.state.isHidden ? "••" : context.state.changePctText)
                        // Mini grafikle dengelensin diye bir punto büyük ve
                        // kalın (4.3): sayı şeridin "sonucu".
                        .font(.sandikNumber(14, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(context.state.hasDirection
                    ? palette.statusColor(isPositive: context.state.isPositive)
                    : palette.text58)

            } minimal: {
                // Minimal: birden fazla Live Activity yarıştığında görünen
                // TEK şey bu — yaklaşık 16pt'lik bir daire.
                //
                // Burada logo DEĞİL, DURUM gösterilir. Logo marka kimliği
                // taşıyor ama bilgi taşımıyordu: kullanıcı zaten hangi
                // uygulama olduğunu ikonun yerinden biliyor, bilmediği şey
                // portföyün ne yaptığı. Bu alan o soruya cevap verebilecek
                // kadar yer bırakıyor — tek bir yön işareti.
                //
                // Yüzde BURAYA sığmaz (`%12,34` bu çapta okunmaz); yön tek
                // başına "iyi mi kötü mü" sorusunu yanıtlar, ayrıntı için
                // kullanıcı Ada'yı genişletir.
                //
                // Yön yoksa (veri yok ya da sıfır değişim) logoya düşülür:
                // nötr bir ok, olmayan bir hareketi ima ederdi.
                //
                // 2026-09-30: yalnız ok yerine ortasında ok olan renkli
                // halka — büyüklük de okunur (dar görünümle aynı gösterge).
                Group {
                    if context.state.hasDirection,
                       let y = SandikYonHalkasi.yuzde(state: context.state) {
                        SandikYonHalkasi(yuzde: y, palette: palette,
                                         kalinlik: 2.5, okGoster: true)
                            .frame(width: 22, height: 22)
                    } else {
                        SandikLogoMark(width: 16)
                    }
                }
            }
            .keylineTint(SandikTheme.amber)
            // Ada'ya dokunuş da performans ekranına gider.
            //
            // `.widgetURL` BURADA KULLANILAMAZ: o bir görünüm
            // değiştiricisidir, `DynamicIsland` ise `View` değildir —
            // aşağıdaki (1) numaralı notta anlatılan derleme kırılmasının
            // aynısı olurdu. ActivityKit bu iş için ayrı bir API veriyor.
            .widgetURL(liveActivityClickURL)
            // ŞEMA BURAYA SABİTLENMEZ — iki ayrı nedenle.
            //
            // 1. `DynamicIsland` bir `View` DEĞİL; `.environment(...)` gibi
            //    görünüm değiştiricileri kabul etmez. Denemek derlemeyi
            //    kırar ("Value of type 'DynamicIsland' has no member
            //    'environment'", build #97) — Dart testleri Swift'i
            //    derlemediği için bu ancak CI'da görülür.
            //
            // 2. Gerek de yok. Kilit ekranında sistem, `activityBackgroundTint`
            //    üzerine kendi uyarlamalı chrome'unu bindirir; ada'da böyle bir
            //    katman yoktur — zemin her zaman siyah donanım bölgesidir ve
            //    buradaki HER renk paletten açıkça geliyor (`palette.gold`,
            //    `palette.text58`, `statusColor`). Materyal, vibrancy ya da
            //    `.primary`/`.secondary` gibi şemaya duyarlı tek bir öğe yok.
            //    Şemayı zorla açığa çekmek, siyah ada üzerinde koyu chrome
            //    isteyip görünürlüğü BOZMA riski taşırdı.
        }
    }
}

/// Yön işareti — kazanç/kayıp rengi tek başına anlam taşımasın diye
/// TEK kaynaktan üretilir.
@available(iOS 17.0, *)
func directionArrow(_ isPositive: Bool) -> String {
    isPositive ? "▲" : "▼"
}

/// Günün yönünü ve büyüklüğünü RENKLE gösteren yay — Dinamik Ada
/// (2026-09-30). Kilit ekranı widget'ının yuvarlak göstergesiyle aynı
/// geometri (240° yay, −%3…+%3) ama orada sistem tek renk çizer; burada
/// dolgu durum renginde (kazanç/kayıp), merkezden değere doğru.
///
/// Neden merkezden dolar: sıfır yayın tepesinde durur; sağa yeşil, sola
/// kırmızı büyüyen yay "ne kadar" sorusunu ok olmadan da yanıtlar. ±%3
/// dışı uçta kalır (portföy için günlük ±%3 zaten sert bir gün).
/// Yön yalnız renkle anlatılmaz: çağıran ▲/▼'yü de gösterir (dar görünümde
/// sağdaki yüzdenin yanında, minimalde halkanın ortasında).
@available(iOS 17.0, *)
struct SandikYonHalkasi: View {
    /// İşaretli günlük yüzde; 0 = hareket yok (gri, nokta tepede).
    let yuzde: Double
    let palette: SandikPalette
    var kalinlik: CGFloat = 3
    var okGoster: Bool = false

    static let olcek = 3.0
    private static let baslangic = 150.0 // derece — saat 8 yönü
    private static let aci = 240.0

    private var oran: Double {
        (min(max(yuzde, -Self.olcek), Self.olcek) + Self.olcek) / (2 * Self.olcek)
    }

    private var renk: Color {
        yuzde == 0 ? palette.text58 : palette.statusColor(isPositive: yuzde > 0)
    }

    var body: some View {
        GeometryReader { geo in
            let boyut = min(geo.size.width, geo.size.height)
            let yaricap = (boyut - kalinlik) / 2
            let kesir = Self.aci / 360
            let merkez = kesir / 2
            let deger = kesir * oran
            let nokta = Angle.degrees(Self.baslangic + 360 * deger)
            ZStack {
                Circle()
                    .trim(from: 0, to: kesir)
                    .stroke(Color.white.opacity(0.22),
                            style: StrokeStyle(lineWidth: kalinlik, lineCap: .round))
                    .rotationEffect(.degrees(Self.baslangic))
                    .padding(kalinlik / 2)
                Circle()
                    .trim(from: min(merkez, deger), to: max(merkez, deger))
                    .stroke(renk,
                            style: StrokeStyle(lineWidth: kalinlik, lineCap: .round))
                    .rotationEffect(.degrees(Self.baslangic))
                    .padding(kalinlik / 2)
                Circle()
                    .fill(renk)
                    .overlay(Circle().stroke(Color.black, lineWidth: kalinlik * 0.5))
                    .frame(width: kalinlik * 2, height: kalinlik * 2)
                    .offset(x: yaricap * CGFloat(cos(nokta.radians)),
                            y: yaricap * CGFloat(sin(nokta.radians)))
                if okGoster, yuzde != 0 {
                    Text(directionArrow(yuzde > 0))
                        .font(.sandikLabel(boyut * 0.32, weight: .black))
                        .foregroundStyle(renk)
                }
            }
            .frame(width: boyut, height: boyut)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityHidden(true)
    }

    /// Canlı Etkinlik durumundan işaretli yüzde. `changePctText` işaretsiz
    /// ("%0,42"), yön `isPositive`'te. Sayı METİNDEN okunur: yeni bir alan
    /// eklemek sunucunun 5 dakikalık push'larına da eklenmeyi gerektirirdi;
    /// eklenmezse her push'ta halka sıfıra dönerdi. Gizliyken ya da ölçüm
    /// yokken ("—") `nil` → çağıran logoya düşer.
    static func yuzde(state: SandikActivityAttributes.ContentState) -> Double? {
        if state.isHidden { return nil }
        let rakam = state.changePctText
            .filter { $0.isNumber || $0 == "," || $0 == "." }
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let deger = Double(rakam) else { return nil }
        if !state.hasDirection { return 0 }
        return state.isPositive ? deger : -deger
    }
}

// MARK: - Kilit ekranı görünümü

/// Kilit ekranı banner'ı — iki sütunlu sakin düzen.
///
/// Sol sütun "ne kadarım var", sağ sütun "bugün ne oldu" sorusunu yanıtlar;
/// aralarında hairline dikey ayraç. Bu ayrım bilinçli: kullanıcı gözünü
/// kaydırmadan iki rakamı da okuyabilmeli.
@available(iOS 17.0, *)
struct SandikLockScreenView: View {
    let context: ActivityViewContext<SandikActivityAttributes>

    /// Uygulamanın seçili teması. Bkz. `ContentState.isLightTheme`.
    private var palette: SandikPalette {
        SandikPalette.resolved(isLight: context.state.isLightTheme)
    }

    private var state: SandikActivityAttributes.ContentState { context.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ---- Başlık: kimlik + canlılık göstergesi ----
            HStack(spacing: 8) {
                SandikLogoMark(width: 24)

                // Marka adı + tarih tek blokta. Tarih ikincil bilgidir ve
                // alt satıra iner: yüzeyin ana sorusu "bugün ne oldu",
                // "hangi gün" değil — ama gece yarısını geçen bir oturumda
                // rakamın hangi güne ait olduğu okunabilmeli.
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sandık")
                        .font(.sandikLabel(15, weight: .semibold))
                        .foregroundStyle(palette.text90)

                    if !state.dateText.isEmpty {
                        Text(state.dateText)
                            .font(.sandikLabel(10, weight: .medium))
                            .foregroundStyle(palette.text58)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    // Canlılık noktası — statik. Marka kuralı gereği yanıp
                    // sönmez: kilit ekranında saatlerce duran bir yüzeyde
                    // titreşen nokta rahatsız edicidir ve pil yakar.
                    //
                    // Piyasa kapalıyken YEŞİL DEĞİL gri: yeşil nokta
                    // "veri akıyor" demektir ve gece bu doğru değildir.
                    Circle()
                        .fill(state.isMarketOpen
                              ? palette.gain
                              : palette.text36)
                        .frame(width: 6, height: 6)

                    // Piyasa kapalıyken kullanıcı rakamın NEDEN
                    // değişmediğini bilmeli; aksi halde donuk sayı
                    // "uygulama bozuk" olarak okunur.
                    Text(state.isMarketOpen
                         ? "Canlı • \(state.updatedAtText)"
                         : "Piyasa kapalı • \(state.updatedAtText)")
                        .font(.sandikNumber(11, weight: .medium))
                        .foregroundStyle(palette.text58)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            // ---- İçerik ----
            //
            // Düzen `showAmounts`'a göre DEĞİŞİR:
            //   kapalı → günlük yüzde solda, grafik sağda (tutar hiç yok)
            //   açık   → toplam + net kazanç iki sütun, grafik altta
            //
            // Yüzde ve grafik her iki durumda da görünür: ikisi de portföy
            // BÜYÜKLÜĞÜNÜ ele vermez, yalnızca günün nasıl geçtiğini söyler.
            if state.showAmounts && !state.isHidden {
                amountsLayout
            } else {
                privateLayout
            }
        }
        .padding(16)
        .background(palette.background)
        // Kilit ekranı çerçevesi — lg (20) + hairline kenar.
        .clipShape(RoundedRectangle(cornerRadius: SandikTheme.radiusLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SandikTheme.radiusLg, style: .continuous)
                .strokeBorder(palette.hairline, lineWidth: 1)
        )
        // Ekran okuyucu için tek, anlamlı cümle — parça parça okumak yerine.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Gizli düzen — tutar YOK, yalnızca günlük yüzde + grafik.
    ///
    /// Varsayılan durum budur. Kullanıcı Ayarlar'dan açıkça izin vermedikçe
    /// kilit ekranında para tutarı görünmez.
    private var privateLayout: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Bugün")
                    .font(.sandikLabel(11, weight: .medium))
                    .foregroundStyle(palette.text58)

                HStack(spacing: 5) {
                    // Veri yoksa ok ve işaret basılmaz: `▲ +—` anlamsızdır
                    // ve yeşil renk olmayan bir kazancı ima ederdi.
                    if state.hasDirection {
                        Text(directionArrow(state.isPositive))
                            .font(.sandikLabel(13, weight: .black))
                    }
                    Text(state.hasChangeData
                         ? (state.isFlatChange
                            ? state.changePctText
                            : "\(signPrefix(state.isPositive))\(state.changePctText)")
                         : "—")
                        .font(.sandikNumber(24, weight: .bold))
                        .tracking(-0.24)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(state.hasDirection
                                 ? palette.statusColor(isPositive: state.isPositive)
                                 : palette.text58)
            }

            Spacer(minLength: 0)

            // Grafik sağda, dikey alanı doldurur.
            SandikSparkline(
                points: state.sparkline,
                palette: palette,
                color: state.hasDirection
                    ? palette.statusColor(isPositive: state.isPositive)
                    : palette.text58,
                isMarketOpen: state.isMarketOpen,
                // Tutar gizliyken bu alanlar BOŞ gelir: rakam yazılmaz
                // ama kılavuz çizgileri yine çizilir. Çizgi bir büyüklük
                // taşımaz, yalnızca grafiğin bandını gösterir.
                axisMin: state.axisMinText,
                axisMax: state.axisMaxText,
                showsGuides: true
            )
            .frame(width: 130, height: 44)
        }
    }

    /// Tutarlı düzen — kullanıcı Ayarlar'dan açıkça izin verdiyse.
    private var amountsLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                // Sol: toplam portföy.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Toplam Portföy")
                        .font(.sandikLabel(11, weight: .medium))
                        .foregroundStyle(palette.text58)

                    Text(state.totalText)
                        .font(.sandikNumber(19, weight: .bold))
                        .tracking(-0.19)
                        .foregroundStyle(palette.gold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Hairline dikey ayraç.
                Rectangle()
                    .fill(palette.hairline)
                    .frame(width: 1)
                    .frame(maxHeight: 46)
                    .padding(.horizontal, 14)

                // Sağ: bugünkü net kazanç.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bugünkü Değişim")
                        .font(.sandikLabel(11, weight: .medium))
                        .foregroundStyle(palette.text58)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    HStack(spacing: 4) {
                        if state.hasDirection {
                            Text(directionArrow(state.isPositive))
                                .font(.sandikLabel(11, weight: .black))
                        }
                        Text(state.changeText)
                            .font(.sandikNumber(17, weight: .bold))
                            .tracking(-0.17)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(state.hasDirection
                                     ? palette.statusColor(isPositive: state.isPositive)
                                     : palette.text58)

                    // Yüzde rozeti — durum renginin çok düşük alfalı zemini
                    // üstünde. Amber BURAYA konmaz: brief'e göre amber
                    // yalnızca gerçekten vurgulanacak TEK öğe için.
                    if state.hasDirection {
                        Text("\(signPrefix(state.isPositive))\(state.changePctText) Günlük")
                            .font(.sandikNumber(10, weight: .semibold))
                            .foregroundStyle(palette.statusColor(isPositive: state.isPositive))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: SandikTheme.radiusSm, style: .continuous)
                                    .fill(palette.statusColor(isPositive: state.isPositive)
                                        .opacity(0.14))
                            )
                            .padding(.top, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Grafik altta, tam genişlik.
            if !state.sparkline.isEmpty {
                SandikSparkline(
                    points: state.sparkline,
                    palette: palette,
                    color: state.hasDirection
                        ? palette.statusColor(isPositive: state.isPositive)
                        : palette.text58,
                    isMarketOpen: state.isMarketOpen,
                    axisMin: state.axisMinText,
                    axisMax: state.axisMaxText,
                    showsGuides: true
                )
                .frame(height: 32)
            }
        }
    }

    /// İşaret öneki — yüzde rozetinde `+%2,45` / `-%2,45` okunuşu için.
    private func signPrefix(_ isPositive: Bool) -> String {
        isPositive ? "+" : "-"
    }

    /// VoiceOver özeti. Ok işaretleri sesli okumada anlamsızdır; yön
    /// burada kelimeyle söylenir.
    private var accessibilitySummary: String {
        if state.isHidden {
            return "Sandık. Bakiye gizli."
        }
        let yon = state.isPositive ? "artış" : "düşüş"
        // Tarih okumanın BAŞINA girer: ekran okuyucu kullanıcısı yüzeye
        // baktığında ilk duyması gereken şey verinin hangi güne ait olduğu.
        let gun = state.dateText.isEmpty ? "" : "\(state.dateText). "

        // Tutar gizliyken sesli okuma da tutarı SÖYLEMEZ. Aksi halde
        // ekranda gizlenen rakam VoiceOver'dan duyulurdu — kilit
        // ekranında bu, gizlemenin tamamen anlamsızlaşması demek.
        guard state.showAmounts else {
            return "Sandık. \(gun)Bugün yüzde \(state.changePctText) \(yon). "
                + "Son güncelleme \(state.updatedAtText)."
        }

        return "Sandık. \(gun)Toplam portföy \(state.totalText). "
            + "Bugün \(state.changeText), yüzde \(state.changePctText) \(yon). "
            + "Son güncelleme \(state.updatedAtText)."
    }
}

// MARK: - Değişim pill'i (Dynamic Island expanded alt satırı)

/// `surface1` zeminli pill — "Bugün: ▲ +₺35.420,00 (%2,45)".
@available(iOS 17.0, *)
struct SandikChangePill: View {
    let state: SandikActivityAttributes.ContentState

    private var palette: SandikPalette {
        SandikPalette.resolved(isLight: state.isLightTheme)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Bugün")
                .font(.sandikLabel(11, weight: .medium))
                .foregroundStyle(palette.text58)

            // Yön oku yalnızca gerçek bir hareket varken. Sıfır değişimde
            // ok basmak olmayan bir yönü ima eder.
            if state.hasDirection {
                Text(directionArrow(state.isPositive))
                    .font(.sandikLabel(10, weight: .black))
                    .foregroundStyle(palette.statusColor(isPositive: state.isPositive))
            }

            // Tutar yalnızca izin verildiyse; yüzde her zaman görünür.
            if state.showAmounts && !state.isHidden {
                Text(state.changeText)
                    .font(.sandikNumber(13, weight: .bold))
                    .foregroundStyle(state.hasDirection
                        ? palette.statusColor(isPositive: state.isPositive)
                        : palette.text58)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("(\(state.changePctText))")
                    .font(.sandikNumber(12, weight: .medium))
                    .foregroundStyle(palette.text58)
            } else {
                Text(state.changePctText)
                    .font(.sandikNumber(13, weight: .bold))
                    .foregroundStyle(state.hasDirection
                        ? palette.statusColor(isPositive: state.isPositive)
                        : palette.text58)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SandikTheme.radiusMd, style: .continuous)
                .fill(palette.surface1)
        )
    }
}

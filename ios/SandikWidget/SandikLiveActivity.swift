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
@available(iOS 17.0, *)
struct SandikLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SandikActivityAttributes.self) { context in
            // ---- Kilit ekranı / banner ----
            SandikLockScreenView(context: context)
                // Sistem, arka planı kendi materyaliyle boyamasın: marka
                // zemini yeşildir, nötr siyah kullanılmaz.
                .activityBackgroundTint(SandikTheme.background)
                .activitySystemActionForegroundColor(SandikTheme.amber)

        } dynamicIsland: { context in
            DynamicIsland {
                // ---- Expanded (basılı tutunca) ----
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 7) {
                        SandikLogoMark(width: 22)
                        Text("sandık")
                            .font(.sandikLabel(15, weight: .semibold))
                            .foregroundStyle(SandikTheme.gold)
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("Son: \(context.state.updatedAtText)")
                        .font(.sandikNumber(12, weight: .medium))
                        .foregroundStyle(SandikTheme.text58)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TOPLAM PORTFÖY DEĞERİ")
                            .font(.sandikLabel(10, weight: .semibold))
                            // Küçük punto etiketlerde harf aralığı açılır;
                            // sıkışık kapitaller okunmaz.
                            .tracking(0.6)
                            .foregroundStyle(SandikTheme.text58)

                        Text(context.state.totalText)
                            .font(.sandikNumber(20, weight: .bold))
                            // Başlık boyutlarında -0.01em sıkılaştırma.
                            .tracking(-0.2)
                            .foregroundStyle(SandikTheme.gold)
                            .lineLimit(1)
                            // Dar cihazlarda (mini) uzun tutar kırpılmasın;
                            // küçülsün ama okunur kalsın.
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    SandikChangePill(state: context.state)
                        .padding(.top, 4)
                }

            } compactLeading: {
                SandikLogoMark(width: 20)

            } compactTrailing: {
                // Yön oku + yüzde. Tutar BURAYA girmez: compact alan dar,
                // uzun bir rakam sistem tarafından kırpılır.
                HStack(spacing: 2) {
                    Text(directionArrow(context.state.isPositive))
                        .font(.sandikLabel(9, weight: .black))
                    Text(context.state.isHidden ? "••" : context.state.changePctText)
                        .font(.sandikNumber(13, weight: .semibold))
                }
                .foregroundStyle(SandikTheme.statusColor(isPositive: context.state.isPositive))

            } minimal: {
                // Minimal: birden fazla Live Activity yarıştığında görünür.
                // Marka kimliği tek bir işarete iner.
                SandikLogoMark(width: 16)
            }
            .keylineTint(SandikTheme.amber)
        }
    }
}

/// Yön işareti — kazanç/kayıp rengi tek başına anlam taşımasın diye
/// TEK kaynaktan üretilir.
@available(iOS 17.0, *)
func directionArrow(_ isPositive: Bool) -> String {
    isPositive ? "▲" : "▼"
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

    private var state: SandikActivityAttributes.ContentState { context.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ---- Başlık: kimlik + canlılık göstergesi ----
            HStack(spacing: 8) {
                SandikLogoMark(width: 24)

                Text("Sandık")
                    .font(.sandikLabel(15, weight: .semibold))
                    .foregroundStyle(SandikTheme.text90)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    // "Canlı" noktası — statik. Marka kuralı gereği yanıp
                    // sönmez: kilit ekranında saatlerce duran bir yüzeyde
                    // titreşen nokta rahatsız edicidir ve pil yakar.
                    Circle()
                        .fill(SandikTheme.gain)
                        .frame(width: 6, height: 6)

                    Text("Canlı • \(state.updatedAtText)")
                        .font(.sandikNumber(11, weight: .medium))
                        .foregroundStyle(SandikTheme.text58)
                }
            }

            // ---- İçerik: iki sütun + dikey ayraç ----
            HStack(alignment: .top, spacing: 0) {

                // Sol: toplam portföy.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Toplam Portföy")
                        .font(.sandikLabel(11, weight: .medium))
                        .foregroundStyle(SandikTheme.text58)

                    Text(state.totalText)
                        .font(.sandikNumber(19, weight: .bold))
                        .tracking(-0.19)
                        .foregroundStyle(SandikTheme.gold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Hairline dikey ayraç.
                Rectangle()
                    .fill(SandikTheme.hairline)
                    .frame(width: 1)
                    .frame(maxHeight: 46)
                    .padding(.horizontal, 14)

                // Sağ: bugünkü net kazanç.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bugünkü Net Kazanç")
                        .font(.sandikLabel(11, weight: .medium))
                        .foregroundStyle(SandikTheme.text58)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if state.isHidden {
                        Text("••••••")
                            .font(.sandikNumber(17, weight: .bold))
                            .foregroundStyle(SandikTheme.text36)
                    } else {
                        HStack(spacing: 4) {
                            Text(directionArrow(state.isPositive))
                                .font(.sandikLabel(11, weight: .black))
                            Text(state.changeText)
                                .font(.sandikNumber(17, weight: .bold))
                                .tracking(-0.17)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(SandikTheme.statusColor(isPositive: state.isPositive))

                        // Yüzde rozeti — durum renginin çok düşük alfalı
                        // zemini üstünde. Amber BURAYA konmaz: brief'e göre
                        // amber yalnızca gerçekten vurgulanacak TEK öğe için.
                        Text("\(signPrefix(state.isPositive))\(state.changePctText) Günlük")
                            .font(.sandikNumber(10, weight: .semibold))
                            .foregroundStyle(SandikTheme.statusColor(isPositive: state.isPositive))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: SandikTheme.radiusSm, style: .continuous)
                                    .fill(SandikTheme.statusColor(isPositive: state.isPositive)
                                        .opacity(0.14))
                            )
                            .padding(.top, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(SandikTheme.background)
        // Kilit ekranı çerçevesi — lg (20) + hairline kenar.
        .clipShape(RoundedRectangle(cornerRadius: SandikTheme.radiusLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SandikTheme.radiusLg, style: .continuous)
                .strokeBorder(SandikTheme.hairline, lineWidth: 1)
        )
        // Ekran okuyucu için tek, anlamlı cümle — parça parça okumak yerine.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
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
        return "Sandık. Toplam portföy \(state.totalText). "
            + "Bugün \(state.changeText), yüzde \(state.changePctText) \(yon). "
            + "Son güncelleme \(state.updatedAtText)."
    }
}

// MARK: - Değişim pill'i (Dynamic Island expanded alt satırı)

/// `surface1` zeminli pill — "Bugün: ▲ +₺35.420,00 (%2,45)".
@available(iOS 17.0, *)
struct SandikChangePill: View {
    let state: SandikActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 6) {
            Text("Bugün")
                .font(.sandikLabel(11, weight: .medium))
                .foregroundStyle(SandikTheme.text58)

            if state.isHidden {
                Text("••••••")
                    .font(.sandikNumber(13, weight: .bold))
                    .foregroundStyle(SandikTheme.text36)
            } else {
                Text(directionArrow(state.isPositive))
                    .font(.sandikLabel(10, weight: .black))
                    .foregroundStyle(SandikTheme.statusColor(isPositive: state.isPositive))

                Text(state.changeText)
                    .font(.sandikNumber(13, weight: .bold))
                    .foregroundStyle(SandikTheme.statusColor(isPositive: state.isPositive))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("(\(state.changePctText))")
                    .font(.sandikNumber(12, weight: .medium))
                    .foregroundStyle(SandikTheme.text58)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SandikTheme.radiusMd, style: .continuous)
                .fill(SandikTheme.surface1)
        )
    }
}

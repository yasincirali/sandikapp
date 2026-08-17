import ActivityKit
import Flutter
import Foundation

/// Dart ↔ ActivityKit köprüsü.
///
/// Dart tarafı seansın NE ZAMAN başlayıp biteceğine karar verir
/// (`lib/services/live_activity_service.dart`); burası yalnızca o kararı
/// ActivityKit çağrılarına çevirir. İş mantığı bilinçli olarak Dart'ta
/// tutulur: test edilebilir ve iki platformda da aynı yerde durur.
///
/// ## Hata felsefesi
/// Live Activity İKİNCİL bir yüzeydir. Hiçbir hata uygulamanın akışını
/// bozmamalı — bu yüzden metotlar `FlutterError` fırlatmak yerine `false`
/// döner ve Dart tarafı sessizce geçer. `HomeWidgetService`'teki aynı
/// yaklaşım burada da geçerli.
@available(iOS 17.0, *)
enum LiveActivityBridge {

    /// Şu an yürüyen oturum. ActivityKit birden fazla oturuma izin verir
    /// ama Sandık için tek bir "seans" anlamlıdır; ikinci bir oturum
    /// kilit ekranında aynı bilgiyi iki kez gösterirdi.
    private static var current: Activity<SandikActivityAttributes>?

    /// Yürüyen oturumu, uygulama yeniden başlatıldıysa sistemden geri bulur.
    ///
    /// **Neden gerekli:** `current` yalnızca süreç belleğinde yaşar. Kullanıcı
    /// uygulamayı kapatıp açtığında Live Activity kilit ekranında DURMAYA
    /// devam eder ama `current` nil olur; bu haliyle `update` sessizce hiçbir
    /// şey yapmaz ve banner son değerde donar. ActivityKit'in kendi kaydı
    /// tek doğru kaynaktır.
    private static func resolveCurrent() -> Activity<SandikActivityAttributes>? {
        if let current, current.activityState == .active {
            return current
        }
        let found = Activity<SandikActivityAttributes>.activities
            .first { $0.activityState == .active }
        current = found
        return found
    }

    /// Cihaz + kullanıcı izni Live Activity'ye açık mı?
    ///
    /// Kullanıcı Ayarlar'dan kapatabilir; bu durumda `request` çağrısı
    /// hata fırlatır. Dart tarafı önce bunu sorar.
    static var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Seansı başlatır. Zaten yürüyen bir oturum varsa YENİSİNİ AÇMAZ,
    /// mevcut olanı günceller — çift banner'ı önler.
    @discardableResult
    static func start(
        sessionName: String,
        state: SandikActivityAttributes.ContentState
    ) -> Bool {
        guard isEnabled else { return false }

        if resolveCurrent() != nil {
            return update(state: state)
        }

        do {
            let attributes = SandikActivityAttributes(sessionName: sessionName)
            let content = ActivityContent(
                state: state,
                // Sistem, seans bitiminde oturumu kendiliğinden "eskimiş"
                // sayar. Kullanıcı uygulamayı hiç açmasa bile kilit ekranı
                // bayat rakam göstermez.
                staleDate: state.sessionEndsAtDate
            )
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                // Push token İSTENİR: uygulama kapalıyken de kilit ekranı
                // güncellenebilsin. `nil` iken oturum yalnızca uygulama
                // önplandayken tazeleniyordu ve kullanıcı telefonu
                // kilitleyince rakam donuyordu.
                pushType: .token
            )
            current = activity
            observePushToken(activity)
            return true
        } catch {
            NSLog("[Sandik] Live Activity başlatılamadı: \(error.localizedDescription)")
            return false
        }
    }

    /// Oturumun push token'ını dinler ve Dart'a iletir.
    ///
    /// **Token oturuma özeldir ve DEĞİŞEBİLİR.** ActivityKit her oturum için
    /// ayrı bir token üretir; sistem gerektiğinde döndürür. Bu yüzden tek
    /// seferlik okuma yetmez, akış boyunca dinlenir — kaçırılan bir
    /// yenileme, sunucunun ölü token'a push atmasına ve kilit ekranının
    /// sessizce donmasına yol açar.
    ///
    /// `Task` bilerek tutulmuyor: oturum bittiğinde `pushTokenUpdates`
    /// akışı kendiliğinden kapanır.
    private static func observePushToken(
        _ activity: Activity<SandikActivityAttributes>
    ) {
        Task {
            for await tokenData in activity.pushTokenUpdates {
                // APNs token'ı ham byte'tır; sunucu hex bekler.
                let hex = tokenData.map { String(format: "%02x", $0) }.joined()
                await MainActor.run {
                    onPushToken?(hex, activity.id)
                }
            }
        }
    }

    /// Yeni push token geldiğinde çağrılır — `(tokenHex, activityId)`.
    /// `LiveActivityChannel` bunu Dart tarafına iletir.
    static var onPushToken: ((String, String) -> Void)?

    /// Yürüyen oturumun içeriğini tazeler. Oturum yoksa sessizce `false`.
    @discardableResult
    static func update(state: SandikActivityAttributes.ContentState) -> Bool {
        guard let activity = resolveCurrent() else { return false }

        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: state.sessionEndsAtDate)
            )
        }
        return true
    }

    /// Oturumu bitirir.
    ///
    /// [immediate] `true` ise banner hemen kaybolur (çıkış/gizlilik durumu).
    /// `false` ise son değer kısa süre kilit ekranında kalır — seans normal
    /// kapandığında kullanıcı kapanış rakamını görebilsin diye.
    @discardableResult
    static func end(
        finalState: SandikActivityAttributes.ContentState?,
        immediate: Bool
    ) -> Bool {
        guard let activity = resolveCurrent() else { return false }

        let content = finalState.map {
            ActivityContent(state: $0, staleDate: nil)
        }

        Task {
            await activity.end(
                content,
                dismissalPolicy: immediate ? .immediate : .default
            )
        }
        current = nil
        return true
    }

    /// Tüm oturumları kapatır — oturum kapanışında çağrılır.
    ///
    /// **Gizlilik kritik:** çıkış yapan kullanıcının bakiyesi kilit
    /// ekranında asılı kalmamalı. Burada `.immediate` şart; `.default`
    /// banner'ı bir süre daha ekranda bırakırdı.
    static func endAll() {
        current = nil
        for activity in Activity<SandikActivityAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}

/// MethodChannel kaydı — `AppDelegate` tarafından çağrılır.
enum LiveActivityChannel {
    static let name = "com.sandik.app/live_activity"

    static func register(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)

        // Push token geldiğinde Dart'a haber ver — Dart onu Supabase'e
        // yazar. Köprü tek yönlü değildir: token asenkron ve gecikmeli
        // gelir, `start` çağrısı çoktan dönmüş olur.
        if #available(iOS 17.0, *) {
            LiveActivityBridge.onPushToken = { token, activityId in
                channel.invokeMethod("onPushToken", arguments: [
                    "token": token,
                    "activityId": activityId,
                ])
            }
        }

        channel.setMethodCallHandler { call, result in
            // Kapı 17.0'da: `ActivityContent` ve
            // `Activity.request(attributes:content:pushType:)` iOS 16.2+
            // API'leridir, 16.1'de yoktur. Hedef minimumu zaten 17.0 olduğu
            // için koşul pratikte hep doğru; kapı yine de bırakılır ki hedef
            // ileride düşürülürse derleme kırılsın, sessizce çökmesin.
            guard #available(iOS 17.0, *) else {
                result(call.method == "isSupported" ? false : FlutterMethodNotImplemented)
                return
            }

            switch call.method {
            case "isSupported":
                result(LiveActivityBridge.isEnabled)

            case "start":
                guard let args = call.arguments as? [String: Any],
                      let state = parseState(args) else {
                    result(false)
                    return
                }
                let name = args["sessionName"] as? String ?? "Piyasa Seansı"
                result(LiveActivityBridge.start(sessionName: name, state: state))

            case "update":
                guard let args = call.arguments as? [String: Any],
                      let state = parseState(args) else {
                    result(false)
                    return
                }
                result(LiveActivityBridge.update(state: state))

            case "end":
                let args = call.arguments as? [String: Any] ?? [:]
                let immediate = args["immediate"] as? Bool ?? false
                result(LiveActivityBridge.end(
                    finalState: parseState(args),
                    immediate: immediate
                ))

            case "endAll":
                LiveActivityBridge.endAll()
                result(true)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    /// Dart map'ini `ContentState`'e çevirir.
    ///
    /// Zorunlu alan eksikse `nil` döner ve çağrı sessizce başarısız olur —
    /// yarım veriyle kilit ekranına boş alan basmaktansa hiç göstermemek
    /// yeğdir.
    @available(iOS 17.0, *)
    private static func parseState(_ args: [String: Any]) -> SandikActivityAttributes.ContentState? {
        guard let total = args["totalText"] as? String,
              let change = args["changeText"] as? String,
              let pct = args["changePctText"] as? String,
              let isPositive = args["isPositive"] as? Bool,
              let updatedAt = args["updatedAtText"] as? String else {
            return nil
        }

        // Dart `DateTime.millisecondsSinceEpoch` gönderir; tip UNIX SANİYESİ
        // olarak taşınır (bkz. `ContentState.sessionEndsAtUnix`). Alan yoksa
        // 0 kalır ve `sessionEndsAtDate` bir saat sonrasına düşer.
        let endsUnix = (args["sessionEndsAtMs"] as? NSNumber)
            .map { $0.doubleValue / 1000.0 } ?? 0

        // Sparkline normalize (0…1) gelir; ham tutar ASLA taşınmaz.
        // Bozuk/eksik veri grafiği gizler, uydurma çizgi çizmez.
        let spark = (args["sparkline"] as? [NSNumber])?.map { $0.doubleValue }
            ?? []

        return SandikActivityAttributes.ContentState(
            totalText: total,
            changeText: change,
            changePctText: pct,
            isPositive: isPositive,
            isHidden: args["isHidden"] as? Bool ?? false,
            updatedAtText: updatedAt,
            // Zorunlu DEĞİL: alan yoksa (eski Dart tarafı) tarih satırı
            // hiç çizilmez, oturum yine de açılır.
            dateText: args["dateText"] as? String ?? "",
            sessionEndsAtUnix: endsUnix,
            sparkline: spark.count >= 2 ? spark : [],
            // Varsayılan KAPALI: bayrak eksikse tutar gösterilmez.
            // Gizlilik kararlarında güvenli taraf budur.
            showAmounts: args["showAmounts"] as? Bool ?? false,
            // Grafiğin tutar ekseni etiketleri.
            //
            // **Bu alanlar EKSİKTİ.** Dart tarafı gönderiyor ve sunucu
            // push'u da taşıyor, ama burada okunmadığı için Swift
            // varsayılanına (boş string) düşüyorlardı: kullanıcı
            // "Tutarları göster"i açsa bile kılavuz çizgilerinin yanında
            // hiçbir rakam görünmüyordu.
            //
            // Boş gelmesi MEŞRU bir durumdur (tutar gizli) — o zaman
            // uzantı yalnızca çizgileri çizer, rakamı yazmaz.
            //
            // ⚠️ Argüman sırası `ContentState` alan sırasıyla AYNI olmak
            // zorunda (memberwise initializer): showAmounts → axisMinText
            // → axisMaxText → isFlatChange → isMarketOpen.
            axisMinText: args["axisMinText"] as? String ?? "",
            axisMaxText: args["axisMaxText"] as? String ?? "",
            // Ölçüldü ama sıfır mı? Yön oku ve kâr/zarar rengi buna göre
            // bastırılır. Varsayılan `false`: bayrak eksikse yön gösterilir
            // (eski davranış korunur).
            isFlatChange: args["isFlatChange"] as? Bool ?? false,
            // Varsayılan AÇIK: bayrak eksikse "Piyasa kapalı" etiketi
            // gösterilmez. Yanlışlıkla "kapalı" demek, gerçekten canlı
            // veriye bakan kullanıcıyı yanıltırdı.
            isMarketOpen: args["isMarketOpen"] as? Bool ?? true
        )
    }
}

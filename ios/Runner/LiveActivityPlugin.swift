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
@available(iOS 16.1, *)
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
                staleDate: state.sessionEndsAt
            )
            current = try Activity.request(
                attributes: attributes,
                content: content,
                // Push token istenmiyor: güncellemeler uygulama önplandayken
                // yerel olarak yapılır. Push ile güncelleme ileride
                // eklenirse burası `.token` olur (bkz. TECHNICAL_DEBT.md).
                pushType: nil
            )
            return true
        } catch {
            NSLog("[Sandik] Live Activity başlatılamadı: \(error.localizedDescription)")
            return false
        }
    }

    /// Yürüyen oturumun içeriğini tazeler. Oturum yoksa sessizce `false`.
    @discardableResult
    static func update(state: SandikActivityAttributes.ContentState) -> Bool {
        guard let activity = resolveCurrent() else { return false }

        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: state.sessionEndsAt)
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

        channel.setMethodCallHandler { call, result in
            // iOS 16.1 altında ActivityKit hiç yok. Uygulama minimumu 17.0
            // olsa da bu kapı bırakılır: hedef ileride düşerse çökme değil,
            // "desteklenmiyor" yanıtı döner.
            guard #available(iOS 16.1, *) else {
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
    @available(iOS 16.1, *)
    private static func parseState(_ args: [String: Any]) -> SandikActivityAttributes.ContentState? {
        guard let total = args["totalText"] as? String,
              let change = args["changeText"] as? String,
              let pct = args["changePctText"] as? String,
              let isPositive = args["isPositive"] as? Bool,
              let updatedAt = args["updatedAtText"] as? String else {
            return nil
        }

        // Dart `DateTime.millisecondsSinceEpoch` gönderir. Alan yoksa
        // (ör. `end` çağrısı) şimdiden 1 saat sonrası varsayılır; staleDate
        // olarak zararsız bir değerdir.
        let endsMs = args["sessionEndsAtMs"] as? Int
        let endsAt = endsMs.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
            ?? Date().addingTimeInterval(3600)

        return SandikActivityAttributes.ContentState(
            totalText: total,
            changeText: change,
            changePctText: pct,
            isPositive: isPositive,
            isHidden: args["isHidden"] as? Bool ?? false,
            updatedAtText: updatedAt,
            sessionEndsAt: endsAt
        )
    }
}

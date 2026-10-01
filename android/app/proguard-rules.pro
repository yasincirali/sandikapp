# R8 kuralları — sandık.
#
# 2026-10-01 daraltma (CPU/GPU ve boyut raporu): eski dosya Flutter gömülü
# katmanı, Firebase ve Google Play Services'in TAMAMINI `{ *; }` ile
# tutuyordu. Bu kütüphaneler kendi tüketici (consumer) kurallarını AAR
# içinde taşır; Flutter'ın kendi kuralları da `flutter_proguard_rules.pro`
# ile her build'e eklenir. Geniş keep'ler R8'in kullanılmayan GMS/Firebase
# kodunu atmasını engelliyordu (DEX'in %35'i GMS). Her kalan satırın
# gerekçesi yanında; yeni satır eklerken gerekçesiz bırakma.
#
# Kaldırılanlar ve nedeni:
#   -keep class io.flutter.** { *; }           → Flutter kendi kurallarını
#                                                 ekler (FlutterPlugin
#                                                 uygulayıcıları korunur).
#   -keep class com.google.firebase.** { *; }  → Firebase AAR consumer
#   -keep class com.google.android.gms.** {*;} → kuralları yeterli.
#   kotlinx.serialization / coroutines kuralları → DEX'te bu paketler yok
#                                                 (Supabase istemcisi Dart).
#   MPAndroidChart                             → kullanılmıyor (fl_chart Dart).

# Uyarı susturma: plugin'ler Firebase/GMS'in isteğe bağlı sınıflarına
# referans verir; eksikleri hata değil.
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# flutter_local_notifications: bildirim modellerini Gson ile yansıma
# üzerinden serileştirir; paketin README'si bu kuralı zorunlu tutar.
-keep class com.dexterous.** { *; }

# Crashlytics: satır numaralı, okunabilir yığın izi için. İstisna
# sınıfları yansıma ile raporlanır.
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# Uygulamanın kendi Kotlin sınıfları: widget sağlayıcı ve MainActivity
# manifestten zaten korunur; `home_widget` geri çağrı dağıtıcısı ve
# platform kanalı sınıf adıyla eşleşir. Küçük paket, geniş tutmak ucuz.
-keep class com.sandik.app.** { *; }

# Genel: generic imzalar ve ek açıklamalar (Firebase, AndroidX yansıması).
-keepattributes Signature
-keepattributes Exceptions
-keepattributes *Annotation*, InnerClasses

# Play Core (Flutter deferred components — kullanılmasa da R8 referans buluyor)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

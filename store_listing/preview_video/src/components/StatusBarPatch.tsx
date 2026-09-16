// Ekran kaydı göstergesini örten yama.
//
// ## Ölçülen arıza (kullanıcı bildirimi, 2026-09-17)
//
// Durum çubuğunun sol üstünde iOS'un KAYIT göstergesi duruyordu:
//   kayit.mov  → kırmızı yuvarlak "kayıt sürüyor" rozeti
//   kayit2.MP4 → kırmızı zeminli saat (23:32)
//
// İkisi de videonun ekran kaydı olduğunu ele veriyor. Apple 2.3.4 zaten
// ekran kaydı İSTİYOR, yani bu bir ihlal değil — ama mağaza sayfasında
// amatör duruyor: kullanıcı uygulamayı değil, birinin telefonunu izliyor
// gibi hissediyor. Her ciddi App Preview'da durum çubuğu temizdir.
//
// ## Neden kırpmak yerine yama
//
// Durum çubuğunu komple kırpmak (üstten %5) kadrajı yukarı kaydırırdı ve
// her sahnenin dikkatle ölçülmüş `startFrom` konumu bozulurdu. Ayrıca
// çentikli ekranda üst şerit uygulamanın kendi zemininin parçası; kesince
// telefon çerçevesi tuhaf görünüyor.
//
// Bunun yerine yalnızca SOL ÜÇTE BİR örtülüyor ve üstüne nötr bir saat
// yazılıyor. Sağdaki sinyal/wifi/pil olduğu gibi kalıyor — onlar gerçek
// bir telefonun doğal parçası ve videoyu inandırıcı kılıyor.
import React from "react";
import { AbsoluteFill } from "remotion";
import { theme } from "../theme";

/**
 * Sol üstteki kayıt göstergesini örter, yerine sade bir saat yazar.
 *
 * Konum oransal: ham kayıt 1126×2436 ve kompozisyon 886×1920 farklı
 * ölçekte, sabit piksel ikisinde de tutmaz.
 *
 * `bg` — örtünün rengi. Uygulamanın kendi zemini koyu yeşil; varsayılan
 * onunla aynı. Şeffaf değil, çünkü altındaki kırmızı rozet sızmamalı.
 */
export const StatusBarPatch: React.FC<{ saat?: string }> = ({
  saat = "9:41",
}) => {
  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      <div
        style={{
          position: "absolute",
          // Ölçüm: rozet ham görüntüde y≈28-100 (2436 yüksekliğinde),
          // x≈100-300. Yama kenarlardan pay bırakarak örter.
          top: "0.6%",
          left: "0%",
          width: "34%",
          height: "3.9%",
          background: theme.colors.bg,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <span
          style={{
            fontFamily: theme.fonts.body,
            // Apple'ın kendi tanıtım materyallerinde kullandığı saat.
            // Nötr ve tanıdık; "9:41" bir markanın değil, konvansiyonun
            // parçası.
            fontSize: 34,
            fontWeight: 600,
            color: theme.colors.text,
            letterSpacing: "-0.01em",
          }}
        >
          {saat}
        </span>
      </div>
    </AbsoluteFill>
  );
};

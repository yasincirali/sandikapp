// Gerçek kişi adını örten maske.
//
// Apple 2.3.9: "you should display fictional account information instead of
// data from a real person." Placeholder ekran görüntülerinde ortak seçicide
// gerçek bir isim ("sila") görünüyor — kare 40 ve 470'te doğrulandı.
//
// Bu maske GEÇİCİ bir emniyet ağıdır. Doğru çözüm, çekimi kurgusal hesapla
// yapmaktır (CEKIM_SENARYOSU.md adım 0) — o zaman HAS_CAPTURE true olur ve
// bu maske gereksizleşir, kaldırılabilir.
import React from "react";
import { AbsoluteFill } from "remotion";
import { theme } from "../theme";
import { HAS_CAPTURE } from "./Capture";

/**
 * Ortak seçicideki isim alanını örter.
 *
 * `top` — maskelenecek şeridin dikey konumu (kare yüksekliğine oranla).
 * Sahneye göre değişir: Ana ekranda seçici daha aşağıda, Performans'ta
 * daha yukarıda.
 */
export const PrivacyMask: React.FC<{ topRatio: number }> = ({ topRatio }) => {
  // Gerçek kayıt kurgusal hesapla alındıysa maskeye gerek yok.
  if (HAS_CAPTURE) return null;

  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      <div
        style={{
          position: "absolute",
          top: `${topRatio * 100}%`,
          right: "6%",
          width: "26%",
          height: "3.2%",
          // Uygulamanın kendi yüzey rengiyle aynı: yama gibi durmasın.
          background: theme.colors.surface1,
          borderRadius: 999,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontFamily: theme.fonts.body,
          fontSize: 30,
          fontWeight: 500,
          color: theme.colors.text58,
        }}
      >
        Ayşe
      </div>
    </AbsoluteFill>
  );
};

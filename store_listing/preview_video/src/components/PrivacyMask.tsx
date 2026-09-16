// Gerçek hesap adını örten maske.
//
// Apple 2.3.9: "you should display fictional account information instead of
// data from a real person."
//
// ## Neden hâlâ gerekli (2026-09-16)
//
// Kayıt geldi ama KURGUSAL hesapla değil, gerçek hesapla alındı: ortak
// seçicide "Birlikte / Ben / Test" yazıyor ve "Test" gerçek bir hesap adı.
// Maske onu kurgusal bir adla örter.
//
// Bu bir emniyet ağıdır, çözüm değil. Kalıcı çözüm çekimi demo portföy ve
// kurgusal ortak adlarıyla tekrarlamak (CEKIM_SENARYOSU.md §2). O zaman bu
// bileşen tamamen kaldırılabilir.
//
// ⚠️ `HAS_CAPTURE` ile KAPATILMAZ. Eskiden "gerçek kayıt varsa maske
// gereksiz" varsayımıyla erken dönüyordu; o varsayım ancak kayıt kurgusal
// hesapla alınmışsa doğru. Burada değil — bayrağa bakıp kapanmak gerçek
// adı mağazaya gönderirdi.
import React from "react";
import { AbsoluteFill } from "remotion";
import { theme } from "../theme";

/**
 * Ortak seçicideki isim alanını örter.
 *
 * `topRatio` — maskelenecek şeridin dikey konumu (kare yüksekliğine oranla).
 * Sahneye göre değişir: Ana ekranda seçici aşağıda, Performans'ta yukarıda.
 */
export const PrivacyMask: React.FC<{ topRatio: number }> = ({ topRatio }) => {
  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      <div
        style={{
          position: "absolute",
          // Ölçüm: 886×1920 render'ında "Test" segmenti y≈1035 merkezli,
          // yüksekliği ≈84px, sağ kenarı x≈830. Oranlar oradan türetildi.
          top: `${topRatio * 100}%`,
          right: "6.3%",
          width: "22.6%",
          height: "4.4%",
          // Uygulamanın kendi yüzey rengiyle aynı: yama gibi durmasın.
          background: theme.colors.surface1,
          borderRadius: 999,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontFamily: theme.fonts.body,
          // 30px, 886 genişlikte segment yazısının yanında küçük kalıyordu;
          // uygulamanın kendi etiket boyutuna yakın.
          fontSize: 38,
          fontWeight: 500,
          color: theme.colors.text58,
        }}
      >
        Ayşe
      </div>
    </AbsoluteFill>
  );
};

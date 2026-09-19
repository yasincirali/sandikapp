// DM Sans — uygulamanın fontu, assets/fonts'tan public/fonts'a kopyalandı.
// Sistem yığınına düşmesin: render makinesinde Segoe UI çıkıyordu ve
// wordmark uygulamadakinden farklı görünüyordu.
//
// loadFont delayRender'ı kendi içinde yönetir; modülün import edilmesi yeter.
import { loadFont } from "@remotion/fonts";
import { staticFile } from "remotion";

const WEIGHTS: Record<string, string> = {
  "400": "Regular",
  "500": "Medium",
  "600": "SemiBold",
  "700": "Bold",
  "800": "ExtraBold",
  "900": "Black",
};

export const FONT_FAMILY = "DM Sans";

export const fontsReady = Promise.all(
  Object.entries(WEIGHTS).map(([weight, name]) =>
    loadFont({
      family: FONT_FAMILY,
      url: staticFile(`fonts/DMSans-${name}.ttf`),
      weight,
      format: "truetype",
    }),
  ),
);

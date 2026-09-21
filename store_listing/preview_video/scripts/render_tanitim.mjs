// Tanıtım videosunu (Tanitim, 1920×1080) render eder.
//   node scripts/render_tanitim.mjs check   # yalnızca kontrol kareleri → out/check_tanitim/
//   node scripts/render_tanitim.mjs         # kareler + video → out/sandik_tanitim_16x9.mp4
import { spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import path from "node:path";

const OUT = path.resolve("out");
const CHECK = path.resolve("out/check_tanitim");
mkdirSync(CHECK, { recursive: true });

// Sahne ortaları (114 BPM, 15,79 kare/vuruş): kanca 30 · ana ekran 130/180 ·
// bugün 240/290 · kazanç 360/400 · enflasyon 470/500 · ortak 540/590 ·
// bildirim 650/690 · CTA 760.
const FRAMES = [30, 130, 180, 240, 290, 360, 400, 470, 500, 540, 590, 650, 690, 760];

const run = (args) => {
  const r = spawnSync("npx", ["remotion", ...args], { stdio: "inherit", shell: true });
  if (r.status !== 0) {
    console.error(`\n✗ remotion ${args.join(" ")} — çıkış kodu ${r.status}`);
    process.exit(r.status ?? 1);
  }
};

const mode = process.argv[2];
for (const f of FRAMES) {
  run(["still", "src/index.ts", "Tanitim", path.join(CHECK, `t_${f}.png`), "--frame", String(f), "--overwrite"]);
}
if (mode === "check") process.exit(0);

run([
  "render", "src/index.ts", "Tanitim", path.join(OUT, "sandik_tanitim_16x9.mp4"),
  "--codec", "h264", "--crf", "17",
  "--audio-codec", "aac", "--audio-bitrate", "256k",
  "--overwrite",
]);
console.log(`\n✓ ${path.join(OUT, "sandik_tanitim_16x9.mp4")}`);

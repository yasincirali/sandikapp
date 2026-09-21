// App Store önizlemesini (Onizleme30, 886×1920, 30 sn) render eder.
//   node scripts/render_onizleme30.mjs check   # yalnızca kontrol kareleri
//   node scripts/render_onizleme30.mjs         # kareler + video
//
// Kareler out/check30/, video out/sandik_onizleme_30sn.mp4.
import { spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import path from "node:path";

const OUT = path.resolve("out");
const CHECK = path.resolve("out/check30");
mkdirSync(CHECK, { recursive: true });

// Sahne ortaları (114 BPM ızgarası): kanca 20 · enflasyon 190 · günlük 290 ·
// nereden geldi 480 · varlık 580 · birlikte 780 · kapanış 860.
const FRAMES = [20, 100, 190, 290, 380, 480, 580, 680, 780, 860];

const run = (args) => {
  const r = spawnSync("npx", ["remotion", ...args], { stdio: "inherit", shell: true });
  if (r.status !== 0) {
    console.error(`\n✗ remotion ${args.join(" ")} — çıkış kodu ${r.status}`);
    process.exit(r.status ?? 1);
  }
};

for (const f of FRAMES) {
  run([
    "still", "src/index.ts", "Onizleme30",
    path.join(CHECK, `o_${f}.png`), "--frame", String(f), "--overwrite",
  ]);
}
if (process.argv[2] === "check") process.exit(0);

run([
  "render", "src/index.ts", "Onizleme30",
  path.join(OUT, "sandik_onizleme_30sn.mp4"),
  "--codec", "h264", "--crf", "17",
  "--audio-codec", "aac", "--audio-bitrate", "256k",
  "--overwrite",
]);
console.log(`\n✓ ${path.join(OUT, "sandik_onizleme_30sn.mp4")}`);

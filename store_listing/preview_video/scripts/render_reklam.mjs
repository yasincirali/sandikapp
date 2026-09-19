// Reklam paketini render eder: 3 video + 5 görsel → store_listing/reklam/out/
// Kontrol kareleri → store_listing/reklam/check/ (gözle bakılır, teslim değil).
//
//   node scripts/render_reklam.mjs            # hepsi
//   node scripts/render_reklam.mjs check      # yalnızca kontrol kareleri
//   node scripts/render_reklam.mjs AdReel     # tek kompozisyon
import { spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import path from "node:path";

const OUT = path.resolve("../reklam/out");
const CHECK = path.resolve("../reklam/check");
mkdirSync(OUT, { recursive: true });
mkdirSync(CHECK, { recursive: true });

const VIDEOS = [
  ["AdReel", "sandik_reel_9x16_15s.mp4"],
  ["AdSquare", "sandik_kare_1x1_12s.mp4"],
  ["AdBumper", "sandik_bumper_16x9_6s.mp4"],
];
const STILLS = [
  ["StillSquareEnflasyon", "sandik_kare_enflasyon_1080.png"],
  ["StillSquareAltin", "sandik_kare_altin_1080.png"],
  ["StillSquareOrtak", "sandik_kare_ortak_1080.png"],
  ["StillStory", "sandik_hikaye_1080x1920.png"],
  ["StillBanner", "sandik_banner_1600x900.png"],
];
// Sahne ortaları: her sahnenin girişi oturmuş, çıkışı başlamamış kareler.
const CHECK_FRAMES = {
  AdReel: [20, 55, 100, 150, 200, 250, 300, 340, 420],
  AdSquare: [30, 100, 170, 280, 340],
  AdBumper: [10, 40, 90, 150],
};

const run = (args) => {
  const r = spawnSync("npx", ["remotion", ...args], { stdio: "inherit", shell: true });
  if (r.status !== 0) {
    console.error(`\n✗ remotion ${args.join(" ")} — çıkış kodu ${r.status}`);
    process.exit(r.status ?? 1);
  }
};

const only = process.argv[2];

if (!only || only === "check") {
  for (const [id, frames] of Object.entries(CHECK_FRAMES)) {
    for (const f of frames) {
      run(["still", "src/index.ts", id, path.join(CHECK, `${id}_${f}.png`), "--frame", String(f), "--overwrite"]);
    }
  }
  if (only === "check") process.exit(0);
}

for (const [id, file] of VIDEOS) {
  if (only && only !== id) continue;
  run([
    "render", "src/index.ts", id, path.join(OUT, file),
    "--codec", "h264", "--crf", "17",
    "--audio-codec", "aac", "--audio-bitrate", "256k",
    "--overwrite",
  ]);
}

for (const [id, file] of STILLS) {
  if (only && only !== id) continue;
  run(["still", "src/index.ts", id, path.join(OUT, file), "--overwrite"]);
}

console.log(`\n✓ Çıktılar: ${OUT}`);

// Minimal ses kiti — indirme yok, tamamen sentetik 16-bit WAV.
//
// Neden sentetik: hazır müzik/SFX kullanmak Apple 2.3.9 gereği lisans
// sorumluluğu doğurur ("You are responsible for securing the rights to use
// all materials"). Burada üretilen her örnek bu betikten çıkar — telif
// zinciri yok, deterministik, tekrar üretilebilir.
import fs from "node:fs";
import path from "node:path";

const SR = 44100;
const OUT = path.join(process.cwd(), "public", "sfx");
fs.mkdirSync(OUT, { recursive: true });

/** Float [-1,1] örneklerini STEREO 16-bit PCM WAV'a yazar (spec: stereo). */
function writeWav(name, samples) {
  const n = samples.length;
  const bytesPerSample = 2;
  const channels = 2;
  const dataSize = n * bytesPerSample * channels;
  const buf = Buffer.alloc(44 + dataSize);

  buf.write("RIFF", 0);
  buf.writeUInt32LE(36 + dataSize, 4);
  buf.write("WAVE", 8);
  buf.write("fmt ", 12);
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20); // PCM
  buf.writeUInt16LE(channels, 22);
  buf.writeUInt32LE(SR, 24);
  buf.writeUInt32LE(SR * channels * bytesPerSample, 28);
  buf.writeUInt16LE(channels * bytesPerSample, 32);
  buf.writeUInt16LE(16, 34);
  buf.write("data", 36);
  buf.writeUInt32LE(dataSize, 40);

  let off = 44;
  for (let i = 0; i < n; i++) {
    const v = Math.max(-1, Math.min(1, samples[i]));
    const s = Math.round(v * 32767);
    buf.writeInt16LE(s, off); // L
    buf.writeInt16LE(s, off + 2); // R
    off += 4;
  }
  fs.writeFileSync(path.join(OUT, name), buf);
  console.log("+", name, (dataSize / 1024).toFixed(0) + "KB");
}

const env = (i, n, attack = 0.01, release = 0.3) => {
  const t = i / SR;
  const dur = n / SR;
  const a = Math.min(1, t / attack);
  const r = Math.min(1, (dur - t) / release);
  return Math.max(0, a * r);
};

/** Yumuşak whoosh — sahne geçişi. Filtrelenmiş gürültü. */
function whoosh(durSec = 0.45) {
  const n = Math.floor(SR * durSec);
  const out = new Float32Array(n);
  let lp = 0;
  for (let i = 0; i < n; i++) {
    const t = i / n;
    const noise = Math.random() * 2 - 1;
    // Alçak geçiren katsayısı zamanla açılır: "süpürme" hissi
    const k = 0.02 + 0.22 * Math.sin(Math.PI * t);
    lp += k * (noise - lp);
    out[i] = lp * env(i, n, 0.05, 0.25) * 0.5;
  }
  return out;
}

/** Yumuşak tık/pop — metin girişi. Perde düşen sinüs. */
function pop(durSec = 0.16) {
  const n = Math.floor(SR * durSec);
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const f = 760 * Math.exp(-14 * t); // hızlı perde düşüşü
    out[i] = Math.sin(2 * Math.PI * f * t) * env(i, n, 0.004, 0.12) * 0.32;
  }
  return out;
}

/** Kapanış vuruşu — derin sinüs thump. */
function thump(durSec = 0.7) {
  const n = Math.floor(SR * durSec);
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const f = 110 * Math.exp(-5 * t);
    out[i] = Math.sin(2 * Math.PI * f * t) * env(i, n, 0.005, 0.5) * 0.55;
  }
  return out;
}

/**
 * Müzik yatağı — sakin, ilerlemeyen pad.
 *
 * Finans uygulaması için sakin ton doğru: agresif müzik "trade et, kazan"
 * vaadi ima eder; burada anlatılan şey takip ve netlik.
 * Akor: Fa majör 9 civarı, hafif detune ile canlılık.
 */
function pad(durSec = 24.5) {
  const n = Math.floor(SR * durSec);
  const out = new Float32Array(n);
  const partials = [
    { f: 87.31, a: 0.3 }, // F2
    { f: 130.81, a: 0.22 }, // C3
    { f: 174.61, a: 0.18 }, // F3
    { f: 261.63, a: 0.12 }, // C4
    { f: 329.63, a: 0.09 }, // E4
  ];
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    let v = 0;
    for (const p of partials) {
      // İki hafif detune'lu osilatör: statik sinüsten daha canlı
      v += Math.sin(2 * Math.PI * p.f * t) * p.a;
      v += Math.sin(2 * Math.PI * (p.f * 1.003) * t) * p.a * 0.6;
    }
    // Çok yavaş genlik dalgalanması — "nefes".
    //
    // Derinlik 0,45 → 0,14 (2026-09-16). Ölçülen arıza: 0,055 Hz'in
    // periyodu 18,2 sn ve 24 sn'lik videoda çukur tam 12–14. saniyeye
    // düşüyordu. Çarpan orada 0,10'a iniyor, yani pad SUSUYORDU: render
    // edilen sesin saniyelik RMS'i 13. sn'de 81'e düşüp 19. sn'de 2890'a
    // fırlıyordu (36× fark). İzleyici sesi kısık sanıp ya da kesinti var
    // sanıp bırakıyor.
    //
    // "Nefes" etkisi korunuyor ama artık duyulabilir bir dalga, sessizlik
    // değil: 0,86–1,00 arası. Tek bir LFO periyodunun videodan uzun
    // olması sorunun kaynağıydı; derinliği kısmak periyodu değiştirmeden
    // çözüyor ve pad'in karakterini bozmuyor.
    v *= 0.86 + 0.14 * Math.sin(2 * Math.PI * 0.055 * t);
    // Giriş/çıkış fade
    const fadeIn = Math.min(1, t / 2.0);
    const fadeOut = Math.min(1, (durSec - t) / 2.5);
    out[i] = v * 0.16 * fadeIn * Math.max(0, fadeOut);
  }
  return out;
}

writeWav("whoosh.wav", whoosh());
writeWav("pop.wav", pop());
writeWav("thump.wav", thump());
writeWav("pad.wav", pad());
console.log("Ses kiti hazır.");

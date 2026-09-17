"""Sahne kliplerini ve anlatım WAV'larını üretir.

1) public/shots/kayit*.mov -> composition/assets/clips/*.mp4 (886x1920, 30 fps, sessiz)
   Zamanlar Preview.tsx'teki ölçülmüş startFrom değerleri. Kanıt klibi ayrıca
   tpad ile dondurulur (kart 2 sn'de ekrandan kayıyordu).
2) composition/assets/vo/*.mp3 (edge-tts çıktısı) -> *.wav 48k mono, baş/son
   sessizlik kırpılmış. Süreler index.html SCENES tablosuna elle girilir.

Anlatımı üretmek için (Kokoro'da Türkçe yok):
  python -m edge_tts --voice tr-TR-AhmetNeural --rate=+0% --text "..." --write-media a_01_rozet.mp3
"""
import subprocess, wave, array, os, glob, sys
FF = r"C:\projects\PortfoyTakip\store_listing\preview_video\node_modules\@remotion\compositor-win32-x64-msvc\ffmpeg.exe"
FP = FF.replace("ffmpeg.exe", "ffprobe.exe")
P = os.path.normpath(os.path.join(HERE, "..", ".."))
CLIPS = os.path.join(P, "brag-output", "composition", "assets", "clips")
VO = os.path.join(P, "brag-output", "composition", "assets", "vo")
os.makedirs(CLIPS, exist_ok=True)
def dur(f):
    return float(subprocess.check_output([FP, "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", f]).decode().strip())
# 1) Sahne klipleri — 886x1920, 30 fps, sessiz. Kaynak: Preview.tsx'teki ölçülmüş startFrom değerleri.
cuts = [("rozet","kayit.mov",0.9,7),("ekle","kayit2.MP4",18.6,8),
        ("alarm","kayit2.MP4",34.3,7),("takip","kayit2.MP4",67.8,7),("dagilim","kayit.mov",64.5,8),("kapanis","kayit.mov",92.0,2.6)]
for name, src, ss, t in cuts:
    out = os.path.join(CLIPS, name + ".mp4")
    subprocess.check_call([FF,"-y","-v","error","-ss",str(ss),"-t",str(t),"-i",os.path.join(P,"public","shots",src),"-an",
        "-vf","scale=886:1920:flags=lanczos,fps=30","-c:v","libx264","-preset","fast","-crf","18","-pix_fmt","yuv420p","-movflags","+faststart",out])
    print(f"clip {name:8s} {dur(out):5.2f}s")
# Kanıt: 0,75 sn kaydırma + son kare 5,6 sn dondurulur
out = os.path.join(CLIPS, "kanit.mp4")
subprocess.check_call([FF,"-y","-v","error","-ss","38.2","-t","0.75","-i",os.path.join(P,"public","shots","kayit.mov"),"-an",
    "-vf","scale=886:1920:flags=lanczos,fps=30,tpad=stop_mode=clone:stop_duration=5.6",
    "-c:v","libx264","-preset","fast","-crf","18","-pix_fmt","yuv420p","-movflags","+faststart",out])
print(f"clip kanit    {dur(out):5.2f}s (dondurmalı)")
# 2) Anlatım: mp3 -> wav 48k mono, baş/son sessizlik kırpma (-45 dBFS, 30 ms pencere, 60 ms pay)
thr = int(32767 * 10 ** (-45/20))
for mp3 in sorted(glob.glob(os.path.join(VO, "*.mp3"))):
    raw = mp3[:-4] + ".raw.wav"
    subprocess.check_call([FF,"-y","-v","error","-i",mp3,"-ar","48000","-ac","1","-c:a","pcm_s16le",raw])
    w = wave.open(raw); sr = w.getframerate(); data = array.array('h', w.readframes(w.getnframes())); w.close()
    win = sr*30//1000
    loud = lambda i: max((abs(x) for x in data[i:i+win]), default=0) > thr
    s = 0
    while s+win < len(data) and not loud(s): s += win
    e = len(data)
    while e-win > s and not loud(e-win): e -= win
    pad = sr*60//1000; s = max(0, s-pad); e = min(len(data), e+pad)
    out = mp3[:-4] + ".wav"
    o = wave.open(out,'w'); o.setnchannels(1); o.setsampwidth(2); o.setframerate(sr); o.writeframes(data[s:e].tobytes()); o.close()
    os.remove(raw); os.remove(mp3)
    print(f"vo   {os.path.basename(out):18s} {(e-s)/sr:5.2f}s (ham {len(data)/sr:.2f})")

// Sessiz saatler — kullanıcı başına TEK global pencere, tüm proaktif push'lar.
//
// RETENTION_STRATEJISI.md bildirim bütçesini kilit kısıt sayıyor; 2026-09
// değerlendirmesi §5.8: sinyal tercihlerinde tür başına pencere vardı ama
// brifing/haftalık özet/takvim/alarm için kullanıcının "gece bana yazma"
// diyebileceği tek bir yer yoktu. `profiles.quiet_start` / `quiet_end`
// (TR saati, 0-23; ikisi de null → kapalı).
//
// Gece yarısını saran pencere desteklenir: 22 → 07 demek 22:00–06:59.
// start == end anlamsızdır; kapalı sayılır (kullanıcıyı 7/24 susturmak
// bir ayar hatası olurdu).
//
// Alarm gibi zamana duyarlı push'lar sessiz saatte ATLANIR, ertelenmez:
// ertelemek "kuyruk" ister ve sabah 07:00'de üst üste beş bildirim demek.
// Alarm damgası da atılmaz — pencere bitince koşul sürüyorsa bir sonraki
// turda gider.

import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

/// Şu anki TR saati (0-23). TR sabit UTC+3, yaz saati yok (2016+).
export function istanbulHour(now: Date): number {
  return (now.getUTCHours() + 3) % 24;
}

/// Verilen TR saati pencerenin içinde mi.
export function sessizSaatteMi(
  hourTR: number,
  start: number | null | undefined,
  end: number | null | undefined,
): boolean {
  if (start == null || end == null) return false;
  if (!Number.isInteger(start) || !Number.isInteger(end)) return false;
  if (start < 0 || start > 23 || end < 0 || end > 23) return false;
  if (start === end) return false;
  if (start < end) return hourTR >= start && hourTR < end;
  // Sarmalı: 22 → 7
  return hourTR >= start || hourTR < end;
}

/// Verilen kullanıcılardan ŞU AN sessiz saatte olanların kümesi.
///
/// Profil okunamazsa BOŞ küme döner (kimse susturulmaz): tercihi bilmemek,
/// herkesi susturmaktan daha güvenli bir varsayımdır — mevcut
/// `weekly_summary_push` mantığıyla aynı.
export async function sessizKullanicilar(
  admin: SupabaseClient,
  userIds: string[],
  now: Date = new Date(),
): Promise<Set<string>> {
  const out = new Set<string>();
  const ids = [...new Set(userIds)];
  if (ids.length === 0) return out;
  const saat = istanbulHour(now);
  try {
    const { data } = await admin
      .from('profiles')
      .select('id, quiet_start, quiet_end')
      .in('id', ids);
    for (const p of (data ?? []) as Array<Record<string, unknown>>) {
      const s = p.quiet_start as number | null | undefined;
      const e = p.quiet_end as number | null | undefined;
      if (sessizSaatteMi(saat, s, e)) out.add(String(p.id));
    }
  } catch (_) {
    // Sessizce boş küme.
  }
  return out;
}

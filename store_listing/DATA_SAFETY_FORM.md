# Google Play Data Safety Form — sandık

> Play Console → Uygulama içeriği → Veri güvenliği bölümüne kopyalanacak referans.
> **App Store Connect'teki App Privacy beyanıyla birebir aynı olmalıdır** —
> Apple veri tipleri ile Play karşılıklarının eşleme tablosu:
> [`PLAY_STORE_YAYIN_REHBERI.md` §12.2](../PLAY_STORE_YAYIN_REHBERI.md#122-soru-farklı-cevap-aynı-olmalı--taksonomi-eşlemesi). Aşağıdaki satırları formda ilgili checkbox'lara işaretle. Her satır "veri toplanır", "veri paylaşılır" vb. kutucuklarında Play Console'un istediği format.

## Data collection & sharing summary

- **Does your app collect or share any of the required user data types?** Yes
- **Is all of the user data collected by your app encrypted in transit?** Yes (TLS 1.2+)
- **Do you provide a way for users to request that their data is deleted?** Yes (In-app: Profile → Settings → Delete Account; Web: https://yasincirali.github.io/sandikapp/data-deletion)

## Data types

### Personal info
| Data type | Collected | Shared | Optional | Purpose |
|---|---|---|---|---|
| Name (display name) | ✅ | ❌ | Required | App functionality (partner leaderboard shows display name to invited partners only) |
| Email address | ✅ | ❌ | Required | Account management, authentication |
| User IDs (Supabase UUID) | ✅ | ❌ | Required | Account management |

### Financial info
| Data type | Collected | Shared | Optional | Purpose |
|---|---|---|---|---|
| User payment info | ❌ | — | — | App does not process payments |
| Purchase history | ❌ | — | — | Not collected |
| Credit score | ❌ | — | — | Not collected |
| Other financial info | ✅ | ❌ | Required | **Portfolio asset records** (symbols, quantities, purchase prices) — stored to provide core tracking functionality. NEVER shared with third parties. Partnership feature shares only with explicitly invited partners. |

### App activity
| Data type | Collected | Shared | Optional | Purpose |
|---|---|---|---|---|
| App interactions | ✅ | ❌ | Required | Analytics (Firebase Analytics — event names, screen views) |
| In-app search history | ❌ | — | — | Not collected |
| Other user-generated content | ✅ | ❌ | Required | Notes attached to asset records (user-controlled) |

### App info & performance
| Data type | Collected | Shared | Optional | Purpose |
|---|---|---|---|---|
| Crash logs | ✅ | ❌ | Required | Firebase Crashlytics — anonymous device ID, stack trace. Sensitive fields (email, password, tokens) are masked before upload. |
| Diagnostics | ✅ | ❌ | Required | Performance metrics (Firebase Analytics) |
| Other app performance data | ✅ | ❌ | Required | Structured error logs (production only, sensitive fields masked) |

### Device or other IDs
| Data type | Collected | Shared | Optional | Purpose |
|---|---|---|---|---|
| Device or other IDs | ✅ | ❌ | Required | FCM push notification token (for partnership invites and signal notifications) |
| **Advertising ID** | ❌ | — | — | **Not collected.** `firebase_analytics` normally merges `com.google.android.gms.permission.AD_ID` into the manifest; it is explicitly removed (`tools:node="remove"` in `android/app/src/main/AndroidManifest.xml`). This matches the iOS declaration (`PrivacyInfo.xcprivacy` → `NSPrivacyTracking=false`). The Privacy Sandbox pair `android.permission.ACCESS_ADSERVICES_AD_ID` / `ACCESS_ADSERVICES_ATTRIBUTION` (added by `play-services-measurement-api`) is removed the same way since 2026-09-27 — the 1.1.6+7 AAB still carried them. Verify after each build: the merged manifest must contain no `AD_ID` and no `ADSERVICES` entry. |

## Special note: Anonymous comparison features (Yarış + Zirvedeki Portföyler)

**Checkbox impact (2026-10-01 review): none.** Both features stay under
"Financial info → Other financial info — Collected ✅, Shared ❌, Optional".
Showing *anonymized* output to other users inside the app is not "sharing"
in Play's sense (no transfer to a third party; anonymous data is exempt), and
Apple's App Privacy label has no "shown to other users" category — the
existing "Other Financial Info → App Functionality, Linked to user" entry
already covers it. What changed is the *optional* column and the purpose
text below; keep both stores' free-text answers in sync with this note.

### Yarış (partner competition + global percentile)
1. **Period return (%)** per user per period (7/30/180/365 days) and
   **asset-type allocation (%)** — no quantities, no TRY amounts, no tickers.
2. Computed **on our servers** twice a day (migrations 0081/0082) — the
   client no longer uploads them — and written only for users who opted in.
3. **Opt-in** (defaults OFF; "Yarış" → "Katıl"). Partners see each other's
   return only after an invitation both accepted.
4. **k-anonymity:** global aggregates need ≥ 8 eligible users (`k_min`, 0031).
5. Retention: **365 days** rolling (0090; was 400 until 2026-10-01).

### Zirvedeki Portföyler (Top Portfolios) — explicit consent since 0091
1. Same two derived percentages plus, for funds, the public **TEFAS fund
   code and its share of the portfolio** (funds < 1 % grouped as "other").
2. **Optional, explicit consent in the app** (KVKK 5(1) / GDPR 6(1)(a)):
   the Top Portfolios screen shows a consent card (what is shared, what is
   not, what you get, how to withdraw); nothing is computed for users who
   do not consent. Withdrawal deletes the user's pool rows immediately.
3. **Reciprocal:** only participants see the list (rank, return %, type
   shares, fund codes — no identity, amounts or quantities).
4. **k-anonymity:** list shown only when the pool has ≥ 8 portfolios; at
   most 4 rows.
5. Retention: 365 days rolling; immediately on withdrawal or account deletion.

Neither feature is shared with third parties.

## Data sharing with third-party providers (processors, not "sharing" in Play sense)

The following third parties act as **data processors** on our instructions (declared as data processors, not "data sharing" per Play's definition):

| Provider | Data | Purpose | Location |
|---|---|---|---|
| Supabase Inc. | All account & app data | Storage, authentication, RLS-enforced access | Japan (AWS Tokyo); migrating to Germany (AWS Frankfurt, EU) |
| Google Firebase (Cloud Messaging, Crashlytics, Analytics, Remote Config) | Push token, crash reports, analytics events | Notification delivery, diagnostics, feature flags | Global (Google) |
| Yahoo Finance / TEFAS / finans.truncgil.com | Only asset ticker symbols (no user identifiers) | Price data retrieval | Global |

## Data deletion

- **In-app:** Profile → Settings → "Hesabımı Sil" (Delete Account). Requires password confirmation. Deletion within 30 days.
- **Web:** https://yasincirali.github.io/sandikapp/data-deletion — public form for users who cannot access the app.
- **Legal retention exception:** Disclaimer acceptance log retained anonymously for 3 years under Turkish CO Art. 146 statute of limitations (documented in privacy policy).

## Encryption

- **In transit:** TLS 1.2+ (enforced by Supabase, Firebase)
- **At rest:** AES-256 (Supabase managed database)

## Data collection is optional?

Most data is required for core app functionality. The following are truly optional:
- Partnership feature (requires explicit invite/acceptance flow)
- Signal notifications (defaults ON, toggleable in Settings)
- Partner notifications (defaults ON, toggleable)
- **Yarış/Competition (defaults OFF, opt-in only)**
- **Zirvedeki Portföyler / Top Portfolios (explicit in-app consent, withdrawable; since 0091)**
- Bulk asset add cart (feature usage optional)

---

**Privacy policy URL:** https://yasincirali.github.io/sandikapp/privacy
**Data deletion URL:** https://yasincirali.github.io/sandikapp/data-deletion

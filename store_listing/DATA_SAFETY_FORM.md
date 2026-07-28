# Google Play Data Safety Form — sandık

> Play Console → Uygulama içeriği → Veri güvenliği bölümüne kopyalanacak referans. Aşağıdaki satırları formda ilgili checkbox'lara işaretle. Her satır "veri toplanır", "veri paylaşılır" vb. kutucuklarında Play Console'un istediği format.

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

## Special note: Anonymous aggregated data (leaderboard/competition)

The "Yarış" (Competition) feature is **entirely opt-in** and processes the following:

1. **Return-on-investment (ROI) percentages** — a single derived percentage per user, per time period (7/30/365 days), uploaded to `user_roi_snapshots`.
2. **Portfolio type allocation percentages** — {asset_type: percent} map (e.g., `{"hisse": 40, "altin": 30}`). **No quantities, no TRY amounts, no ticker symbols.** Uploaded to `user_allocation_snapshots`.

Both are:
- **Opt-in by explicit user consent** (defaults OFF; user must open "Yarış" and tap "Katıl")
- **Guarded by k-anonymity** (minimum 20 participants; below this threshold, no aggregate is exposed)
- **Aggregated by SECURITY DEFINER RPCs** on the server; raw rows are never sent to any client except the row's owner (RLS enforced)
- **Not shared with third parties**

This should be declared under "Financial info → Other financial info" with note that data is only aggregated with strict privacy guardrails and is opt-in.

## Data sharing with third-party providers (processors, not "sharing" in Play sense)

The following third parties act as **data processors** on our instructions (declared as data processors, not "data sharing" per Play's definition):

| Provider | Data | Purpose | Location |
|---|---|---|---|
| Supabase Inc. | All account & app data | Storage, authentication, RLS-enforced access | USA (AWS) |
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
- Bulk asset add cart (feature usage optional)

---

**Privacy policy URL:** https://yasincirali.github.io/sandikapp/privacy
**Data deletion URL:** https://yasincirali.github.io/sandikapp/data-deletion

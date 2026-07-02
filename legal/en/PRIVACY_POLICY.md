# Privacy Policy — sandık

**Effective date:** May 11, 2026
**Last updated:** May 11, 2026
**Version:** 1.0

> **TODO (fill in before publication):** Replace `[COMPANY NAME]`, `[ADDRESS]`, `[TAX ID]`, `[CONTACT EMAIL]`, `[WEBSITE]`, `[DPO]` with real values. If you operate as an individual developer, "company" can be replaced with your name and a contact address. For commercial activity, VERBIS registration in Türkiye may be mandatory (kvkk.gov.tr).

---

## 1. Data Controller

This application (**sandık**, the "App") is operated by `[COMPANY NAME]` ("we", "us", "Company").

- **Address:** `[FULL ADDRESS]`
- **Email:** `[CONTACT EMAIL]`
- **Website:** `[WEBSITE]`

We act as data controller under GDPR Article 4(7) and Turkish KVKK Article 3(1)(ı).

---

## 2. Scope

This policy explains what personal data we collect when you download and use the App, why we collect it, with whom we share it, how long we retain it, and what your legal rights are.

The policy is designed to satisfy the requirements of GDPR (EU 2016/679), Turkish KVKK (Law No. 6698), Apple App Store Privacy Guidelines and Google Play Data Safety.

---

## 3. Data We Collect

### 3.1 Account Data (mandatory)
| Data | Purpose | Legal basis |
|---|---|---|
| Email address | Account creation, login, password reset | GDPR 6(1)(b) — contract |
| Password (hashed) | Authentication | GDPR 6(1)(b) |
| Display name | Visible to other users in the partnership feature | GDPR 6(1)(b) |

### 3.2 In-App Content (entered by user)
| Data | Purpose |
|---|---|
| Asset records (symbol, quantity, purchase price, date, note) | Portfolio tracking (core functionality) |
| Portfolio snapshot history | Performance charts |
| Partnership invite codes & mutual links | Multi-user sharing feature |

### 3.3 Device & Notification Data
| Data | Purpose |
|---|---|
| Push notification token (FCM) | Partnership invite & signal notifications |
| Device model, OS version, app version | Diagnostics (only at disclaimer acceptance) |
| Locale | Language/date format |

### 3.4 Legal Acceptance Records
| Data | Purpose | Legal basis |
|---|---|---|
| Disclaimer acceptance timestamp, IP, version, platform | Proof of investment-advice disclaimer | GDPR 6(1)(c) — legal obligation |

### 3.5 Automatically Collected Data
| Data | Purpose |
|---|---|
| Crash reports (Crashlytics) | Crash diagnostics (no personal data, anonymous device id) |
| Structured error logs | Only in production for **errors**; sensitive fields (email, password, token) are masked |

### Data We Do NOT Collect
- Location
- Contacts
- Photos / camera
- Advertising identifier
- Third-party advertising network tracking data
- Bank account information (the App does not connect to any bank API)

---

## 4. Purposes of Processing

1. To create and maintain your account
2. To store your portfolio on your local device and our servers
3. To compute your performance charts
4. To deliver your partnership invitations
5. To send notifications (only if you have explicitly opted in)
6. To meet legal obligations (disclaimer proof, lawful authority requests)
7. For diagnostics and service improvement
8. To detect abuse, fraud, and cyberattacks (GDPR 6(1)(f) — legitimate interest)

---

## 5. Third-Party Recipients (Data Processors)

| Service | Provider | Data | Purpose | Location |
|---|---|---|---|---|
| Backend & database | Supabase Inc. | All account & app data | Storage, authentication | USA (AWS) |
| Push notifications | Google Firebase Cloud Messaging | Push token, notification content | Notification delivery | Global (Google) |
| Crash reports (when added) | Google Firebase Crashlytics | Device model, OS, error stack trace | Crash diagnostics | Global |
| Stock/fund prices | Yahoo Finance, TEFAS, finans.truncgil.com | NONE — only symbol query is sent | Price retrieval | Global |

**These providers act solely as data processors on our instructions. Controllership remains with us.**

---

## 6. International Data Transfers

Because Supabase and Firebase are hosted in the USA, your data is transferred outside the EEA / Türkiye. Under GDPR Articles 44-49 and KVKK Article 9:

- **For EU/EEA users:** Transfers are made under Standard Contractual Clauses (SCCs) and the providers' GDPR-compliance commitments.
- **For Turkish users:** **Explicit consent** is collected at registration (the consent checkbox in the KVKK Disclosure Document).

The destination country (USA) is not on the Turkish DPA's list of countries with adequate protection; therefore international transfer is based on **explicit consent**.

---

## 7. Retention Periods

| Data | Period |
|---|---|
| Account data | Until account deletion |
| Asset records | Until account deletion |
| Snapshot history | Last 365 days (rolling, older entries auto-deleted) |
| Disclaimer acceptance log | **3 years** after account deletion (Turkish CO Art. 146 statute of limitations) |
| Push token | Auto-deleted on app uninstall or logout |
| Crash reports | 90 days |
| db_logs (errors only) | 30 days |

When you delete your account, all your data — except records with statutory retention listed above — is **permanently deleted within 30 days**.

---

## 8. Your Rights (GDPR Art. 15-22 / KVKK Art. 11)

You may exercise the following rights by contacting us:

- **Right to information**
- **Right of access** — receive a copy of your data
- **Right to rectification**
- **Right to erasure ("right to be forgotten")**
- **Right to data portability** — receive your data in machine-readable JSON format
- **Right to object** to processing based on legitimate interest
- **Right to withdraw consent** at any time

**How to request:**
1. **In-app:** Profile → Settings → "Delete Account" / "Download My Data"
2. **Email:** `[CONTACT EMAIL]` with identity-verification information
3. **Web form:** `[WEBSITE]/data-request`

We respond to requests within **30 days** (GDPR Art. 12(3) / KVKK Art. 13(2)).

**Right to lodge a complaint:**
- EU/EEA: Your local Data Protection Authority
- Türkiye: Kişisel Verileri Koruma Kurumu — kvkk.gov.tr

---

## 9. Children's Data

The App is not intended for users under 18. You confirm being 18+ at registration. If we learn that a user under 18 has provided data, the account is deleted promptly. We do not accept users under 16 (GDPR Art. 8 parental consent threshold).

---

## 10. Data Security

Technical and organizational measures we apply:

- **In transit:** TLS 1.2+ (HTTPS) enforced
- **At rest:** AES-256 encryption (Supabase)
- **Access:** Row-Level Security (RLS) — each user can access only their own data
- **Passwords:** Bcrypt hash (Supabase Auth)
- **Sessions:** JWT, 1-hour access + 7-day refresh; in-app 10-minute idle timeout
- **Logging:** Production logs only errors; sensitive fields (email, password, token) are masked
- **Developer access:** Only during a support request and with customer consent

**Breach notification:**
- Within **72 hours** to the relevant supervisory authority (GDPR Art. 33 / KVKK Art. 12)
- Direct notification to affected users
- Compliance with GDPR Art. 33-34

---

## 11. Cookies and Local Storage

The App runs in a mobile environment, so web cookies are **not used**. Local storage (SharedPreferences, SQLite cache) is used only for:

- Session token (Supabase Auth)
- Theme/language preference
- Saved email (if user opts in)
- Disclaimer acceptance status (local copy)

No third-party tracking, analytics, or advertising SDKs are included.

---

## 12. Investment Advice Disclaimer

**sandık** is a portfolio tracking tool. We are NOT a licensed investment advisor or brokerage. Prices, performance figures, signals and charts shown in the App are for informational purposes only and do not constitute investment advice. Consult a licensed advisor before making investment decisions.

This disclaimer is shown and acknowledged at first launch; the acknowledgement is recorded as legal evidence.

---

## 13. Changes to This Policy

When we change this policy:
- An in-app notification is shown
- The "Last updated" date is refreshed
- Material changes are also sent via email
- Changes that require a new KVKK consent will trigger re-acceptance

If you do not object within 30 days, you are deemed to have accepted the changes.

---

## 14. Contact

For all data protection questions, requests and complaints:

- **Email:** `[CONTACT EMAIL]`
- **Address:** `[FULL ADDRESS]`
- **Data Protection Officer (DPO, if appointed):** `[DPO NAME] — [DPO EMAIL]`

---

*This policy is provided in [Turkish] and [English]. In case of discrepancy, the Turkish version prevails.*

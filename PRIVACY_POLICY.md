# SayWell Privacy Policy

**Last Updated:** July 21, 2026  
**Effective Date:** [Release Date]

## 1. Overview

SayWell is a keyboard and app that translates Singlish (romanized Sinhala) into English. This privacy policy explains how we handle your data.

## 2. Data We Collect

### User Input (Translations)
- **What:** Text you type for translation
- **When:** When you use the keyboard or app
- **How long:** 30 days (cached for faster future translations)
- **Why:** To provide translations and improve accuracy

### Device Identifier
- **What:** Unique device ID (randomly generated)
- **When:** First app launch
- **How long:** While app is installed
- **Why:** Rate limiting (max 60 requests/minute per device)

### Usage Analytics (if enabled)
- We do NOT currently collect usage analytics
- No tracking, no user profiles, no behavioral data

## 3. How We Use Your Data

1. **Translation:** Your text is normalized and sent to Google Gemini API for translation
2. **Caching:** Translations are cached for 30 days to speed up future requests
3. **Improvement:** Cache misses are logged (normalized text only, not raw input) for algorithm improvement
4. **Rate Limiting:** Device ID ensures fair usage limits

## 4. Data Sharing

### Third Parties
- **Google Gemini API:** We send normalized text to Google for translation. See [Google's privacy policy](https://policies.google.com/privacy)
- **No other sharing:** We do NOT sell, share, or disclose your data to third parties

### Government Requests
- We will comply with lawful requests from law enforcement with proper legal process

## 5. Data Security

- **In Transit:** HTTPS encryption on all network connections
- **At Rest:** Encrypted in Cloudflare KV storage
- **Raw Input:** Never logged or stored (only normalized + translation cached)
- **Device ID:** Not linked to personal identity

## 6. Your Rights

- **Access:** You can request your cached translations
- **Delete:** Clear cached phrases in app settings
- **Portability:** Your data is not locked in; translations are your own
- **No Tracking:** We don't track you across other apps or websites

## 7. Data Retention

| Data Type | Retention | Notes |
|-----------|-----------|-------|
| Cached Translations | 30 days | Auto-expires in KV storage |
| Device ID | Until app uninstall | Regenerates on reinstall |
| Logs (misses) | 1 day | For debugging only |
| Personal Data | None | We don't collect any |

## 8. Changes to This Policy

We may update this policy. Material changes will be notified in-app or via release notes.

## 9. Contact

Questions about this privacy policy?  
Email: [contact email]  
GitHub: [github repo]

---

**Key Commitments:**
- ✅ No tracking or profiling
- ✅ No ads or data sales
- ✅ Minimal data collection
- ✅ Transparent about third parties (Google Gemini)
- ✅ User control over cached data

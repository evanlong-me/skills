---
name: fuck-claude-check
description: Detect whether a user appears to be a "Claude China user" via IP geo + request headers. Use whenever the user asks about Claude China restrictions, wants to check if they're flagged, suspects regional blocking, or wants to audit their own fingerprint. Also use when troubleshooting Claude region-lock issues, discussing Anthropic/Monica China policy, or testing VPN/proxy effectiveness against region detection.
metadata:
  author: evanlong-me
---

# Fuck Claude Check

Check whether you appear to be a "Claude China user" using the [`fuck-claude.vercel.app`](https://fuck-claude.vercel.app/) API.

The API evaluates multiple server-side signals (timezone, browser language, emoji rendering, etc.) to produce a risk score from 0–100.

## Output style

### Language

**Always respond in the language matching the user's system locale.** Read `$LANG` from the environment: if it starts with `zh`, reply in Chinese; if `en`, English; if `ja`, Japanese; and so on. If the user explicitly passed a different `Accept-Language` value, follow that instead. This is non-negotiable — the user's terminal speaks their language, and so should you.

### Tone

When presenting results to the user, match the irreverent tone of the service. Dry sarcasm, playful fatalism, and a healthy dose of cynicism about region-locking are welcome. Keep it brief — one good punchline lands harder than five. The tone should land in the detected language too — Chinese sarcasm for Chinese users, English snark for English users, etc.

### What to show

Always break down every signal for the user in a scannable format, e.g. a table:

- **Signal name** — what was checked
- **Result** — the detected value (timezone name, language code, etc.)
- **Weight** — maximum possible score for this signal
- **Score** — how many points this signal contributed
- **Verdict** — a short judgment: ✅ safe / ⚠️ flagged / ❌ high risk / ⸺ not measurable

Present two tables: first the server-side signals (from the API), then the locally-measured browser-only signals (fonts + Intl locale). Follow with a combined estimate out of 100, the risk band, and one dark-humor summary line. The user deserves the full picture — don't leave the 30-point browser gap as a mystery when the command line can fill it.

## Usage

### Basic check (follows system language automatically)

```bash
curl -s -H "Accept-Language: ${LANG%_*}" https://fuck-claude.vercel.app/api/check
```

`${LANG%_*}` strips the locale suffix from `$LANG` — `zh_CN.UTF-8` becomes `zh`, `en_US.UTF-8` becomes `en`, etc. No subprocess, no awk, no shell escaping gotchas.

### Override language explicitly

```bash
curl -s -H "Accept-Language: zh" https://fuck-claude.vercel.app/api/check
```

### JSON output (for programmatic use)

```bash
curl -s "https://fuck-claude.vercel.app/api/check?format=json"
```

### Complete check (fill browser-only gaps locally)

The API's server-side scan covers 70/100 points. The remaining 30 — Chinese fonts (20 pts) and Intl locale (10 pts) — require a browser. But you can approximate them from the command line:

**1. Chinese fonts (20 pts)**

```bash
# Check for CJK fonts — any hit means potential flags
fc-list :lang=zh 2>/dev/null | head -10

# Targeted check for common Chinese font families
for font in PingFang "Hiragino Sans GB" STHeiti STSong "Songti SC" \
  "Heiti SC" "Noto Sans CJK" "Noto Serif CJK" SimSun SimHei \
  "Microsoft YaHei" FangSong KaiTi WenQuanYi; do
  fc-list :family 2>/dev/null | grep -qi "$font" && echo "FOUND: $font"
done
```

Interpretation: one or more Chinese font families installed → likely the full 20 pts. No Chinese fonts → 0 pts. On macOS without `fc-list`, fall back to `system_profiler SPFontsDataType`.

**2. Intl locale (10 pts)**

```bash
echo "LANG=$LANG"
locale | grep -E '^(LANG|LC_ALL|LC_CTYPE)='
```

Interpretation: if `LANG` or `LC_ALL` starts with `zh` (e.g. `zh_CN.UTF-8`), the browser's `Intl.DateTimeFormat().resolvedOptions().locale` will almost certainly report `zh-CN` → the full 10 pts. Otherwise → 0 pts.

**3. Combine into a full 100-point estimate**

Add the API's server-side score (out of 70) to your local font + Intl estimates (out of 30) for a full-picture risk score. Present both the API result and the combined estimate side by side.

## Understanding the response

### Text report

```
┌─────────────────────────────────────────────────────┐
│  Fuck Claude          Claude "China user" check     │
│  Score  4/100   ● LOW RISK                          │
│  🐶You are not a "Claude China user"🐶              │
│                                                     │
│  Signals visible server-side:                       │
│    ● +3   Emoji rendering style · Unknown style     │
│    ·   0   System timezone     · America/Los_Angeles │
│    ·   0   Browser language    · unknown             │
│    ·   0   Timezone offset     · UTC-7              │
│                                                     │
│  Coverage 70/100 · Geo US · America/Los_Angeles     │
└─────────────────────────────────────────────────────┘
```

### JSON output fields

| Field | Type | Description |
|-------|------|-------------|
| `score` | integer | Risk score 0–100 |
| `band` | string | `"low"`, `"medium"`, `"high"` |
| `verdict` | string | Short verdict text |
| `message` | string | Full verdict with emoji |
| `geo.country` | string | Estimated country code |
| `geo.timezone` | string | Estimated timezone |
| `signals[]` | array | Individual signal breakdowns |
| `coverage.measuredWeight` | integer | Server-side measurable weight |
| `coverage.totalWeight` | integer | Total possible weight |

### Risk bands

| Score | Band | Language |
|-------|------|----------|
| 0–33 | low | EN: "Low risk" / ZH: "低风险" |
| 34–66 | medium | EN: "Medium risk" / ZH: "中等风险" |
| 67–100 | high | EN: "High risk" / ZH: "高风险" |

## Signals breakdown

The API measures these signals server-side (70/100 weight):

| Signal | Weight | Description |
|--------|--------|-------------|
| System timezone | 30 | e.g. `America/Los_Angeles`, `Asia/Shanghai` |
| Browser language | 24 | From `Accept-Language` header |
| Emoji rendering style | 8 | `Apple`, `Google`, or `Unknown` |
| Timezone offset | 8 | e.g. `UTC+8`, `UTC-7` |

The remaining 30 points can only be measured in-browser (Chinese fonts + Intl locale).

## Installation via skills.sh

```bash
npx skills add evanlong-me/skills
```

Then use any of the trigger phrases or invoke with:

```bash
/skill fuck-claude-check check my region status
```

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

When presenting results to the user, match the irreverent tone of the service. Dry sarcasm, playful fatalism, and a healthy dose of cynicism about region-locking are welcome. Keep it brief — one good punchline lands harder than five.

## Usage

### Basic check (follows system language automatically)

```bash
curl -s -H "Accept-Language: $(locale | awk -F'=' '/^LANG=/{split($2,a,"."); split(a[1],b,"_"); print b[1]}')" \
  https://fuck-claude.vercel.app/api/check
```

The output language matches the system locale: `zh` for Chinese systems, `en` for English, etc.

### Override language explicitly

```bash
curl -s -H "Accept-Language: zh" https://fuck-claude.vercel.app/api/check
```

### JSON output (for programmatic use)

```bash
curl -s "https://fuck-claude.vercel.app/api/check?format=json"
```

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

# evanlong-me/skills

A collection of reusable agent skills for AI coding agents, following the [Agent Skills](https://agentskills.io/) format.

[![skills.sh](https://skills.sh/b/evanlong-me/skills)](https://skills.sh/evanlong-me/skills)

## Available Skills

### fuck-claude-check

Check whether you appear to be a "Claude China user" via IP geo + request headers. Evaluates server-side signals (timezone, browser language, emoji rendering, etc.) to produce a risk score from 0–100.

**Use when:**

- Checking if you're flagged as a Claude China user
- Troubleshooting Claude region-lock issues
- Discussing Anthropic/Monica China policy
- Testing VPN/proxy effectiveness against region detection
- Auditing your browser fingerprint signals

## Installation

```bash
npx skills add evanlong-me/skills
```

Then the skills will be available to your AI agent automatically based on trigger phrases.

## Structure

```
skills/
├── README.md
├── .gitignore
├── skills.sh.json
└── skills/
    └── fuck-claude-check/
        └── SKILL.md
```

Each skill lives in a subdirectory under `skills/` and contains at minimum a `SKILL.md` file with YAML frontmatter.

## Contributing

This is a personal collection. PRs and issues are welcome for improvements to existing skills.

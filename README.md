# evanlong-me/skills

A collection of reusable agent skills for AI coding agents, following the [Agent Skills](https://agentskills.io/) format.

[![skills.sh](https://skills.sh/b/evanlong-me/skills)](https://skills.sh/evanlong-me/skills)

## Available Skills

### cleanmymac-x

对标 CleanMyMac X，用命令行实现 Mac 系统清理、优化、安全检测、隐私保护等核心功能。

覆盖 8 大模块：系统垃圾清理、隐私痕迹清除、大文件扫描、重复文件查找、恶意软件检测、
性能优化、应用彻底卸载、智能扫描。所有操作遵循 **先扫描预览、再确认清理** 的安全原则。

附带 `scripts/cmx.sh` 一键脚本，支持 `scan` / `clean` / `optimize` / `uninstall` / `status` 等命令。

**Use when:**

- Mac 磁盘空间不足，需要清理缓存和日志
- 想彻底卸载应用并清除残留文件
- 系统运行缓慢，需要释放内存和优化性能
- 想扫描大文件或重复文件回收空间
- 需要检查系统安全状态和恶意软件
- 对标 CleanMyMac X，但希望使用命令行方案

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
evanlong-me/skills/
├── README.md
├── .gitignore
├── skills.sh.json
├── fuck-claude-check/
│   └── SKILL.md
└── cleanmymac-x/
    ├── SKILL.md
    └── scripts/
        ├── cmx.sh
        └── README.md
```

Each skill lives in its own directory at the repo root and contains at minimum a `SKILL.md` file with YAML frontmatter.

## Contributing

This is a personal collection. PRs and issues are welcome for improvements to existing skills.

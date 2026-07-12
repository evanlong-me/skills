---
name: cleanmymac-x
description: A CLI-based macOS system cleanup, optimization, security, and privacy tool — the command-line equivalent of CleanMyMac X. Scan-first, clean-confirmed workflow. Includes the cmx convenience script.
metadata:
  author: evanlong-me
  trigger_phrases: ["clean my mac", "mac cleanup", "system junk", "cache cleanup", "mac optimization", "cleanmymac", "mac utility"]
---

# CleanMyMac X CLI Equivalent

## Overview

CleanMyMac X is the best-known system utility for macOS. This skill implements each of its 8 core modules using native CLI tools:

| # | Module | CleanMyMac X Name | Risk Level |
|---|--------|-------------------|------------|
| 1 | **System Junk** | System Junk | 🟢 Safe |
| 2 | **Privacy** | Privacy | 🟢 Safe |
| 3 | **Large Files** | Large & Old Files | 🟢 Safe |
| 4 | **Duplicates** | Duplicates | 🟢 Safe |
| 5 | **Malware Detection** | Malware Removal | 🟡 Caution |
| 6 | **Performance** | Speed / Maintenance | 🟡 Caution |
| 7 | **App Uninstall** | Uninstaller | 🔴 Irreversible |
| 8 | **Smart Scan** | Smart Scan | 🟢 Safe |

Core principle:

> **Scan first → confirm before cleaning.** All cleanup operations are dry-run by default; actual execution requires explicit confirmation.

## Quick Start

This skill ships with `scripts/cmx.sh`, a convenience script for all modules:

```bash
# System overview (disk/memory/load/security)
bash cmx.sh status

# Smart scan (full module summary)
bash cmx.sh scan

# Clean system junk (preview → confirm)
bash cmx.sh clean system-junk --apply

# Performance optimization
bash cmx.sh optimize --apply

# Uninstall an app
bash cmx.sh uninstall "AppName"
```

You can also run the individual commands shown in each module below for fine-grained control.

---

## Module 1: System Junk

### What it does

CleanMyMac X's System Junk scans these macOS locations:

| Item | Path | CleanMyMac Logic |
|------|------|------------------|
| **User caches** | `~/Library/Caches/` | Per-app cache directories, safe to delete |
| **System caches** | `/Library/Caches/` | Same, some require root |
| **User logs** | `~/Library/Logs/` | Evaluated by file count and age |
| **System logs** | `/Library/Logs/`, `/private/var/log/` | Same |
| **Xcode DerivedData** | `~/Library/Developer/Xcode/DerivedData/` | Build intermediates, safe to delete |
| **Xcode Archives** | `~/Library/Developer/Xcode/Archives/` | Distributed .xcarchive |
| **iOS Backups** | `~/Library/Application Support/MobileSync/Backup/` | Old device backups |
| **Language files** | `*.app/Contents/Resources/*.lproj` | Keep current language, remove extra |
| **Trash** | `~/.Trash/` | Staging area for deleted files |
| **Temp files** | `/private/tmp/`, `/private/var/tmp/` | System temp files |
| **Homebrew cache** | `$(brew --cache)` | Old formula package cache |
| **npm/pnpm/yarn cache** | (package manager cache dirs) | Node ecosystem dep caches |

macOS does not automatically clean app caches and leftover files — that's where this tool comes in.

### Scan

```bash
# ── User caches ──
echo "=== User Caches ===" && du -sh ~/Library/Caches/ 2>/dev/null
echo "Top 10 cache subdirs:" && du -sh ~/Library/Caches/*/ 2>/dev/null | sort -rh | head -10

# ── System caches ──
echo "=== System Caches ===" && du -sh /Library/Caches/ 2>/dev/null

# ── Log files ──
echo "=== User Logs ===" && du -sh ~/Library/Logs/ 2>/dev/null
echo "Logs older than 30 days:" && find ~/Library/Logs -type f -mtime +30 2>/dev/null | wc -l
echo "=== System Logs ===" && du -sh /Library/Logs/ 2>/dev/null
echo "=== var/log ===" && du -sh /private/var/log/ 2>/dev/null

# ── Xcode ──
echo "=== Xcode DerivedData ===" && du -sh ~/Library/Developer/Xcode/DerivedData/ 2>/dev/null
echo "=== Xcode Archives ===" && du -sh ~/Library/Developer/Xcode/Archives/ 2>/dev/null

# ── iOS Backups ──
echo "=== iOS Backups ===" && du -sh ~/Library/Application\ Support/MobileSync/Backup/ 2>/dev/null

# ── Trash ──
echo "=== Trash ===" && du -sh ~/.Trash/ 2>/dev/null

# ── Temp files ──
echo "=== Temp Files ===" && du -sh /private/tmp/ /private/var/tmp/ 2>/dev/null

# ── Homebrew cache (if installed) ──
which brew >/dev/null 2>&1 && echo "=== Homebrew Cache ===" && du -sh $(brew --cache) 2>/dev/null

# ── npm cache (if installed) ──
which npm >/dev/null 2>&1 && echo "=== npm Cache ===" && du -sh $(npm cache dir) 2>/dev/null
```

### Clean

> ⚠️ **Quit running apps before clearing caches.** Deleting caches while an app is running may cause unexpected behavior.

```bash
# 1. Delete logs older than 30 days (safe)
find ~/Library/Logs -type f -mtime +30 -delete 2>/dev/null && echo "✓ Old logs cleaned"

# 2. Clean system logs (needs sudo)
sudo find /private/var/log -type f -mtime +30 -delete 2>/dev/null && echo "✓ System logs cleaned"

# 3. Empty trash
rm -rf ~/.Trash/* 2>/dev/null && echo "✓ Trash emptied"

# 4. Clean Xcode DerivedData (Xcode will rebuild)
rm -rf ~/Library/Developer/Xcode/DerivedData/* 2>/dev/null && echo "✓ DerivedData cleaned"

# 5. Clean Homebrew cache
brew cleanup -s 2>/dev/null && echo "✓ Homebrew cache cleaned"

# 6. Clean npm cache
npm cache clean --force 2>/dev/null && echo "✓ npm cache cleaned"

# 7. Clean user caches (most aggressive, use with care)
# rm -rf ~/Library/Caches/*
```

### Language file cleanup (advanced)

CleanMyMac X removes unused language packs from apps, keeping only your current language:

```bash
# Check which languages an app includes
ls /Applications/Safari.app/Contents/Resources/ | grep lproj

# Keep Chinese and English only, delete the rest (example for one app)
# find /Applications/SomeApp.app -name "*.lproj" ! -name "zh*" ! -name "en*" -exec rm -rf {} +
```

> Do this per-app, not bulk — some apps bundle data in unexpected lproj directories.

---

## Module 2: Privacy

### What it does

CleanMyMac X cleans three types of privacy traces:

| Category | Contents | Path |
|----------|----------|------|
| **Browser traces** | Cache, history, cookies, LocalStorage | Varies by browser |
| **System traces** | Recent files, clipboard, recent searches | Finder / System services |
| **Communication traces** | Message attachments, call history | Messages / FaceTime |

### Scan

```bash
# ── Safari ──
echo "=== Safari ==="
echo "Cache:" && du -sh ~/Library/Caches/com.apple.Safari/ 2>/dev/null
echo "History:" && ls -lh ~/Library/Safari/History.db 2>/dev/null

# ── Chrome ──
echo "=== Google Chrome ==="
echo "Cache:" && du -sh ~/Library/Caches/Google/Chrome/ 2>/dev/null
echo "History file:" && ls -lh ~/Library/Application\ Support/Google/Chrome/Default/History 2>/dev/null

# ── Firefox ──
echo "=== Firefox ==="
ls ~/Library/Application\ Support/Firefox/Profiles/ 2>/dev/null

# ── Recent files ──
echo "=== Recent Files ==="
mdfind "kMDItemLastUsedDate >= \$time.today(-7)" -onlyin ~/Documents 2>/dev/null | head -20

# ── Clipboard ──
echo "=== Clipboard ==="
pbpaste 2>/dev/null | head -3 || echo "(empty)"
```

### Clean

```bash
# Safari cache (safe to clear while browser is running)
rm -rf ~/Library/Caches/com.apple.Safari/* 2>/dev/null

# Chrome cache (clearing while browser is running will force redownload)
rm -rf ~/Library/Caches/Google/Chrome/* 2>/dev/null

# Clear clipboard
pbcopy < /dev/null

# Clear recent files list (takes effect after Finder restart)
osascript -e 'tell application "Finder" to set the name of every item of trash to ""' 2>/dev/null

# Clear Safari browsing history (deletes History.db)
# rm ~/Library/Safari/History.db  # Safari will recreate when launched
```

> After clearing browser caches, resources will redownload on next launch — first load may be slower.

---

## Module 3: Large & Old Files

### What it does

CleanMyMac X uses the Spotlight index (`mdfind`) to quickly locate large files instead of traversing the filesystem.

### Scan

```bash
# Fastest: use Spotlight index to find files > 1GB
mdfind "kMDItemFSSize > 1000000000" 2>/dev/null | head -30

# Show file sizes
mdfind "kMDItemFSSize > 1000000000" 2>/dev/null | while read f; do
  [ -f "$f" ] && echo "$(stat -f%z "$f" 2>/dev/null | xargs -I {} echo "scale=1; {} / 1073741824" | bc 2>/dev/null)GB  $f"
done | sort -rn | head -30

# Fallback: use find (slow, no index needed)
find ~ -type f -size +1G 2>/dev/null -exec ls -lhS {} + | awk '{print $5, $NF}' | head -20

# Find old files (not accessed in over a year)
find ~ -type f -atime +365 2>/dev/null | head -20

# Find large directories
du -sh ~/*/ 2>/dev/null | sort -rh | head -10
du -sh ~/Library/*/ 2>/dev/null | sort -rh | head -10
```

### Clean

Review scan results manually, then `rm` or move to Trash:

```bash
# Safe: move to Trash instead of deleting directly
# osascript -e "tell application \"Finder\" to delete POSIX file \"$PWD/large-file.mp4\""

# Direct delete (after confirmation)
# rm -i /path/to/unwanted/large/file.mkv
```

---

## Module 4: Duplicates

### What it does

CleanMyMac X finds duplicate files by comparing file hashes (MD5/SHA). Same approach using `md5` + `sort` + `uniq`.

### Scan

```bash
# Find duplicates in ~/Documents grouped by MD5
echo "Scanning ~/Documents for duplicates (MD5-based)..."
find ~/Documents -type f -size +1k 2>/dev/null \
  -exec md5 -r {} \; \
  | sort \
  | awk '{seen[$1]++; lines[$1]=lines[$1] ? lines[$1]"\n  "$2 : "  "$2} \
         END{for(h in seen) if(seen[h]>1) printf "--- MD5: %s ---\n%s\n\n", h, lines[h]}'

# Same for ~/Downloads
echo "Scanning ~/Downloads..."
find ~/Downloads -type f -size +1k 2>/dev/null \
  -exec md5 -r {} \; \
  | sort \
  | awk '{seen[$1]++; lines[$1]=lines[$1] ? lines[$1]"\n  "$2 : "  "$2} \
         END{for(h in seen) if(seen[h]>1) printf "--- MD5: %s ---\n%s\n\n", h, lines[h]}'
```

### Clean

Review the scan results, then manually delete duplicates — keep one copy.

---

## Module 5: Malware Detection

### What it does

macOS has multiple built-in security layers:

| Layer | Technology | Description |
|-------|-----------|-------------|
| **XProtect** | Signature scanning | Apple-maintained malware signature database, auto-updated |
| **Gatekeeper** | App notarization check | Blocks un-notarized apps from running |
| **Notarization** | Code signing | Developers must pass Apple review |

CleanMyMac X's Malware Removal is essentially a wrapper around XProtect + scanning common malware installation paths.

### Scan

```bash
# 1. XProtect version and status
xprotect version 2>/dev/null || echo "XProtect unavailable (requires macOS 15+)"

# 2. XProtect full scan (needs root, macOS 15+)
sudo xprotect check --json 2>/dev/null || echo "Requires Full Disk Access"

# 3. Check login items (common persistence point for malware)
osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null

# 4. Check Launch Agents (user-level auto-start items)
ls ~/Library/LaunchAgents/ 2>/dev/null
# Inspect suspicious plists
for f in ~/Library/LaunchAgents/*.plist; do
  [ -f "$f" ] && echo "--- $(basename $f) ---" && plutil -p "$f" 2>/dev/null | grep -E '"Program|ProgramArguments|Label"' | head -5
done

# 5. Check for suspicious processes
ps aux | grep -iE "(adware|spy|trojan|keylogger|miner|crypto)" | grep -v grep

# 6. Check browser extensions (Chrome)
ls ~/Library/Application\ Support/Google/Chrome/Default/Extensions/ 2>/dev/null

# 7. Check system extensions
systemextensionsctl list 2>/dev/null
```

### Security recommendations

- macOS built-in protection (XProtect + Gatekeeper + SIP) is already strong
- Keep the system updated: `softwareupdate --list`
- Only download apps from official sources
- If you suspect infection, try [Malwarebytes for Mac](https://www.malwarebytes.com/mac) (free scan)

---

## Module 6: Performance Optimization

### What it does

CleanMyMac X's Speed module covers:

| Sub-feature | Implementation | Effect |
|-------------|---------------|--------|
| **Free memory** | `purge` command | Clears inactive memory pages |
| **Maintenance scripts** | ~~`periodic`~~ (removed in macOS 15+) | Clean temp files, rotate logs |
| **Flush DNS** | `dscacheutil` + `killall -HUP mDNSResponder` | Clears DNS cache |
| **Rebuild Spotlight** | `mdutil -E` | Fixes search result issues |
| **Dynamic linker cache** | `update_dyld_shared_cache` | Speeds up app launch |

### Execute

```bash
# 1. Free inactive memory (needs sudo)
echo "=== Memory Status ==="
vm_stat | head -10
sudo purge && echo "✓ Memory purged"

# 2. Flush DNS cache
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder && echo "✓ DNS cache flushed"

# 3. Rebuild Spotlight index (takes a while)
# sudo mdutil -E / && echo "✓ Spotlight rebuild triggered"

# 4. Clean system temp files
sudo rm -rf /private/var/tmp/* 2>/dev/null
sudo rm -rf /private/tmp/* 2>/dev/null
echo "✓ Temp files cleaned"

# 5. Rebuild dynamic linker cache (recommended after system updates)
# sudo update_dyld_shared_cache -force 2>/dev/null && echo "✓ Dyld cache rebuilt"
```

### macOS 15+ notes

> macOS Sequoia (15) removed the `periodic` command. Steps 2 and 4 above cover its core functions — just run them directly.

---

## Module 7: App Uninstall

### What it does

Dragging `.app` to Trash leaves config files behind. CleanMyMac X finds and removes:

| Leftover Type | Path Pattern |
|---------------|-------------|
| Preferences | `~/Library/Preferences/com.developer.appname.plist` |
| App Support | `~/Library/Application Support/appname/` |
| Caches | `~/Library/Caches/com.developer.appname/` |
| Saved State | `~/Library/Saved Application State/com.developer.appname.savedState/` |
| Containers | `~/Library/Containers/com.developer.appname/` |
| Group Containers | `~/Library/Group Containers/*.appname/` |

### Find and uninstall

```bash
# Step 1: Locate the app
mdfind "kMDItemKind == 'Application' && kMDItemDisplayName == 'AppName'cw"
# Alternative
find /Applications -iname "*AppName*" -maxdepth 2

# Step 2: List all associated files
# Replace AppName with the actual app name
app="AppName"
echo "=== App Bundle ===" && find /Applications ~/Applications -maxdepth 2 -iname "*${app}*" -type d 2>/dev/null
echo "=== Preferences ===" && find ~/Library/Preferences -maxdepth 2 -iname "*${app}*" 2>/dev/null
echo "=== App Support ===" && find ~/Library/Application\ Support -maxdepth 3 -iname "*${app}*" 2>/dev/null
echo "=== Caches ===" && find ~/Library/Caches -maxdepth 2 -iname "*${app}*" 2>/dev/null
echo "=== Saved State ===" && find ~/Library/Saved\ Application\ State -maxdepth 2 -iname "*${app}*" 2>/dev/null
echo "=== Containers ===" && find ~/Library/Containers -maxdepth 2 -iname "*${app}*" 2>/dev/null

# Step 3: Delete (after confirmation)
app="AppName"
# Remove app bundle
sudo rm -rf "/Applications/${app}.app" 2>/dev/null || rm -rf ~/Applications/"${app}.app" 2>/dev/null
# Remove config files
find ~/Library/Preferences ~/Library/Application\ Support ~/Library/Caches \
  ~/Library/Saved\ Application\ State ~/Library/Containers \
  -maxdepth 3 -iname "*${app}*" -exec rm -rf {} + 2>/dev/null
echo "✓ ${app} and related files removed"
```

---

## Module 8: Smart Scan

### What it does

CleanMyMac X's Smart Scan combines System Junk + Malware Detection + Performance Optimization into a single one-click operation.

**CLI approach A: Run scan modules together**

```bash
echo "==============================="
echo "  Smart Scan — All Modules"
echo "==============================="
echo ""

echo "=== 1/4 System Junk ==="
du -sh ~/Library/Caches/ ~/Library/Logs/ ~/.Trash/ ~/Library/Developer/Xcode/DerivedData/ 2>/dev/null

echo ""
echo "=== 2/4 Large Files (>1GB) ==="
mdfind "kMDItemFSSize > 1000000000" 2>/dev/null | head -10

echo ""
echo "=== 3/4 Duplicates ==="
find ~/Documents ~/Downloads -type f -size +1k 2>/dev/null \
  -exec md5 -r {} \; | sort | awk '{seen[$1]++; lines[$1]=lines[$1] ? lines[$1]"\n  "$2 : "  "$2} \
  END{for(h in seen) if(seen[h]>1) printf "Duplicates: %s\n%s\n", h, lines[h]}' | head -50

echo ""
echo "=== 4/4 System Status ==="
echo "Disk free:" && df -h / | tail -1 | awk '{print $4}'
echo "XProtect:" && xprotect version 2>/dev/null
```

**Approach B: Use cmx.sh script**

```bash
bash /path/to/scripts/cmx.sh scan
```

---

## Safety Notes

### Risk levels

| Level | Meaning | Examples |
|-------|---------|---------|
| 🟢 **Safe** | Files auto-generated by system/apps, safe to remove | Caches, logs, DerivedData |
| 🟡 **Caution** | Affects system behavior but is recoverable | Flush DNS, purge memory |
| 🔴 **Risky** | Irreversible — double-check before deleting | Uninstall app, delete files |

### Best practices

1. **Scan first, clean second** — never skip the scan step
2. **Quit apps before clearing cache** — avoids issues with running processes
3. **Keep recent logs** — only delete logs older than 30 days
4. **Check large files manually** — some large files are work-critical (VMs, asset libraries)
5. **Don't blindly delete system caches** — `/Library/Caches/` may include system-required items

### Recovery

If you accidentally delete something important:

- App caches: restart the app — they'll be recreated
- System caches: restart your Mac — they'll be recreated
- Xcode DerivedData: auto-rebuilt on next build
- Spotlight index: rebuild with `mdutil -E /`

---

## Appendix: cmx.sh Reference

This skill ships with `scripts/cmx.sh`, a one-stop script wrapping all the above functionality.

### Installation

#### Via skills.sh (recommended)

```bash
npx skills add evanlong-me/skills --skill cleanmymac-x
```

#### Manual cmx alias

```bash
# Add alias to your shell config
# Replace /path/to with the actual path
echo 'alias cmx="bash /path/to/cleanmymac-x/scripts/cmx.sh"' >> ~/.zshrc
source ~/.zshrc
```

### Commands

```bash
cmx status                # System status (disk/memory/load)
cmx scan                  # Smart scan (all modules)
cmx scan system-junk      # Scan system junk only
cmx scan privacy          # Scan privacy traces only
cmx scan large-files      # Scan large files only (default >3GB)
cmx scan duplicates       # Scan duplicates only
cmx scan malware          # Malware detection only
cmx clean system-junk     # Clean system junk (dry-run)
cmx clean system-junk --apply   # Confirm and clean
cmx clean privacy --apply       # Clean privacy traces
cmx optimize --apply      # Performance optimization
cmx uninstall "AppName"   # Preview uninstall
cmx uninstall "AppName" --apply # Actually uninstall
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--apply` | Actually execute clean (default: preview) | dry-run |
| `--size 500M` | Large file threshold | 3GB |
| `--days 30` | Log retention days | 365 |

---

## References

- [Apple official storage space guide](https://support.apple.com/en-us/102624)
- [XProtect man page](https://manp.gs/mac/1/xprotect)
- [Apple platform security — malware protection](https://support.apple.com/guide/security/protecting-against-malware-sec469d47bd8/1/web/1)

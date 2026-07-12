#!/bin/bash
# cmx — CleanMyMac X CLI Equivalent
# Dry-run by default (preview only). Add --apply to execute.
# Usage: cmx [command] [options]
#   Commands: scan, clean, optimize, uninstall, status
#   Modules: system-junk, privacy, large-files, duplicates, malware
#
# Examples:
#   cmx scan                         # Scan all modules
#   cmx scan system-junk             # Scan system junk only
#   cmx clean system-junk --apply    # Confirm and clean
#   cmx status                       # System overview
#   cmx uninstall "AppName"          # Preview uninstall

set -eo pipefail

# ── Colors ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
TICK="${GREEN}✓${NC}"; CROSS="${RED}✗${NC}"; INFO="${BLUE}ℹ${NC}"; WARN="${YELLOW}⚠${NC}"

# ── Defaults ──
DRY_RUN=true
LARGE_FILE_SIZE=$((3 * 1073741824))  # Default 3GB
OLD_FILE_DAYS=365
JSON_OUTPUT=false

# ── Utility functions ──

hr_size() {
  local bytes=$1
  if (( bytes >= 1073741824 )); then
    printf "%.1f GB" "$(echo "scale=1; $bytes / 1073741824" | bc -l 2>/dev/null || echo "$bytes / 1073741824")"
  elif (( bytes >= 1048576 )); then
    printf "%.1f MB" "$(echo "scale=1; $bytes / 1048576" | bc -l 2>/dev/null || echo "$bytes / 1048576")"
  elif (( bytes >= 1024 )); then
    printf "%.1f KB" "$(echo "scale=1; $bytes / 1024" | bc -l 2>/dev/null || echo "$bytes / 1024")"
  else
    printf "%d B" "$bytes"
  fi
}

du_dir() {
  local path="$1"
  if [ -d "$path" ]; then
    local size
    size=$(du -sk "$path" 2>/dev/null | awk '{print $1}')
    if [ -n "$size" ] && [ "$size" -gt 0 ]; then
      hr_size $(( size * 1024 ))
    else
      echo "0 B"
    fi
  else
    echo "-"
  fi
}

print_header() {
  echo -e "\n${BOLD}${CYAN}═══ $1 ═══${NC}"
}

print_sub() {
  echo -e "  ${BLUE}→${NC} $1"
}

print_ok() {
  echo -e "  ${TICK} $1"
}

print_warn() {
  echo -e "  ${WARN} $1"
}

print_err() {
  echo -e "  ${CROSS} $1"
}

print_info() {
  echo -e "  ${INFO} $1"
}

confirm() {
  local prompt="${1:-Proceed?}"
  echo -en "  ${YELLOW}?${NC} $prompt [y/N] "
  read -r response
  case "$response" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# Check if root is needed
check_root_for() {
  local cmd="$1"
  if [ "$EUID" -ne 0 ]; then
    print_warn "'$cmd' requires root, attempting sudo..."
    return 1
  fi
  return 0
}

run_sudo_if_needed() {
  if [ "$EUID" -ne 0 ]; then
    sudo "$@"
  else
    "$@"
  fi
}

# ── Module: System Status ──

cmd_status() {
  print_header "System Status"

  # Disk
  echo -e "\n${BOLD}Disk:${NC}"
  local disk_info
  disk_info=$(diskutil info / 2>/dev/null)
  local total used free
  total=$(echo "$disk_info" | awk -F': ' '/Disk Size/{print $2}' | head -1)
  used=$(echo "$disk_info" | awk -F': ' '/Volume Used Space/{print $2}' | head -1)
  free=$(echo "$disk_info" | awk -F': ' '/Container Free Space/{print $2}' | head -1)
  print_info "Total: $total"
  print_info "Used:  $used"
  print_info "Free:  $free"

  # Memory
  echo -e "\n${BOLD}Memory:${NC}"
  local mem_total=$(( $(sysctl -n hw.memsize) ))
  local page_size vm_stat_out
  page_size=$(vm_stat | head -1 | awk -F'of ' '{print $2}' | awk '{print $1}')
  vm_stat_out=$(vm_stat)
  local pages_free pages_active pages_inactive pages_spec
  pages_free=$(echo "$vm_stat_out" | awk '/Pages free/{print $NF}' | tr -d '.')
  pages_active=$(echo "$vm_stat_out" | awk '/Pages active/{print $NF}' | tr -d '.')
  pages_inactive=$(echo "$vm_stat_out" | awk '/Pages inactive/{print $NF}' | tr -d '.')
  pages_spec=$(echo "$vm_stat_out" | awk '/Pages speculative/{print $NF}' | tr -d '.')
  local free_bytes=$(( pages_free * page_size ))
  local active_bytes=$(( pages_active * page_size ))
  local inactive_bytes=$(( pages_inactive * page_size ))
  print_info "Physical: $(hr_size $mem_total)"
  print_info "Active:   $(hr_size $active_bytes)"
  print_info "Inactive: $(hr_size $inactive_bytes)"
  print_info "Free:     $(hr_size $free_bytes)"

  # Load
  echo -e "\n${BOLD}System Load:${NC}"
  local loadavg
  loadavg=$(sysctl -n vm.loadavg | awk '{print $2, $3, $4}')
  print_info "Load avg: $loadavg"
  local uptime_sec
  uptime_sec=$(sysctl -n kern.boottime | awk -F'sec = |, ' '{print $2}')
  local days=$(( uptime_sec / 86400 ))
  print_info "Uptime: ${days} days"

  # XProtect
  echo -e "\n${BOLD}Security:${NC}"
  if command -v xprotect &>/dev/null; then
    local xp_ver
    xp_ver=$(xprotect version 2>/dev/null || echo "unknown")
    print_info "XProtect version: $xp_ver"
  else
    print_info "XProtect: unavailable (older macOS version)"
  fi
}

# ── Module: System Junk Scan ──

scan_system_junk() {
  local dry_run="$1"
  local total_bytes=0
  print_header "System Junk Scan"

  local results=()

  # 1) User caches
  local user_cache_size
  user_cache_size=$(du_dir "$HOME/Library/Caches")
  if [ -d "$HOME/Library/Caches" ]; then
    local count
    count=$(ls "$HOME/Library/Caches/" 2>/dev/null | wc -l | tr -d ' ')
    results+=("User caches|$HOME/Library/Caches|$user_cache_size|$count subdirs")
  fi

  # 2) System caches
  local sys_cache_size
  sys_cache_size=$(du_dir "/Library/Caches")
  if [ -d /Library/Caches ]; then
    results+=("System caches|/Library/Caches|$sys_cache_size|-")
  fi

  # 3) User logs
  local user_log_size old_log_count=0
  user_log_size=$(du_dir "$HOME/Library/Logs")
  if [ -d "$HOME/Library/Logs" ]; then
    old_log_count=$(find "$HOME/Library/Logs" -type f -mtime +"$OLD_FILE_DAYS" 2>/dev/null | wc -l | tr -d ' ')
    results+=("User logs|$HOME/Library/Logs|$user_log_size|$old_log_count files > ${OLD_FILE_DAYS} days")
  fi

  # 4) System logs
  local sys_log_size sys_log_old=0
  sys_log_size=$(du_dir "/Library/Logs")
  if [ -d /Library/Logs ]; then
    sys_log_old=$(find /Library/Logs -type f -mtime +"$OLD_FILE_DAYS" 2>/dev/null | wc -l | tr -d ' ')
    results+=("System logs|/Library/Logs|$sys_log_size|$sys_log_old files > ${OLD_FILE_DAYS} days")
  fi

  local var_log_size var_log_old=0
  var_log_size=$(du_dir "/private/var/log")
  if [ -d /private/var/log ]; then
    var_log_old=$(find /private/var/log -type f -mtime +"$OLD_FILE_DAYS" 2>/dev/null | wc -l | tr -d ' ')
    results+=("System logs|/private/var/log|$var_log_size|$var_log_old files > ${OLD_FILE_DAYS} days")
  fi

  # 5) Xcode
  local xc_derived xc_archives
  xc_derived=$(du_dir "$HOME/Library/Developer/Xcode/DerivedData")
  xc_archives=$(du_dir "$HOME/Library/Developer/Xcode/Archives")
  if [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]; then
    results+=("Xcode DerivedData|~/Library/Developer/Xcode/DerivedData|$xc_derived|Safe to delete, Xcode rebuilds")
  fi
  if [ -d "$HOME/Library/Developer/Xcode/Archives" ]; then
    results+=("Xcode Archives|~/Library/Developer/Xcode/Archives|$xc_archives|Archived builds can be removed")
  fi

  # 6) iOS Backups
  local ios_backup
  ios_backup=$(du_dir "$HOME/Library/Application Support/MobileSync/Backup")
  if [ -d "$HOME/Library/Application Support/MobileSync/Backup" ]; then
    results+=("iOS Backups|~/Library/Application Support/MobileSync/Backup|$ios_backup|Old backups can be removed")
  fi

  # 7) Trash
  local trash_size
  trash_size=$(du_dir "$HOME/.Trash")
  if [ -d "$HOME/.Trash" ]; then
    results+=("Trash|~/.Trash|$trash_size|Safe to empty")
  fi

  # 8) Temp files
  local tmp_size var_tmp_size
  tmp_size=$(du_dir "/private/tmp")
  var_tmp_size=$(du_dir "/private/var/tmp")
  results+=("System temp|/private/tmp|$tmp_size|-")
  results+=("System temp|/private/var/tmp|$var_tmp_size|-")

  # 9) Homebrew (if present)
  if command -v brew &>/dev/null; then
    local brew_cache_size
    brew_cache_size=$(du_dir "$(brew --cache 2>/dev/null)")
    results+=("Homebrew cache|$(brew --cache)|$brew_cache_size|brew cleanup -s")
  fi

  # 10) npm/pnpm/yarn (if present)
  for pkgman in npm pnpm yarn; do
    if command -v "$pkgman" &>/dev/null; then
      local cache_dir=""
      cache_dir=$($pkgman cache dir 2>/dev/null || true)
      if [ -n "$cache_dir" ] && [ -d "$cache_dir" ]; then
        local pkg_size
        pkg_size=$(du_dir "$cache_dir")
        results+=("${pkgman} cache|$cache_dir|$pkg_size|Safe to clean")
      fi
    fi
  done

  # 11) Display results table
  printf "\n%-24s %-45s %-10s %s\n" "Category" "Path" "Size" "Note"
  printf "%-24s %-45s %-10s %s\n" "$(printf '=%.0s' {1..24})" "$(printf '=%.0s' {1..45})" "$(printf '=%.0s' {1..10})" "$(printf '=%.0s' {1..20})"
  for r in "${results[@]}"; do
    IFS='|' read -r cat path size note <<< "$r"
    printf "%-24s %-45s %-10s %s\n" "$cat" "$path" "$size" "$note"
  done

  # Estimate reclaimable space
  print_header "Estimated Reclaimable Space"
  local reclaimable=0
  for d in "$HOME/Library/Caches" "$HOME/.Trash" "$HOME/Library/Logs"; do
    if [ -d "$d" ]; then
      local s
      s=$(du -sk "$d" 2>/dev/null | awk '{print $1}')
      reclaimable=$(( reclaimable + (s * 1024) ))
    fi
  done
  print_info "Caches + Logs + Trash: approx $(hr_size $reclaimable) reclaimable"
  print_info "(Note: actual savings may be higher, review individual items)"
}

# ── Clean System Junk ──

clean_system_junk() {
  local dry_run="$1"
  print_header "Clean System Junk"

  if [ "$dry_run" = true ]; then
    print_info "Dry-run mode — the following can be safely cleaned:"
  fi

  # 1) Delete old logs
  local old_logs
  old_logs=$(find "$HOME/Library/Logs" -type f -mtime +"$OLD_FILE_DAYS" 2>/dev/null | wc -l | tr -d ' ')
  print_sub "Old log files (> ${OLD_FILE_DAYS} days): $old_logs"
  if [ "$old_logs" -gt 0 ]; then
    local log_size
    log_size=$(find "$HOME/Library/Logs" -type f -mtime +"$OLD_FILE_DAYS" -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1} END{print s}' | xargs echo)
    [ -z "$log_size" ] && log_size=0
    print_info "  Estimated recovery: $(hr_size "$log_size")"
    if [ "$dry_run" = false ]; then
      find "$HOME/Library/Logs" -type f -mtime +"$OLD_FILE_DAYS" -delete 2>/dev/null
      print_ok "Old logs cleaned"
    fi
  fi

  # 2) Trash
  print_sub "Trash"
  if [ -d "$HOME/.Trash" ]; then
    local trash_size
    trash_size=$(du -sk "$HOME/.Trash" 2>/dev/null | awk '{print $1}')
    trash_size=$(( trash_size * 1024 ))
    print_info "  Trash size: $(hr_size "$trash_size")"
    if [ "$dry_run" = false ]; then
      if confirm "Empty Trash?"; then
        rm -rf "$HOME/.Trash/"* 2>/dev/null || true
        print_ok "Trash emptied"
      fi
    fi
  fi

  # 3) Xcode DerivedData
  if [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]; then
    local xc_size
    xc_size=$(du -sk "$HOME/Library/Developer/Xcode/DerivedData" 2>/dev/null | awk '{print $1}')
    xc_size=$(( xc_size * 1024 ))
    print_sub "Xcode DerivedData: $(hr_size "$xc_size")"
    if [ "$dry_run" = false ]; then
      if confirm "Clean Xcode DerivedData (Xcode will rebuild them)?"; then
        rm -rf "$HOME/Library/Developer/Xcode/DerivedData/"* 2>/dev/null || true
        print_ok "Xcode DerivedData cleaned"
      fi
    fi
  fi

  # 4) Homebrew cache
  if command -v brew &>/dev/null; then
    print_sub "Homebrew cache"
    local brew_cache
    brew_cache=$(brew --cache 2>/dev/null)
    if [ -d "$brew_cache" ]; then
      local br_size
      br_size=$(du -sk "$brew_cache" 2>/dev/null | awk '{print $1}')
      br_size=$(( br_size * 1024 ))
      print_info "  Homebrew cache: $(hr_size "$br_size")"
      if [ "$dry_run" = false ]; then
        if confirm "Run brew cleanup -s (clean old package caches)?"; then
          brew cleanup -s 2>/dev/null || true
          print_ok "Homebrew cache cleaned"
        fi
      fi
    fi
  fi

  if [ "$dry_run" = true ]; then
    print_info "\nThis was a dry-run preview. Add --apply to execute."
  fi
}

# ── Module: Privacy Scan ──

scan_privacy() {
  local dry_run="$1"
  print_header "Privacy Traces Scan"
  local results=()

  # Safari
  if [ -d "$HOME/Library/Caches/com.apple.Safari" ]; then
    local saf_cache
    saf_cache=$(du_dir "$HOME/Library/Caches/com.apple.Safari")
    results+=("Safari cache|~/Library/Caches/com.apple.Safari|$saf_cache")
  fi
  if [ -f "$HOME/Library/Safari/History.db" ]; then
    results+=("Safari history|~/Library/Safari/History.db|-")
  fi

  # Chrome
  local chrome_cache="$HOME/Library/Caches/Google/Chrome"
  if [ -d "$chrome_cache" ]; then
    local ch_cache
    ch_cache=$(du_dir "$chrome_cache")
    results+=("Chrome cache|$chrome_cache|$ch_cache")
  fi
  local chrome_profile="$HOME/Library/Application Support/Google/Chrome/Default"
  if [ -f "$chrome_profile/History" ]; then
    results+=("Chrome history|$chrome_profile/History|-")
  fi
  if [ -f "$chrome_profile/Cookies" ]; then
    results+=("Chrome cookies|$chrome_profile/Cookies|-")
  fi

  # Firefox
  local firefox_profiles="$HOME/Library/Application Support/Firefox/Profiles"
  if [ -d "$firefox_profiles" ]; then
    local ff_count
    ff_count=$(ls "$firefox_profiles" 2>/dev/null | wc -l | tr -d ' ')
    results+=("Firefox profiles|$firefox_profiles|$ff_count profiles")
    for prof in "$firefox_profiles"/*/; do
      [ -f "${prof}places.sqlite" ] && results+=("Firefox history|${prof}places.sqlite|-")
      [ -f "${prof}cookies.sqlite" ] && results+=("Firefox cookies|${prof}cookies.sqlite|-")
      break
    done
  fi

  # Recent items
  results+=("Recent files|Finder recent items|-|App menu → Recent Items → Clear Menu")

  # Clipboard
  local clipboard
  clipboard=$(pbpaste 2>/dev/null | head -c 100 || echo "")
  if [ -n "$clipboard" ]; then
    results+=("Clipboard|System clipboard|$(echo "$clipboard" | wc -c | tr -d ' ') B|Has content, clear with pbcopy < /dev/null")
  fi

  printf "\n%-20s %-50s %s\n" "App" "Path" "Size/Note"
  printf "%-20s %-50s %s\n" "$(printf '=%.0s' {1..20})" "$(printf '=%.0s' {1..50})" "$(printf '=%.0s' {1..15})"
  for r in "${results[@]}"; do
    IFS='|' read -r app path note <<< "$r"
    printf "%-20s %-50s %s\n" "$app" "$path" "$note"
  done
}

# ── Clean Privacy ──

clean_privacy() {
  local dry_run="$1"
  print_header "Clean Privacy Traces"

  if [ "$dry_run" = true ]; then
    print_info "Dry-run mode — the following can be cleaned:"
  fi

  # Safari
  if [ -d "$HOME/Library/Caches/com.apple.Safari" ]; then
    print_sub "Safari cache"
    if [ "$dry_run" = false ]; then
      rm -rf "$HOME/Library/Caches/com.apple.Safari/"* 2>/dev/null || true
      print_ok "Safari cache cleaned"
    else
      local s_size
      s_size=$(du_dir "$HOME/Library/Caches/com.apple.Safari")
      print_info "  Safari cache: $s_size"
    fi
  fi

  # Chrome cache
  local chrome_cache="$HOME/Library/Caches/Google/Chrome"
  if [ -d "$chrome_cache" ]; then
    print_sub "Chrome cache"
    if [ "$dry_run" = false ]; then
      rm -rf "$chrome_cache/"* 2>/dev/null || true
      print_ok "Chrome cache cleaned"
    else
      local c_size
      c_size=$(du_dir "$chrome_cache")
      print_info "  Chrome cache: $c_size"
    fi
  fi

  # Clipboard
  print_sub "System clipboard"
  if [ "$dry_run" = false ]; then
    pbcopy < /dev/null 2>/dev/null || true
    print_ok "Clipboard cleared"
  else
    print_info "  Clipboard can be cleared (pbcopy < /dev/null)"
  fi

  if [ "$dry_run" = true ]; then
    print_info "\nThis was a dry-run preview. Add --apply to execute."
  fi
}

# ── Module: Large Files Scan ──

scan_large_files() {
  local dry_run="$1"
  local size_threshold="$2"
  print_header "Large Files Scan (> $(hr_size "$size_threshold"))"

  print_sub "Using Spotlight index (fastest)..."
  local results
  results=$(mdfind "kMDItemFSSize > $size_threshold" -onlyin / 2>/dev/null | head -50 || true)

  if [ -z "$results" ]; then
    print_info "No files found > $(hr_size "$size_threshold") (or index incomplete)"
    print_sub "Trying fallback (find traversal)..."
    local top20
    top20=$(find "$HOME" -type f -size +"$(( size_threshold / 1024 / 1024 ))"M 2>/dev/null -exec ls -lhS {} + | awk '{print $5, $NF}' | head -20)
    if [ -n "$top20" ]; then
      echo ""
      echo "$top20" | while read -r size path; do
        echo "  $size  $path"
      done
    else
      print_info "No large files found"
    fi
  else
    echo ""
    local count=0
    while IFS= read -r f; do
      count=$(( count + 1 ))
      if [ -f "$f" ]; then
        local size
        size=$(stat -f%z "$f" 2>/dev/null || stat -f%z "$f")
        echo -e "  $(hr_size "$size" 2>/dev/null || echo "?")  $f"
      fi
      [ "$count" -ge 30 ] && { print_info "...(showing first 30)"; break; }
    done <<< "$results"
  fi
}

# ── Module: Duplicates Scan ──

scan_duplicates() {
  local dry_run="$1"
  print_header "Duplicate File Scan"
  print_info "Scanning for duplicates (may be slow). Default: ~/Documents, ~/Downloads, ~/Desktop"

  local scan_dirs=("$HOME/Documents" "$HOME/Downloads" "$HOME/Desktop")
  local tmpfile
  tmpfile=$(mktemp)
  local found=false

  for dir in "${scan_dirs[@]}"; do
    if [ ! -d "$dir" ]; then continue; fi
    print_sub "Scanning: $dir"
    find "$dir" -type f -size +1k 2>/dev/null | while read -r f; do
      md5 -r "$f" 2>/dev/null
    done | sort > "$tmpfile"
    local dups
    dups=$(awk '{seen[$1]++; lines[$1]=lines[$1] ? lines[$1]"\n    "$2 : "    "$2} END{for(h in seen) if(seen[h]>1) print lines[h]}' "$tmpfile" 2>/dev/null)
    if [ -n "$dups" ]; then
      found=true
      echo ""
      echo "$dups"
      echo "  ---"
    fi
  done

  if [ "$found" = false ]; then
    print_info "No duplicate files found"
  fi
  rm -f "$tmpfile"
}

# ── Module: Malware Detection ──

scan_malware() {
  local dry_run="$1"
  print_header "Malware Detection"

  # XProtect
  print_sub "XProtect Status"
  if command -v xprotect &>/dev/null; then
    xprotect version 2>/dev/null && print_ok "XProtect enabled" || print_warn "XProtect unavailable"
  else
    print_warn "xprotect command not available (requires macOS Sequoia 15+)"
  fi

  # XProtect full scan (requires root)
  print_sub "XProtect Malware Scan"
  if command -v xprotect &>/dev/null; then
    if sudo xprotect check --json 2>/dev/null | grep -q '"malware"'; then
      local result
      result=$(sudo xprotect check --json 2>/dev/null)
      print_ok "XProtect scan complete"
      echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
    else
      print_info "XProtect check requires Full Disk Access"
      print_info "Run: sudo xprotect check --json"
    fi
  fi

  # Login items
  echo ""
  print_sub "Login Items (auto-start apps)"
  local login_items
  login_items=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null)
  if [ -n "$login_items" ]; then
    echo "$login_items" | tr ',' '\n' | while read -r item; do
      echo "  • $(echo "$item" | xargs)"
    done
  else
    print_info "No login items"
  fi

  # Launch Agents
  echo ""
  print_sub "User Launch Agents (potentially suspicious)"
  local agent_count
  agent_count=$(ls "$HOME/Library/LaunchAgents/" 2>/dev/null | wc -l | tr -d ' ')
  print_info "User Launch Agents count: $agent_count"
  local agent_files=()
  while IFS= read -r -d '' f; do
    agent_files+=("$f")
  done < <(find "$HOME/Library/LaunchAgents/" -name "*.plist" -maxdepth 1 2>/dev/null -print0)
  for f in "${agent_files[@]:0:10}"; do
    local label
    label=$(plutil -p "$f" 2>/dev/null | grep '"Label"' | awk -F'"' '{print $4}' || basename "$f")
    echo "  • $label"
  done

  # Suspicious processes
  echo ""
  print_sub "Suspicious Process Check"
  local susp_procs
  susp_procs=$(ps aux 2>/dev/null | grep -iE "(bundle|Maps|adware|spy|trojan|keylog)" | grep -v grep | grep -v "cmx.sh" || true)
  if [ -n "$susp_procs" ]; then
    print_warn "Suspicious processes found:"
    echo "$susp_procs"
  else
    print_ok "No obviously suspicious processes found"
  fi
}

# ── Module: Performance Optimization ──

cmd_optimize() {
  local dry_run="$1"
  print_header "Performance Optimization"

  # 1) Free memory
  print_sub "Free inactive memory"
  if [ "$dry_run" = false ]; then
    if check_root_for "purge"; then
      sudo purge 2>/dev/null && print_ok "Memory purged" || print_warn "purge failed (may need SIP disabled)"
    else
      sudo purge 2>/dev/null && print_ok "Memory purged" || print_warn "purge failed"
    fi
  else
    print_info "Will execute: sudo purge (free inactive memory pages)"
  fi

  # 2) Flush DNS cache
  echo ""
  print_sub "Flush DNS cache"
  if [ "$dry_run" = false ]; then
    sudo dscacheutil -flushcache 2>/dev/null || true
    sudo killall -HUP mDNSResponder 2>/dev/null || true
    print_ok "DNS cache flushed"
  else
    print_info "Will execute: sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
  fi

  # 3) Rebuild Spotlight index
  echo ""
  print_sub "Spotlight Index"
  local spotlight_status
  spotlight_status=$(mdutil -s / 2>/dev/null)
  echo "  $spotlight_status"
  if [ "$dry_run" = false ]; then
    if confirm "Rebuild Spotlight index (may take hours)?"; then
      sudo mdutil -E / 2>/dev/null && print_ok "Spotlight rebuild triggered" || print_warn "Rebuild failed"
    fi
  fi

  # 4) System maintenance (macOS 15+ removed periodic; execute core tasks manually)
  echo ""
  print_sub "System maintenance tasks"
  if [ "$dry_run" = false ]; then
    # Clean temp dirs
    if confirm "Clean system temp files?"; then
      sudo rm -rf /private/var/tmp/* 2>/dev/null || true
      sudo rm -rf /private/tmp/* 2>/dev/null || true
      print_ok "Temp files cleaned"
    fi
    # Rebuild dyld cache
    if confirm "Rebuild dynamic linker cache?"; then
      sudo update_dyld_shared_cache -force 2>/dev/null && print_ok "Dyld cache rebuilt" || print_warn "Rebuild failed"
    fi
  else
    print_info "Will execute the following maintenance tasks:"
    print_info "  • Clean /private/var/tmp/"
    print_info "  • Clean /private/tmp/"
    print_info "  • Rebuild dynamic linker cache"
  fi

  if [ "$dry_run" = true ]; then
    print_info "\nThis was a dry-run preview. Add --apply to execute."
  fi
}

# ── Module: App Uninstall ──

cmd_uninstall() {
  local app_name="$1"
  local dry_run="$2"

  if [ -z "$app_name" ]; then
    print_err "Please specify an app name. Usage: cmx uninstall 'AppName'"
    exit 1
  fi

  print_header "Uninstall App: $app_name"

  # Locate app
  print_sub "Finding app"
  local app_paths
  app_paths=$(mdfind "kMDItemKind == 'Application' && kMDItemDisplayName == '$app_name'cw" 2>/dev/null || true)
  if [ -z "$app_paths" ]; then
    app_paths=$(find /Applications "$HOME/Applications" -maxdepth 3 -iname "*${app_name}*" -type d 2>/dev/null || true)
  fi

  if [ -z "$app_paths" ]; then
    print_warn "App '$app_name' not found"
    # Try fuzzy search
    print_sub "Fuzzy search..."
    local fuzzy
    fuzzy=$(mdfind "kMDItemKind == 'Application'" 2>/dev/null | grep -i "$app_name" | head -5 || true)
    if [ -z "$fuzzy" ]; then
      fuzzy=$(find /Applications "$HOME/Applications" -maxdepth 2 -name "*.app" 2>/dev/null | grep -i "$app_name" | head -5 || true)
    fi
    if [ -n "$fuzzy" ]; then
      print_info "Did you mean one of these?"
      echo "$fuzzy" | while read -r f; do
        echo "  • $(basename "$f" .app)"
      done
    else
      print_info "No matching apps found"
    fi
    exit 1
  fi

  # Show app info
  echo ""
  while IFS= read -r app_path; do
    local app_bundle
    app_bundle=$(basename "$app_path")
    local app_size
    app_size=$(du_dir "$app_path")
    echo "  📦 $app_bundle"
    echo "     Path: $app_path"
    echo "     Size: $app_size"

    local app_basename
    app_basename=$(basename "$app_path" .app)
    local related_files=()
    print_sub "Related files:"
    for search_dir in "$HOME/Library/Preferences" "$HOME/Library/Application Support" "$HOME/Library/Caches" "$HOME/Library/Saved Application State" "$HOME/Library/Containers" "$HOME/Library/Group Containers"; do
      if [ -d "$search_dir" ]; then
        local matches
        matches=$(find "$search_dir" -maxdepth 2 -iname "*${app_basename}*" 2>/dev/null || true)
        if [ -n "$matches" ]; then
          echo "$matches" | while read -r m; do
            local m_size
            m_size=$(du_dir "$m")
            echo "    $m_size  $m"
          done
        fi
      fi
    done
  done <<< "$app_paths"

  if [ "$dry_run" = false ]; then
    echo ""
    if confirm "Proceed with uninstall? This is irreversible!"; then
      while IFS= read -r app_path; do
        local app_basename
        app_basename=$(basename "$app_path" .app)
        # Remove app
        if [ -w "$(dirname "$app_path")" ]; then
          rm -rf "$app_path" && print_ok "Deleted: $app_path"
        else
          sudo rm -rf "$app_path" && print_ok "Deleted (sudo): $app_path"
        fi
        # Remove related files
        for search_dir in "$HOME/Library/Preferences" "$HOME/Library/Application Support" "$HOME/Library/Caches" "$HOME/Library/Saved Application State"; do
          if [ -d "$search_dir" ]; then
            find "$search_dir" -maxdepth 2 -iname "*${app_basename}*" -exec rm -rf {} + 2>/dev/null || true
          fi
        done
      done <<< "$app_paths"
      print_ok "Uninstall complete"
    fi
  else
    print_info "\nThis was a preview. Add --apply to execute."
  fi
}

# ── Module: Smart Scan (all modules combined) ──

cmd_smart_scan() {
  local dry_run="$1"
  print_header "🧠 Smart Scan — All Modules"
  print_info "Simultaneous scan: System Junk + Privacy + Large Files + Malware"
  echo ""

  scan_system_junk "$dry_run"
  echo ""
  scan_privacy "$dry_run"
  echo ""
  scan_large_files "$dry_run" "$LARGE_FILE_SIZE"
  echo ""
  scan_malware "$dry_run"

  print_header "Smart Scan Complete"
  print_info "You can now run:"
  echo "  1. cmx clean system-junk --apply    Clean system junk"
  echo "  2. cmx clean privacy --apply        Clean privacy traces"
  echo "  3. cmx optimize --apply             Performance optimization"
  echo "  4. cmx uninstall <AppName>           Uninstall an app"
}

# ── Main ──

usage() {
  cat <<EOF
Usage: cmx <command> [module] [options]

Commands:
  scan                      Scan all modules (summary report)
  scan system-junk          Scan system junk (caches/logs/temp)
  scan privacy              Scan privacy traces (browser/clipboard/etc)
  scan large-files          Scan large files
  scan duplicates           Scan duplicate files
  scan malware              Malware detection + XProtect scan

  clean system-junk         Clean system junk
  clean privacy             Clean privacy traces

  optimize                  Performance optimization (memory/DNS/maintenance)
  uninstall <AppName>       Uninstall app and leftover files
  status                    System overview
  help                      Show this help

Options:
  --apply                   Execute (default is dry-run preview only)
  --size N[KMG]             Large file threshold (e.g. --size 100M, --size 1G)
  --days N                  Log retention days (default $OLD_FILE_DAYS)
  --json                    JSON output (experimental)

Examples:
  cmx status                            # System status
  cmx scan                              # Smart scan all
  cmx scan large-files --size 500M      # Scan files >500MB
  cmx clean system-junk --apply         # Clean system junk
  cmx optimize --apply                  # Performance optimization
  cmx uninstall "Xcode"                 # Preview Xcode uninstall
  cmx uninstall "Xcode" --apply         # Actually uninstall Xcode

EOF
}

main() {
  [ $# -eq 0 ] && { usage; exit 0; }

  local cmd=""; local module=""; local app_name=""
  local positional=()

  # Parse arguments, separating options from positional args
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) DRY_RUN=false; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      --size)
        shift; [ $# -eq 0 ] && { print_err "--size requires a value"; exit 1; }
        local size_str="$1"; shift
        local num="${size_str//[A-Za-z]/}"
        local unit="${size_str//[0-9]/}"
        case "$unit" in
          G|GB) LARGE_FILE_SIZE=$(( num * 1073741824 )) ;;
          M|MB) LARGE_FILE_SIZE=$(( num * 1048576 )) ;;
          K|KB) LARGE_FILE_SIZE=$(( num * 1024 )) ;;
          *) LARGE_FILE_SIZE=$(( num )) ;;
        esac
        ;;
      --days) shift; [ $# -eq 0 ] && { print_err "--days requires a value"; exit 1; }
        OLD_FILE_DAYS=$1; shift ;;
      --json) JSON_OUTPUT=true; shift ;;
      -h|--help|help) usage; exit 0 ;;
      --*) print_err "Unknown option: $1"; usage; exit 1 ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  cmd="${positional[0]:-}"
  local sub="${positional[1]:-}"
  module="$sub"; app_name="$sub"

  case "$cmd" in
    scan)
      case "$module" in
        system-junk) scan_system_junk "$DRY_RUN" ;;
        privacy) scan_privacy "$DRY_RUN" ;;
        large-files) scan_large_files "$DRY_RUN" "$LARGE_FILE_SIZE" ;;
        duplicates) scan_duplicates "$DRY_RUN" ;;
        malware) scan_malware "$DRY_RUN" ;;
        ""|all|smart) cmd_smart_scan "$DRY_RUN" ;;
        *) print_err "Unknown module: $module"; usage; exit 1 ;;
      esac
      ;;
    clean)
      case "$module" in
        system-junk) clean_system_junk "$DRY_RUN" ;;
        privacy) clean_privacy "$DRY_RUN" ;;
        *) print_err "Unknown clean module: $module"; usage; exit 1 ;;
      esac
      ;;
    optimize) cmd_optimize "$DRY_RUN" ;;
    uninstall)
      cmd_uninstall "$module" "$DRY_RUN"
      ;;
    status) cmd_status ;;
    smart-scan) cmd_smart_scan "$DRY_RUN" ;;
    "") usage ;;
    *) print_err "Unknown command: $cmd"; usage; exit 1 ;;
  esac
}

main "$@"

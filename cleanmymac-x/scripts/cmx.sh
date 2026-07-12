#!/bin/bash
# cmx — CleanMyMac X 命令行对标实现
# 默认 dry-run（仅扫描预览），加 --apply 执行实际清理
# 用法: cmx [command] [options]
#   命令: scan, clean, optimize, uninstall, status
#   模块: system-junk, privacy, large-files, duplicates, malware
#
# 示例:
#   cmx scan                  # 扫描全部
#   cmx scan system-junk      # 仅扫系统垃圾
#   cmx clean system-junk --apply   # 确认后清理
#   cmx status                # 系统状态概览
#   cmx uninstall "AppName"   # 卸载应用

set -eo pipefail

# ── 颜色 ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
TICK="${GREEN}✓${NC}"; CROSS="${RED}✗${NC}"; INFO="${BLUE}ℹ${NC}"; WARN="${YELLOW}⚠${NC}"

# ── 配置默认值 ──
DRY_RUN=true
LARGE_FILE_SIZE=$((3 * 1073741824))  # 默认 3GB
OLD_FILE_DAYS=365
JSON_OUTPUT=false

# ── 工具函数 ──

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
  local prompt="${1:-确定继续？}"
  echo -en "  ${YELLOW}?${NC} $prompt [y/N] "
  read -r response
  case "$response" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# 检查是否需要 root
check_root_for() {
  local cmd="$1"
  if [ "$EUID" -ne 0 ]; then
    print_warn "'$cmd' 需要 root 权限，尝试 sudo..."
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

# ── 模块: 系统状态概览 ──

cmd_status() {
  print_header "系统状态概览"

  # 磁盘
  echo -e "\n${BOLD}磁盘:${NC}"
  local disk_info
  disk_info=$(diskutil info / 2>/dev/null)
  local total used free
  total=$(echo "$disk_info" | awk -F': ' '/Disk Size/{print $2}' | head -1)
  used=$(echo "$disk_info" | awk -F': ' '/Volume Used Space/{print $2}' | head -1)
  free=$(echo "$disk_info" | awk -F': ' '/Container Free Space/{print $2}' | head -1)
  print_info "总容量: $total"
  print_info "已用:    $used"
  print_info "可用:    $free"

  # 内存
  echo -e "\n${BOLD}内存:${NC}"
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
  print_info "物理内存: $(hr_size $mem_total)"
  print_info "活跃:     $(hr_size $active_bytes)"
  print_info "非活跃:   $(hr_size $inactive_bytes)"
  print_info "空闲:     $(hr_size $free_bytes)"

  # 负载
  echo -e "\n${BOLD}系统负载:${NC}"
  local loadavg
  loadavg=$(sysctl -n vm.loadavg | awk '{print $2, $3, $4}')
  print_info "平均负载: $loadavg"
  local uptime_sec
  uptime_sec=$(sysctl -n kern.boottime | awk -F'sec = |, ' '{print $2}')
  local days=$(( uptime_sec / 86400 ))
  print_info "运行时间: ${days} 天"

  # XProtect
  echo -e "\n${BOLD}安全:${NC}"
  if command -v xprotect &>/dev/null; then
    local xp_ver
    xp_ver=$(xprotect version 2>/dev/null || echo "未知")
    print_info "XProtect 版本: $xp_ver"
  else
    print_info "XProtect: 不可用（macOS 版本较旧）"
  fi
}

# ── 模块: 系统垃圾扫描 ──

scan_system_junk() {
  local dry_run="$1"
  local total_bytes=0
  print_header "系统垃圾扫描"

  local results=()

  # 1) 用户缓存
  local user_cache_size
  user_cache_size=$(du_dir "$HOME/Library/Caches")
  if [ -d "$HOME/Library/Caches" ]; then
    local count
    count=$(ls "$HOME/Library/Caches/" 2>/dev/null | wc -l | tr -d ' ')
    results+=("用户缓存|$HOME/Library/Caches|$user_cache_size|$count 个子目录")
  fi

  # 2) 系统缓存
  local sys_cache_size
  sys_cache_size=$(du_dir "/Library/Caches")
  if [ -d /Library/Caches ]; then
    results+=("系统缓存|/Library/Caches|$sys_cache_size|-")
  fi

  # 3) 用户日志
  local user_log_size old_log_count=0
  user_log_size=$(du_dir "$HOME/Library/Logs")
  if [ -d "$HOME/Library/Logs" ]; then
    old_log_count=$(find "$HOME/Library/Logs" -type f -mtime +"$OLD_FILE_DAYS" 2>/dev/null | wc -l | tr -d ' ')
    results+=("用户日志|$HOME/Library/Logs|$user_log_size|$old_log_count 个文件超过 ${OLD_FILE_DAYS} 天")
  fi

  # 4) 系统日志
  local sys_log_size sys_log_old=0
  sys_log_size=$(du_dir "/Library/Logs")
  if [ -d /Library/Logs ]; then
    sys_log_old=$(find /Library/Logs -type f -mtime +"$OLD_FILE_DAYS" 2>/dev/null | wc -l | tr -d ' ')
    results+=("系统日志|/Library/Logs|$sys_log_size|$sys_log_old 个文件超过 ${OLD_FILE_DAYS} 天")
  fi

  local var_log_size var_log_old=0
  var_log_size=$(du_dir "/private/var/log")
  if [ -d /private/var/log ]; then
    var_log_old=$(find /private/var/log -type f -mtime +"$OLD_FILE_DAYS" 2>/dev/null | wc -l | tr -d ' ')
    results+=("系统日志|/private/var/log|$var_log_size|$var_log_old 个文件超过 ${OLD_FILE_DAYS} 天")
  fi

  # 5) Xcode
  local xc_derived xc_archives
  xc_derived=$(du_dir "$HOME/Library/Developer/Xcode/DerivedData")
  xc_archives=$(du_dir "$HOME/Library/Developer/Xcode/Archives")
  if [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]; then
    results+=("Xcode DerivedData|~/Library/Developer/Xcode/DerivedData|$xc_derived|可安全删除，Xcode 会重建")
  fi
  if [ -d "$HOME/Library/Developer/Xcode/Archives" ]; then
    results+=("Xcode Archives|~/Library/Developer/Xcode/Archives|$xc_archives|已分发应用的存档可删")
  fi

  # 6) iOS 备份
  local ios_backup
  ios_backup=$(du_dir "$HOME/Library/Application Support/MobileSync/Backup")
  if [ -d "$HOME/Library/Application Support/MobileSync/Backup" ]; then
    results+=("iOS 备份|~/Library/Application Support/MobileSync/Backup|$ios_backup|旧备份可删")
  fi

  # 7) 废纸篓
  local trash_size
  trash_size=$(du_dir "$HOME/.Trash")
  if [ -d "$HOME/.Trash" ]; then
    results+=("废纸篓|~/.Trash|$trash_size|安全清理")
  fi

  # 8) 临时文件
  local tmp_size var_tmp_size
  tmp_size=$(du_dir "/private/tmp")
  var_tmp_size=$(du_dir "/private/var/tmp")
  results+=("系统临时文件|/private/tmp|$tmp_size|-")
  results+=("系统临时文件|/private/var/tmp|$var_tmp_size|-")

  # 9) Homebrew (如果存在)
  if command -v brew &>/dev/null; then
    local brew_cache_size
    brew_cache_size=$(du_dir "$(brew --cache 2>/dev/null)")
    results+=("Homebrew 缓存|$(brew --cache)|$brew_cache_size|brew cleanup -s 可清理")
  fi

  # 10) npm/pnpm/yarn (如果存在)
  for pkgman in npm pnpm yarn; do
    if command -v "$pkgman" &>/dev/null; then
      local cache_dir=""
      cache_dir=$($pkgman cache dir 2>/dev/null || true)
      if [ -n "$cache_dir" ] && [ -d "$cache_dir" ]; then
        local pkg_size
        pkg_size=$(du_dir "$cache_dir")
        results+=("${pkgman} 缓存|$cache_dir|$pkg_size|可安全清理")
      fi
    fi
  done

  # 11) 显示结果表格
  printf "\n%-24s %-45s %-10s %s\n" "分类" "路径" "大小" "说明"
  printf "%-24s %-45s %-10s %s\n" "$(printf '=%.0s' {1..24})" "$(printf '=%.0s' {1..45})" "$(printf '=%.0s' {1..10})" "$(printf '=%.0s' {1..20})"
  for r in "${results[@]}"; do
    IFS='|' read -r cat path size note <<< "$r"
    printf "%-24s %-45s %-10s %s\n" "$cat" "$path" "$size" "$note"
  done

  # 计算总可回收空间
  print_header "可回收空间估算"
  local reclaimable=0
  # 只统计可安全清理的
  for d in "$HOME/Library/Caches" "$HOME/.Trash" "$HOME/Library/Logs"; do
    if [ -d "$d" ]; then
      local s
      s=$(du -sk "$d" 2>/dev/null | awk '{print $1}')
      reclaimable=$(( reclaimable + (s * 1024) ))
    fi
  done
  print_info "缓存 + 日志 + 废纸篓 约可释放: $(hr_size $reclaimable)"
  print_info "（注：实际可回收更多，需根据具体项确认）"
}

# ── 执行清理系统垃圾 ──

clean_system_junk() {
  local dry_run="$1"
  print_header "清理系统垃圾"

  if [ "$dry_run" = true ]; then
    print_info "dry-run 模式 — 以下文件可安全清理:"
  fi

  # 1) 清理超过 30 天的日志
  local old_logs
  old_logs=$(find "$HOME/Library/Logs" -type f -mtime +"$OLD_FILE_DAYS" 2>/dev/null | wc -l | tr -d ' ')
  print_sub "旧日志文件（> ${OLD_FILE_DAYS} 天）: $old_logs 个"
  if [ "$old_logs" -gt 0 ]; then
    local log_size
    log_size=$(find "$HOME/Library/Logs" -type f -mtime +"$OLD_FILE_DAYS" -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1} END{print s}' | xargs echo)
    [ -z "$log_size" ] && log_size=0
    print_info "  预计释放: $(hr_size "$log_size")"
    if [ "$dry_run" = false ]; then
      find "$HOME/Library/Logs" -type f -mtime +"$OLD_FILE_DAYS" -delete 2>/dev/null
      print_ok "已清理旧日志"
    fi
  fi

  # 2) 废纸篓
  print_sub "废纸篓"
  if [ -d "$HOME/.Trash" ]; then
    local trash_size
    trash_size=$(du -sk "$HOME/.Trash" 2>/dev/null | awk '{print $1}')
    trash_size=$(( trash_size * 1024 ))
    print_info "  废纸篓大小: $(hr_size "$trash_size")"
    if [ "$dry_run" = false ]; then
      if confirm "清空废纸篓？"; then
        rm -rf "$HOME/.Trash/"* 2>/dev/null || true
        print_ok "废纸篓已清空"
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
      if confirm "清理 Xcode DerivedData（Xcode 会重建它们）？"; then
        rm -rf "$HOME/Library/Developer/Xcode/DerivedData/"* 2>/dev/null || true
        print_ok "Xcode DerivedData 已清理"
      fi
    fi
  fi

  # 4) Homebrew 缓存
  if command -v brew &>/dev/null; then
    print_sub "Homebrew 缓存"
    local brew_cache
    brew_cache=$(brew --cache 2>/dev/null)
    if [ -d "$brew_cache" ]; then
      local br_size
      br_size=$(du -sk "$brew_cache" 2>/dev/null | awk '{print $1}')
      br_size=$(( br_size * 1024 ))
      print_info "  Homebrew 缓存: $(hr_size "$br_size")"
      if [ "$dry_run" = false ]; then
        if confirm "运行 brew cleanup -s（清理旧版本包缓存）？"; then
          brew cleanup -s 2>/dev/null || true
          print_ok "Homebrew 缓存已清理"
        fi
      fi
    fi
  fi

  if [ "$dry_run" = true ]; then
    print_info "\n以上为 dry-run 预览。实际清理请加 --apply 参数。"
  fi
}

# ── 模块: 隐私痕迹扫描 ──

scan_privacy() {
  local dry_run="$1"
  print_header "隐私痕迹扫描"
  local results=()

  # Safari
  if [ -d "$HOME/Library/Caches/com.apple.Safari" ]; then
    local saf_cache
    saf_cache=$(du_dir "$HOME/Library/Caches/com.apple.Safari")
    results+=("Safari 缓存|~/Library/Caches/com.apple.Safari|$saf_cache")
  fi
  if [ -f "$HOME/Library/Safari/History.db" ]; then
    results+=("Safari 历史|~/Library/Safari/History.db|-")
  fi

  # Chrome
  local chrome_cache="$HOME/Library/Caches/Google/Chrome"
  if [ -d "$chrome_cache" ]; then
    local ch_cache
    ch_cache=$(du_dir "$chrome_cache")
    results+=("Chrome 缓存|$chrome_cache|$ch_cache")
  fi
  local chrome_profile="$HOME/Library/Application Support/Google/Chrome/Default"
  if [ -f "$chrome_profile/History" ]; then
    results+=("Chrome 历史|$chrome_profile/History|-")
  fi
  if [ -f "$chrome_profile/Cookies" ]; then
    results+=("Chrome Cookies|$chrome_profile/Cookies|-")
  fi

  # Firefox
  local firefox_profiles="$HOME/Library/Application Support/Firefox/Profiles"
  if [ -d "$firefox_profiles" ]; then
    local ff_count
    ff_count=$(ls "$firefox_profiles" 2>/dev/null | wc -l | tr -d ' ')
    results+=("Firefox 配置|$firefox_profiles|$ff_count 个配置")
    for prof in "$firefox_profiles"/*/; do
      [ -f "${prof}places.sqlite" ] && results+=("Firefox 历史|${prof}places.sqlite|-")
      [ -f "${prof}cookies.sqlite" ] && results+=("Firefox Cookies|${prof}cookies.sqlite|-")
      break
    done
  fi

  # 最近项目
  results+=("最近文件|Finder 最近项目|-|应用程序菜单 → 最近项目 → 清除菜单")

  # 剪贴板
  local clipboard
  clipboard=$(pbpaste 2>/dev/null | head -c 100 || echo "")
  if [ -n "$clipboard" ]; then
    results+=("剪贴板|系统剪贴板|$(echo "$clipboard" | wc -c | tr -d ' ') B|含内容，可用 pbcopy < /dev/null 清空")
  fi

  printf "\n%-20s %-50s %s\n" "应用" "路径" "大小/说明"
  printf "%-20s %-50s %s\n" "$(printf '=%.0s' {1..20})" "$(printf '=%.0s' {1..50})" "$(printf '=%.0s' {1..15})"
  for r in "${results[@]}"; do
    IFS='|' read -r app path note <<< "$r"
    printf "%-20s %-50s %s\n" "$app" "$path" "$note"
  done
}

# ── 执行隐私清理 ──

clean_privacy() {
  local dry_run="$1"
  print_header "清理隐私痕迹"

  if [ "$dry_run" = true ]; then
    print_info "dry-run 模式 — 以下操作可执行:"
  fi

  # Safari
  if [ -d "$HOME/Library/Caches/com.apple.Safari" ]; then
    print_sub "Safari 缓存"
    if [ "$dry_run" = false ]; then
      rm -rf "$HOME/Library/Caches/com.apple.Safari/"* 2>/dev/null || true
      print_ok "Safari 缓存已清理"
    else
      local s_size
      s_size=$(du_dir "$HOME/Library/Caches/com.apple.Safari")
      print_info "  Safari 缓存: $s_size"
    fi
  fi

  # Chrome 缓存
  local chrome_cache="$HOME/Library/Caches/Google/Chrome"
  if [ -d "$chrome_cache" ]; then
    print_sub "Chrome 缓存"
    if [ "$dry_run" = false ]; then
      rm -rf "$chrome_cache/"* 2>/dev/null || true
      print_ok "Chrome 缓存已清理"
    else
      local c_size
      c_size=$(du_dir "$chrome_cache")
      print_info "  Chrome 缓存: $c_size"
    fi
  fi

  # 剪贴板
  print_sub "系统剪贴板"
  if [ "$dry_run" = false ]; then
    pbcopy < /dev/null 2>/dev/null || true
    print_ok "剪贴板已清空"
  else
    print_info "  剪贴板可清空（pbcopy < /dev/null）"
  fi

  if [ "$dry_run" = true ]; then
    print_info "\n以上为 dry-run 预览。实际清理请加 --apply 参数。"
  fi
}

# ── 模块: 大文件扫描 ──

scan_large_files() {
  local dry_run="$1"
  local size_threshold="$2"
  print_header "大文件扫描（大于 $(hr_size "$size_threshold")）"

  print_sub "使用 Spotlight 索引扫描（最快方式）..."
  local results
  results=$(mdfind "kMDItemFSSize > $size_threshold" -onlyin / 2>/dev/null | head -50 || true)

  if [ -z "$results" ]; then
    print_info "未找到大于 $(hr_size "$size_threshold") 的文件（或索引不完整）"
    print_sub "尝试备用方案（find 遍历）..."
    local top20
    top20=$(find "$HOME" -type f -size +"$(( size_threshold / 1024 / 1024 ))"M 2>/dev/null -exec ls -lhS {} + | awk '{print $5, $NF}' | head -20)
    if [ -n "$top20" ]; then
      echo ""
      echo "$top20" | while read -r size path; do
        echo "  $size  $path"
      done
    else
      print_info "未找到大文件"
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
      [ "$count" -ge 30 ] && { print_info "...（仅显示前 30 个）"; break; }
    done <<< "$results"
  fi
}

# ── 模块: 重复文件扫描 ──

scan_duplicates() {
  local dry_run="$1"
  print_header "重复文件扫描"
  print_info "扫描重复文件可能较慢，默认在 ~/Documents 和 ~/Downloads 中查找"

  local scan_dirs=("$HOME/Documents" "$HOME/Downloads" "$HOME/Desktop")
  local tmpfile
  tmpfile=$(mktemp)
  local found=false

  for dir in "${scan_dirs[@]}"; do
    if [ ! -d "$dir" ]; then continue; fi
    print_sub "扫描: $dir"
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
    print_info "未发现重复文件"
  fi
  rm -f "$tmpfile"
}

# ── 模块: 恶意软件检测 ──

scan_malware() {
  local dry_run="$1"
  print_header "恶意软件检测"

  # XProtect
  print_sub "XProtect 状态"
  if command -v xprotect &>/dev/null; then
    xprotect version 2>/dev/null && print_ok "XProtect 已启用" || print_warn "XProtect 不可用"
  else
    print_warn "xprotect 命令不可用（需 macOS Sequoia 15+）"
  fi

  # XProtect 完整检测（需 root）
  print_sub "XProtect 恶意软件扫描"
  if command -v xprotect &>/dev/null; then
    if sudo xprotect check --json 2>/dev/null | grep -q '"malware"'; then
      local result
      result=$(sudo xprotect check --json 2>/dev/null)
      print_ok "XProtect 扫描完成"
      echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
    else
      print_info "XProtect 检查需要完整磁盘访问权限"
      print_info "运行: sudo xprotect check --json"
    fi
  fi

  # 登录项
  echo ""
  print_sub "登录项（开机自启应用）"
  local login_items
  login_items=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null)
  if [ -n "$login_items" ]; then
    echo "$login_items" | tr ',' '\n' | while read -r item; do
      echo "  • $(echo "$item" | xargs)"
    done
  else
    print_info "无登录项"
  fi

  # Launch Agents
  echo ""
  print_sub "用户 Launch Agents（可能可疑项）"
  local agent_count
  agent_count=$(ls "$HOME/Library/LaunchAgents/" 2>/dev/null | wc -l | tr -d ' ')
  print_info "用户 Launch Agents 数量: $agent_count"
  local agent_files=()
  while IFS= read -r -d '' f; do
    agent_files+=("$f")
  done < <(find "$HOME/Library/LaunchAgents/" -name "*.plist" -maxdepth 1 2>/dev/null -print0)
  for f in "${agent_files[@]:0:10}"; do
    local label
    label=$(plutil -p "$f" 2>/dev/null | grep '"Label"' | awk -F'"' '{print $4}' || basename "$f")
    echo "  • $label"
  done

  # 可疑进程
  echo ""
  print_sub "可疑进程检查"
  local susp_procs
  susp_procs=$(ps aux 2>/dev/null | grep -iE "(bundle|Maps|adware|spy|trojan|keylog)" | grep -v grep | grep -v "cmx.sh" || true)
  if [ -n "$susp_procs" ]; then
    print_warn "发现可疑进程:"
    echo "$susp_procs"
  else
    print_ok "未发现明显可疑进程"
  fi
}

# ── 模块: 性能优化 ──

cmd_optimize() {
  local dry_run="$1"
  print_header "性能优化"

  # 1) 释放内存
  print_sub "释放非活跃内存"
  if [ "$dry_run" = false ]; then
    if check_root_for "purge"; then
      sudo purge 2>/dev/null && print_ok "内存已释放" || print_warn "purge 失败（可能需要禁用 SIP）"
    else
      sudo purge 2>/dev/null && print_ok "内存已释放" || print_warn "purge 失败"
    fi
  else
    print_info "将执行: sudo purge（释放非活跃内存页面）"
  fi

  # 2) 刷新 DNS 缓存
  echo ""
  print_sub "刷新 DNS 缓存"
  if [ "$dry_run" = false ]; then
    sudo dscacheutil -flushcache 2>/dev/null || true
    sudo killall -HUP mDNSResponder 2>/dev/null || true
    print_ok "DNS 缓存已刷新"
  else
    print_info "将执行: sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
  fi

  # 3) 重建 Spotlight 索引
  echo ""
  print_sub "Spotlight 索引"
  local spotlight_status
  spotlight_status=$(mdutil -s / 2>/dev/null)
  echo "  $spotlight_status"
  if [ "$dry_run" = false ]; then
    if confirm "重建 Spotlight 索引（可能需要数小时）？"; then
      sudo mdutil -E / 2>/dev/null && print_ok "Spotlight 索引重建已触发" || print_warn "重建失败"
    fi
  fi

  # 4) 系统维护脚本（macOS 15+ 已移除 periodic，手动执行核心任务）
  echo ""
  print_sub "系统维护任务"
  if [ "$dry_run" = false ]; then
    # 清理临时目录
    if confirm "清理系统临时文件？"; then
      sudo rm -rf /private/var/tmp/* 2>/dev/null || true
      sudo rm -rf /private/tmp/* 2>/dev/null || true
      print_ok "临时文件已清理"
    fi
    # 重建动态链接器缓存
    if confirm "重建动态链接器缓存？"; then
      sudo update_dyld_shared_cache -force 2>/dev/null && print_ok "动态链接器缓存已重建" || print_warn "重建失败"
    fi
  else
    print_info "将执行以下维护任务:"
    print_info "  • 清理 /private/var/tmp/"
    print_info "  • 清理 /private/tmp/"
    print_info "  • 重建动态链接器缓存"
  fi

  if [ "$dry_run" = true ]; then
    print_info "\n以上为 dry-run 预览。实际执行请加 --apply 参数。"
  fi
}

# ── 模块: 应用卸载 ──

cmd_uninstall() {
  local app_name="$1"
  local dry_run="$2"

  if [ -z "$app_name" ]; then
    print_err "请指定应用名称，如: cmx uninstall 'AppName'"
    exit 1
  fi

  print_header "卸载应用: $app_name"

  # 查找应用
  print_sub "查找应用"
  local app_paths
  app_paths=$(mdfind "kMDItemKind == 'Application' && kMDItemDisplayName == '$app_name'cw" 2>/dev/null || true)
  if [ -z "$app_paths" ]; then
    # 使用 find 备选
    app_paths=$(find /Applications "$HOME/Applications" -maxdepth 3 -iname "*${app_name}*" -type d 2>/dev/null || true)
  fi

  if [ -z "$app_paths" ]; then
    print_warn "未找到应用 '$app_name'"
    # 尝试模糊搜索
    print_sub "模糊搜索..."
    local fuzzy
    fuzzy=$(mdfind "kMDItemKind == 'Application'" 2>/dev/null | grep -i "$app_name" | head -5 || true)
    if [ -z "$fuzzy" ]; then
      fuzzy=$(find /Applications "$HOME/Applications" -maxdepth 2 -name "*.app" 2>/dev/null | grep -i "$app_name" | head -5 || true)
    fi
    if [ -n "$fuzzy" ]; then
      print_info "您是否想卸载以下应用？"
      echo "$fuzzy" | while read -r f; do
        echo "  • $(basename "$f" .app)"
      done
    else
      print_info "未找到匹配的应用"
    fi
    exit 1
  fi

  # 显示应用信息
  echo ""
  while IFS= read -r app_path; do
    local app_bundle
    app_bundle=$(basename "$app_path")
    local app_size
    app_size=$(du_dir "$app_path")
    echo "  📦 $app_bundle"
    echo "     路径: $app_path"
    echo "     大小: $app_size"

    # 查找关联文件
    local app_basename
    app_basename=$(basename "$app_path" .app)
    local related_files=()
    print_sub "关联文件:"
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
    if confirm "确认卸载以上应用及其关联文件？此操作不可逆！"; then
      while IFS= read -r app_path; do
        local app_basename
        app_basename=$(basename "$app_path" .app)
        # 删除应用
        if [ -w "$(dirname "$app_path")" ]; then
          rm -rf "$app_path" && print_ok "已删除: $app_path"
        else
          sudo rm -rf "$app_path" && print_ok "已删除（需 sudo）: $app_path"
        fi
        # 删除关联文件
        for search_dir in "$HOME/Library/Preferences" "$HOME/Library/Application Support" "$HOME/Library/Caches" "$HOME/Library/Saved Application State"; do
          if [ -d "$search_dir" ]; then
            find "$search_dir" -maxdepth 2 -iname "*${app_basename}*" -exec rm -rf {} + 2>/dev/null || true
          fi
        done
      done <<< "$app_paths"
      print_ok "卸载完成"
    fi
  else
    print_info "\n以上为预览。实际卸载请加 --apply 参数。"
  fi
}

# ── 模块: 智能扫描（全模块汇总） ──

cmd_smart_scan() {
  local dry_run="$1"
  print_header "🧠 智能扫描 — 全模块汇总"
  print_info "同时扫描: 系统垃圾 + 隐私痕迹 + 大文件 + 恶意软件检测"
  echo ""

  scan_system_junk "$dry_run"
  echo ""
  scan_privacy "$dry_run"
  echo ""
  scan_large_files "$dry_run" "$LARGE_FILE_SIZE"
  echo ""
  scan_malware "$dry_run"

  print_header "智能扫描完成"
  print_info "可执行以下操作:"
  echo "  1. cmx clean system-junk --apply   清理系统垃圾"
  echo "  2. cmx clean privacy --apply       清理隐私痕迹"
  echo "  3. cmx optimize --apply             性能优化"
  echo "  4. cmx uninstall <应用名>           卸载应用"
}

# ── 主入口 ──

usage() {
  cat <<EOF
用法: cmx <命令> [模块] [选项]

命令:
  scan                      扫描所有模块（汇总报告）
  scan system-junk          扫描系统垃圾（缓存/日志/临时文件）
  scan privacy              扫描隐私痕迹（浏览器/剪贴板等）
  scan large-files          扫描大文件
  scan duplicates           扫描重复文件
  scan malware              恶意软件检测 + XProtect 扫描

  clean system-junk         清理系统垃圾
  clean privacy             清理隐私痕迹

  optimize                  性能优化（内存/DNS/维护任务）
  uninstall <应用名>        卸载应用及残留文件
  status                    系统状态概览
  help                      显示此帮助

选项:
  --apply                   实际执行（默认 dry-run 仅预览）
  --size N[KMG]             大文件阈值（如 --size 100M, --size 1G）
  --days N                  日志保留天数（默认 $OLD_FILE_DAYS）
  --json                    JSON 输出（实验性）

示例:
  cmx status                            # 系统状态
  cmx scan                              # 智能扫描全部
  cmx scan large-files --size 500M      # 扫描 >500MB 的大文件
  cmx clean system-junk --apply         # 清理系统垃圾
  cmx optimize --apply                  # 执行性能优化
  cmx uninstall "Xcode"                 # 预览卸载 Xcode 及相关文件
  cmx uninstall "Xcode" --apply         # 实际卸载

EOF
}

main() {
  [ $# -eq 0 ] && { usage; exit 0; }

  local cmd=""; local module=""; local app_name=""
  local positional=()

  # 解析参数，分离选项和位置参数
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) DRY_RUN=false; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      --size)
        shift; [ $# -eq 0 ] && { print_err "--size 需要值"; exit 1; }
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
      --days) shift; [ $# -eq 0 ] && { print_err "--days 需要值"; exit 1; }
        OLD_FILE_DAYS=$1; shift ;;
      --json) JSON_OUTPUT=true; shift ;;
      -h|--help|help) usage; exit 0 ;;
      --*) print_err "未知选项: $1"; usage; exit 1 ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  # 提取命令和子参数
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
        *) print_err "未知模块: $module"; usage; exit 1 ;;
      esac
      ;;
    clean)
      case "$module" in
        system-junk) clean_system_junk "$DRY_RUN" ;;
        privacy) clean_privacy "$DRY_RUN" ;;
        *) print_err "未知清理模块: $module"; usage; exit 1 ;;
      esac
      ;;
    optimize) cmd_optimize "$DRY_RUN" ;;
    uninstall)
      cmd_uninstall "$module" "$DRY_RUN"
      ;;
    status) cmd_status ;;
    smart-scan) cmd_smart_scan "$DRY_RUN" ;;
    "") usage ;;
    *) print_err "未知命令: $cmd"; usage; exit 1 ;;
  esac
}

main "$@"

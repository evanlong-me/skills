---
name: cleanmymac-x
description: 对标 CleanMyMac X，用命令行实现 Mac 系统清理、优化、安全检测、隐私保护等核心功能。提供扫描-清理两步操作，安全可控。附带 cmx 快捷脚本。
metadata:
  author: evanlong-me
  trigger_phrases: ["clean my mac", "清理 mac", "mac 清理", "系统垃圾", "缓存清理", "mac 优化", "cleanmymac", "mac 管家"]
---

# 对标 CleanMyMac X — 命令行系统管家

## 概述

CleanMyMac X 是 macOS 上最知名的系统管家类应用，核心包含 8 大功能模块：

| # | 模块 | CleanMyMac X 名称 | 危险等级 |
|---|------|-------------------|---------|
| 1 | **系统垃圾** | System Junk | 🟢 安全 |
| 2 | **隐私清理** | Privacy | 🟢 安全 |
| 3 | **大文件扫描** | Large & Old Files | 🟢 安全 |
| 4 | **重复文件** | Duplicates | 🟢 安全 |
| 5 | **恶意软件检测** | Malware Removal | 🟡 需注意 |
| 6 | **性能优化** | Speed / Maintenance | 🟡 需注意 |
| 7 | **应用卸载** | Uninstaller | 🔴 不可逆 |
| 8 | **智能扫描** | Smart Scan | 🟢 安全 |

本文档用纯命令行工具对每个模块进行对标实现，核心原则：

> **先扫描预览 → 确认后再清理**。所有清理操作默认 dry-run，实际执行需要用户确认。

## 快速入口

本 skill 附带 `scripts/cmx.sh` 快捷脚本，安装后可直接使用：

```bash
# 系统状态概览（磁盘/内存/负载/安全）
bash cmx.sh status

# 智能扫描（全模块汇总报告）
bash cmx.sh scan

# 清理系统垃圾（预览 → 确认后执行）
bash cmx.sh clean system-junk --apply

# 性能优化
bash cmx.sh optimize --apply

# 卸载应用
bash cmx.sh uninstall "AppName"
```

也可以直接执行文档中的单条命令进行精细控制。

---

## 模块 1：系统垃圾 (System Junk)

### 原理

CleanMyMac X 的 System Junk 扫描以下 macOS 系统位置：

| 项目 | 路径 | CleanMyMac 检测逻辑 |
|------|------|-------------------|
| **用户缓存** | `~/Library/Caches/` | 每个应用子目录的大小，可安全删除 |
| **系统缓存** | `/Library/Caches/` | 同上，部分需 root |
| **用户日志** | `~/Library/Logs/` | 按文件数量和过期天数评估 |
| **系统日志** | `/Library/Logs/`, `/private/var/log/` | 同上 |
| **Xcode 派生数据** | `~/Library/Developer/Xcode/DerivedData/` | 编译中间产物，可安全删除 |
| **Xcode 归档** | `~/Library/Developer/Xcode/Archives/` | 已分发的 .xcarchive |
| **iOS 备份** | `~/Library/Application Support/MobileSync/Backup/` | 旧设备备份 |
| **语言文件** | `*.app/Contents/Resources/*.lproj` | 保留当前语言，删多余语言包 |
| **废纸篓** | `~/.Trash/` | 已删除文件的暂存 |
| **临时文件** | `/private/tmp/`, `/private/var/tmp/` | 系统临时文件 |
| **Homebrew 缓存** | `$(brew --cache)` | 旧版本包缓存 |
| **npm/pnpm/yarn 缓存** | (各包管理器缓存目录) | node 生态依赖缓存 |

macOS 自身不会自动清理应用缓存和残留文件 —— 这就是工具的价值所在。

### 扫描

```bash
# ── 用户缓存 ──
echo "=== 用户缓存 ===" && du -sh ~/Library/Caches/ 2>/dev/null
echo "Top 10 缓存子目录:" && du -sh ~/Library/Caches/*/ 2>/dev/null | sort -rh | head -10

# ── 系统缓存 ──
echo "=== 系统缓存 ===" && du -sh /Library/Caches/ 2>/dev/null

# ── 日志文件 ──
echo "=== 用户日志 ===" && du -sh ~/Library/Logs/ 2>/dev/null
echo "超过 30 天的日志:" && find ~/Library/Logs -type f -mtime +30 2>/dev/null | wc -l
echo "=== 系统日志 ===" && du -sh /Library/Logs/ 2>/dev/null
echo "=== var/log ===" && du -sh /private/var/log/ 2>/dev/null

# ── Xcode ──
echo "=== Xcode DerivedData ===" && du -sh ~/Library/Developer/Xcode/DerivedData/ 2>/dev/null
echo "=== Xcode Archives ===" && du -sh ~/Library/Developer/Xcode/Archives/ 2>/dev/null

# ── iOS 备份 ──
echo "=== iOS 备份 ===" && du -sh ~/Library/Application\ Support/MobileSync/Backup/ 2>/dev/null

# ── 废纸篓 ──
echo "=== 废纸篓 ===" && du -sh ~/.Trash/ 2>/dev/null

# ── 临时文件 ──
echo "=== 临时文件 ===" && du -sh /private/tmp/ /private/var/tmp/ 2>/dev/null

# ── Homebrew 缓存（如安装） ──
which brew >/dev/null 2>&1 && echo "=== Homebrew 缓存 ===" && du -sh $(brew --cache) 2>/dev/null

# ── npm 缓存（如安装） ──
which npm >/dev/null 2>&1 && echo "=== npm 缓存 ===" && du -sh $(npm cache dir) 2>/dev/null
```

### 清理

> ⚠️ **清理缓存前最好退出所有正在运行的应用**，部分应用运行中删除缓存可能异常。

```bash
# 1. 清理超过 30 天的日志（安全）
find ~/Library/Logs -type f -mtime +30 -delete 2>/dev/null && echo "✓ 旧日志已清理"

# 2. 清理系统日志（需 sudo）
sudo find /private/var/log -type f -mtime +30 -delete 2>/dev/null && echo "✓ 系统日志已清理"

# 3. 清空废纸篓
rm -rf ~/.Trash/* 2>/dev/null && echo "✓ 废纸篓已清空"

# 4. 清理 Xcode DerivedData（Xcode 会重建）
rm -rf ~/Library/Developer/Xcode/DerivedData/* 2>/dev/null && echo "✓ DerivedData 已清理"

# 5. 清理 Homebrew 缓存
brew cleanup -s 2>/dev/null && echo "✓ Homebrew 缓存已清理"

# 6. 清理 npm 缓存
npm cache clean --force 2>/dev/null && echo "✓ npm 缓存已清理"

# 7. 清理用户缓存（最激进，谨慎使用）
# rm -rf ~/Library/Caches/*
```

### 语言文件清理（进阶）

CleanMyMac X 会删除应用中不需要的多余语言包，只保留你使用的语言：

```bash
# 查看一个应用包含的语言包
ls /Applications/Safari.app/Contents/Resources/ | grep lproj

# 保留中文和英文，删除其他（以某个应用为例）
# find /Applications/SomeApp.app -name "*.lproj" ! -name "zh*" ! -name "en*" -exec rm -rf {} +
```

> 实际按需执行，不要对所有应用批量操作。

---

## 模块 2：隐私清理 (Privacy)

### 原理

CleanMyMac X 清理三类隐私痕迹：

| 类别 | 内容 | 路径 |
|------|------|------|
| **浏览器痕迹** | 缓存、历史记录、Cookie、LocalStorage | 每个浏览器不同位置 |
| **系统痕迹** | 最近文件、剪贴板、最近搜索 | Finder / 系统服务 |
| **通信痕迹** | 消息附件、通话记录 | Messages / FaceTime |

### 扫描

```bash
# ── Safari ──
echo "=== Safari ==="
echo "缓存:" && du -sh ~/Library/Caches/com.apple.Safari/ 2>/dev/null
echo "历史:" && ls -lh ~/Library/Safari/History.db 2>/dev/null

# ── Chrome ──
echo "=== Google Chrome ==="
echo "缓存:" && du -sh ~/Library/Caches/Google/Chrome/ 2>/dev/null
echo "历史文件:" && ls -lh ~/Library/Application\ Support/Google/Chrome/Default/History 2>/dev/null

# ── Firefox ──
echo "=== Firefox ==="
ls ~/Library/Application\ Support/Firefox/Profiles/ 2>/dev/null

# ── 最近文件 ──
echo "=== 最近文件 ==="
mdfind "kMDItemLastUsedDate >= \$time.today(-7)" -onlyin ~/Documents 2>/dev/null | head -20

# ── 剪贴板 ──
echo "=== 剪贴板 ==="
pbpaste 2>/dev/null | head -3 || echo "(空)"
```

### 清理

```bash
# Safari 缓存（浏览器运行中的时候也可以清理）
rm -rf ~/Library/Caches/com.apple.Safari/* 2>/dev/null

# Chrome 缓存（浏览器运行中清理会导致其重新下载资源）
rm -rf ~/Library/Caches/Google/Chrome/* 2>/dev/null

# 清空剪贴板
pbcopy < /dev/null

# 清除最近文件记录（Finder 重启后生效）
osascript -e 'tell application "Finder" to set the name of every item of trash to ""' 2>/dev/null

# 清除 Safari 浏览历史（会删除 History.db）
# rm ~/Library/Safari/History.db  # Safari 运行时会重建
```

> 浏览器清理后，重新打开浏览器时会重新下载资源，首次加载略慢。

---

## 模块 3：大文件扫描 (Large & Old Files)

### 原理

CleanMyMac X 使用 Spotlight 索引（`mdfind`）快速定位大文件，比遍历文件系统快得多。

### 扫描

```bash
# 使用 Spotlight 索引（最快）: 查找大于 1GB 的文件
mdfind "kMDItemFSSize > 1000000000" 2>/dev/null | head -30

# 查看文件大小
mdfind "kMDItemFSSize > 1000000000" 2>/dev/null | while read f; do
  [ -f "$f" ] && echo "$(stat -f%z "$f" 2>/dev/null | xargs -I {} echo "scale=1; {} / 1073741824" | bc 2>/dev/null)GB  $f"
done | sort -rn | head -30

# 备选：使用 find 遍历（慢但无需索引）
find ~ -type f -size +1G 2>/dev/null -exec ls -lhS {} + | awk '{print $5, $NF}' | head -20

# 查找旧文件（超过 1 年未访问）
find ~ -type f -atime +365 2>/dev/null | head -20

# 查找大文件夹
du -sh ~/*/ 2>/dev/null | sort -rh | head -10
du -sh ~/Library/*/ 2>/dev/null | sort -rh | head -10
```

### 清理

根据扫描结果手动确认后，直接 `rm` 或 `trash`：

```bash
# 安全做法：移到废纸篓而非直接删除
# osascript -e "tell application \"Finder\" to delete POSIX file \"$PWD/large-file.mp4\""

# 直接删除（确认后）
# rm -i /path/to/unwanted/large/file.mkv
```

---

## 模块 4：重复文件 (Duplicates)

### 原理

CleanMyMac X 通过文件哈希（MD5/SHA）比对来发现重复文件。同样的方法可用 `md5` + `sort` + `uniq` 实现。

### 扫描

```bash
# 在 Documents 中查找重复文件（按 MD5 分组）
echo "扫描 ~/Documents 中的重复文件（基于 MD5）..."
find ~/Documents -type f -size +1k 2>/dev/null \
  -exec md5 -r {} \; \
  | sort \
  | awk '{seen[$1]++; lines[$1]=lines[$1] ? lines[$1]"\n  "$2 : "  "$2} \
         END{for(h in seen) if(seen[h]>1) printf "--- MD5: %s ---\n%s\n\n", h, lines[h]}'

# 同样方法扫描 Downloads
echo "扫描 ~/Downloads..."
find ~/Downloads -type f -size +1k 2>/dev/null \
  -exec md5 -r {} \; \
  | sort \
  | awk '{seen[$1]++; lines[$1]=lines[$1] ? lines[$1]"\n  "$2 : "  "$2} \
         END{for(h in seen) if(seen[h]>1) printf "--- MD5: %s ---\n%s\n\n", h, lines[h]}'
```

### 清理

根据扫描结果手动确认后删除重复文件，保留一份即可。

---

## 模块 5：恶意软件检测 (Malware Removal)

### 原理

macOS 内置了多层安全防护：

| 层级 | 技术 | 说明 |
|------|------|------|
| **XProtect** | 签名扫描 | Apple 维护的恶意软件签名数据库，自动更新 |
| **Gatekeeper** | 应用公证检查 | 阻止未公证的应用运行 |
| **Notarization** | 代码签名 | 开发者需经过 Apple 审核 |

CleanMyMac X 的 Malware Removal 本质上是对 XProtect 的封装 + 扫描常见恶意软件安装位置。

### 检测

```bash
# 1. XProtect 版本和状态
xprotect version 2>/dev/null || echo "XProtect 不可用（需 macOS 15+）"

# 2. XProtect 完整扫描（需 root，macOS 15+）
sudo xprotect check --json 2>/dev/null || echo "需要完整磁盘访问权限"

# 3. 检查登录项（恶意软件常在此设持久化）
osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null

# 4. 检查 Launch Agents（用户级开机启动项）
ls ~/Library/LaunchAgents/ 2>/dev/null
# 查看可疑 plist
for f in ~/Library/LaunchAgents/*.plist; do
  [ -f "$f" ] && echo "--- $(basename $f) ---" && plutil -p "$f" 2>/dev/null | grep -E '"Program|ProgramArguments|Label"' | head -5
done

# 5. 检查可疑进程
ps aux | grep -iE "(adware|spy|trojan|keylogger|miner|crypto)" | grep -v grep

# 6. 检查浏览器扩展（Chrome）
ls ~/Library/Application\ Support/Google/Chrome/Default/Extensions/ 2>/dev/null

# 7. 检查系统扩展
systemextensionsctl list 2>/dev/null
```

### 安全建议

- macOS 内置防护（XProtect + Gatekeeper + SIP）已经很强
- 保持系统更新：`softwareupdate --list`
- 不要从非官方渠道下载应用
- 如果真怀疑感染，可以用 [Malwarebytes for Mac](https://www.malwarebytes.com/mac) 免费版扫描

---

## 模块 6：性能优化 (Speed / Maintenance)

### 原理

CleanMyMac X 的 Speed 模块包含：

| 子功能 | 实现方式 | 效果 |
|--------|---------|------|
| **释放内存** | `purge` 命令 | 清除非活跃内存页面 |
| **维护脚本** | ~~`periodic`~~ (macOS 15+ 已移除) | 清理临时文件、rotatelogs |
| **DNS 刷新** | `dscacheutil` + `killall -HUP mDNSResponder` | 清空 DNS 缓存 |
| **Spotlight 重建** | `mdutil -E` | 修复搜索结果异常 |
| **动态链接器缓存** | `update_dyld_shared_cache` | 加速应用启动 |

### 执行

```bash
# 1. 释放非活跃内存（需 sudo）
echo "=== 内存状态 ==="
vm_stat | head -10
sudo purge && echo "✓ 内存已释放"

# 2. 刷新 DNS 缓存
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder && echo "✓ DNS 缓存已刷新"

# 3. 重建 Spotlight 索引（需较长时间）
# sudo mdutil -E / && echo "✓ Spotlight 重建已触发"

# 4. 清理系统临时文件
sudo rm -rf /private/var/tmp/* 2>/dev/null
sudo rm -rf /private/tmp/* 2>/dev/null
echo "✓ 临时文件已清理"

# 5. 重建动态链接器缓存（建议在系统更新后执行）
# sudo update_dyld_shared_cache -force 2>/dev/null && echo "✓ 动态链接器缓存已重建"
```

### macOS 15+ 注意事项

> macOS Sequoia (15) 移除了 `periodic` 命令。上述步骤 2/4 是 `periodic` 的核心工作内容，直接手动执行替代。

---

## 模块 7：应用卸载 (Uninstaller)

### 原理

直接将 `.app` 拖入废纸篓会残留配置文件。CleanMyMac X 会查找并删除：

| 残留类型 | 路径模式 |
|----------|---------|
| 偏好设置 | `~/Library/Preferences/com.developer.appname.plist` |
| 应用支持 | `~/Library/Application Support/appname/` |
| 缓存 | `~/Library/Caches/com.developer.appname/` |
| 保存状态 | `~/Library/Saved Application State/com.developer.appname.savedState/` |
| 容器 | `~/Library/Containers/com.developer.appname/` |
| 组容器 | `~/Library/Group Containers/*.appname/` |

### 查找并卸载

```bash
# 步骤 1：查找应用
mdfind "kMDItemKind == 'Application' && kMDItemDisplayName == 'AppName'cw"
# 备选
find /Applications -iname "*AppName*" -maxdepth 2

# 步骤 2：列出该应用的所有关联文件
# 将 AppName 替换为实际应用名
app="AppName"
echo "=== 应用本体 ===" && find /Applications ~/Applications -maxdepth 2 -iname "*${app}*" -type d 2>/dev/null
echo "=== 偏好设置 ===" && find ~/Library/Preferences -maxdepth 2 -iname "*${app}*" 2>/dev/null
echo "=== 应用支持 ===" && find ~/Library/Application\ Support -maxdepth 3 -iname "*${app}*" 2>/dev/null
echo "=== 缓存 ===" && find ~/Library/Caches -maxdepth 2 -iname "*${app}*" 2>/dev/null
echo "=== 保存状态 ===" && find ~/Library/Saved\ Application\ State -maxdepth 2 -iname "*${app}*" 2>/dev/null
echo "=== 容器 ===" && find ~/Library/Containers -maxdepth 2 -iname "*${app}*" 2>/dev/null

# 步骤 3：删除（确认后）
app="AppName"
# 删除应用本体
sudo rm -rf "/Applications/${app}.app" 2>/dev/null || rm -rf ~/Applications/"${app}.app" 2>/dev/null
# 删除配置文件
find ~/Library/Preferences ~/Library/Application\ Support ~/Library/Caches \
  ~/Library/Saved\ Application\ State ~/Library/Containers \
  -maxdepth 3 -iname "*${app}*" -exec rm -rf {} + 2>/dev/null
echo "✓ ${app} 及相关文件已删除"
```

---

## 模块 8：智能扫描 (Smart Scan)

### 原理

CleanMyMac X 的 Smart Scan 是把系统垃圾 + 恶意软件 + 性能优化三个模块的扫描合并为一次一键操作。

**命令行对标方案 A：组合运行各扫描模块**

```bash
echo "==============================="
echo " 智能扫描 - 全模块汇总"
echo "==============================="
echo ""

echo "=== 1/4 系统垃圾 ==="
du -sh ~/Library/Caches/ ~/Library/Logs/ ~/.Trash/ ~/Library/Developer/Xcode/DerivedData/ 2>/dev/null

echo ""
echo "=== 2/4 大文件 (>1GB) ==="
mdfind "kMDItemFSSize > 1000000000" 2>/dev/null | head -10

echo ""
echo "=== 3/4 重复文件 ==="
find ~/Documents ~/Downloads -type f -size +1k 2>/dev/null \
  -exec md5 -r {} \; | sort | awk '{seen[$1]++; lines[$1]=lines[$1] ? lines[$1]"\n  "$2 : "  "$2} \
  END{for(h in seen) if(seen[h]>1) printf "重复: %s\n%s\n", h, lines[h]}' | head -50

echo ""
echo "=== 4/4 系统状态 ==="
echo "磁盘可用:" && df -h / | tail -1 | awk '{print $4}'
echo "XProtect:" && xprotect version 2>/dev/null
```

**方案 B：使用 cmx.sh 脚本**

```bash
bash /path/to/scripts/cmx.sh scan
```

---

## 安全须知

### 通用原则

| 等级 | 含义 | 操作示例 |
|------|------|---------|
| 🟢 **安全** | 文件由系统/应用自动生成，可安全删除 | 缓存、日志、DerivedData |
| 🟡 **需注意** | 操作影响系统行为，但有恢复方法 | 清 DNS 缓存、purge |
| 🔴 **有风险** | 操作不可逆，删除前必须再三确认 | 卸载应用、删除文件 |

### 最佳实践

1. **先扫描，再清理**：永远不要跳过扫描步骤直接清理
2. **退出应用再清缓存**：避免应用运行中缓存被删除导致异常
3. **保留最近日志**：建议只删除 30 天前的日志
4. **大文件手动检查**：有些大文件是工作必需（虚拟机、素材库）
5. **不要随意删系统缓存**：`/Library/Caches/` 部分缓存是系统组件所需的

### 恢复指引

如果不小心删除了系统需要的缓存文件：

- 应用缓存：重启对应应用即可重建
- 系统缓存：重启 Mac 即可重建
- Xcode DerivedData：下次编译时自动重建
- Spotlight 索引：`mdutil -E /` 重建

---

## 附：cmx.sh 脚本参考

本 skill 附带 `scripts/cmx.sh` 一键脚本，封装了上述所有功能。

### 安装

```bash
# 添加别名到 shell 配置
echo 'alias cmx="bash /path/to/cleanmymac-x/scripts/cmx.sh"' >> ~/.zshrc
source ~/.zshrc
```

### 命令一览

```bash
cmx status                # 系统状态（磁盘/内存/负载）
cmx scan                  # 智能扫描（全模块）
cmx scan system-junk      # 仅扫描系统垃圾
cmx scan privacy          # 仅扫描隐私痕迹
cmx scan large-files      # 仅扫描大文件（默认 >3GB）
cmx scan duplicates       # 仅扫描重复文件
cmx scan malware          # 仅恶意软件检测
cmx clean system-junk     # 清理系统垃圾（dry-run）
cmx clean system-junk --apply   # 确认后清理
cmx clean privacy --apply       # 清理隐私痕迹
cmx optimize --apply      # 性能优化
cmx uninstall "AppName"   # 预览卸载
cmx uninstall "AppName" --apply # 实际卸载
```

### 选项

| 选项 | 说明 | 默认 |
|------|------|------|
| `--apply` | 实际执行清理（默认预览） | dry-run |
| `--size 500M` | 大文件阈值 | 3GB |
| `--days 30` | 日志保留天数 | 365 |

---

## 参考

- [CleanMyMac X 核心功能详解 — 少数派](https://sspai.com/post/65914)
- [Apple 官方存储空间释放指南](https://support.apple.com/zh-cn/102624)
- [XProtect 命令行文档 (man page)](https://manp.gs/mac/1/xprotect)
- [macOS 安全防护 — Apple 官方](https://support.apple.com/guide/security/protecting-against-malware-sec469d47bd8/1/web/1)

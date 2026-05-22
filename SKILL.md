---
name: github-ip-auto-fix
description: GitHub hosts IP 自动检测和修复机制 - 解决服务器连接 GitHub 443 端口超时问题
tags: [github, network, hosts, devops, automation]
---

# GitHub IP 自动检测和修复

## 问题描述

### 问题一：IP 失效（网络层）

服务器 `/etc/hosts` 中配置的 GitHub IP 会周期性失效，表现为：
- `ping` 能通（ICMP 协议正常）
- 但 443 端口不通（TCP 连接超时）
- 导致 `git push/pull` 失败

### 问题二：Token 403（认证层）

GitHub Token 对 REST API 完全有效（读写均正常），但对 git HTTPS 协议返回 403 Forbidden。
- **解决**：去 GitHub 网页端重新生成 Personal Access Token (classic)，勾选 `repo` 权限
- **临时方案**：通过 GitHub REST API 的 Contents endpoint 推送文件

## 解决方案（三级降级）

### 优先级排序

| 级别 | 方案 | 优点 | 缺点 |
|------|------|------|------|
| 🥇 优先 | 公共源 hosts.gitcdn.top | 自动维护 IP、更新频繁 | 依赖外部服务 |
| 🥈 降级 | 手动 IP 池轮换 | 不依赖外部、可控性强 | 需要手动维护 |
| 🥉 兜底 | GitHub REST API | 绕过 git 协议问题 | 只能推送，不能拉取 |

## 脚本部署

### 主脚本：/home/ubuntu/scripts/fix_github_hosts.sh

脚本包含以下功能：
1. `main()` - 自动检测并修复 hosts（公共源 + IP 池）
2. `push_via_api()` - 使用 GitHub REST API 推送单个文件
3. `push_all_via_api()` - 批量推送所有修改的文件

### 部署步骤

```bash
# 1. 创建脚本目录
mkdir -p /home/ubuntu/scripts

# 2. 下载脚本
curl -sL https://raw.githubusercontent.com/SparkTech-2049/github-ip-auto-fix/main/scripts/fix_github_hosts.sh -o /home/ubuntu/scripts/fix_github_hosts.sh
curl -sL https://raw.githubusercontent.com/SparkTech-2049/github-ip-auto-fix/main/scripts/check_and_update_github_ips.sh -o /home/ubuntu/scripts/check_and_update_github_ips.sh

# 3. 设置权限
chmod +x /home/ubuntu/scripts/fix_github_hosts.sh
chmod +x /home/ubuntu/scripts/check_and_update_github_ips.sh

# 4. 更新 crontab
(crontab -l 2>/dev/null | grep -v "fix_github_hosts.sh\|check_and_update_github_ips.sh"; \
 echo "*/30 * * * * /home/ubuntu/scripts/fix_github_hosts.sh >> /tmp/fix_github_hosts.log 2>&1"; \
 echo "0 2 * * 0,1,3,5 /home/ubuntu/scripts/check_and_update_github_ips.sh >> /tmp/github_ip_check.log 2>&1") | crontab -
```

### Cron 任务说明

| 任务 | 时间 | 功能 |
|------|------|------|
| `fix_github_hosts.sh` | 每 30 分钟 | 检测并修复 hosts，确保 git push/pull 正常 |
| `check_and_update_github_ips.sh` | 每周一三五日 02:00 | 从多个来源获取最新 IP，自动更新 IP 池 |

## 使用方法

### 1. 自动修复 hosts

```bash
# 直接执行，自动检测并修复
/home/ubuntu/scripts/fix_github_hosts.sh

# 输出示例：
# OK - 连接正常
# FIXED:public-source - 从公共源修复
# FIXED:140.82.114.20 - 从 IP 池修复
# FAILED - 所有方案失败
```

### 2. git push 超时时使用 API 推送

```bash
# 推送单个文件
source /home/ubuntu/scripts/fix_github_hosts.sh
push_via_api "desktop.html" "feat: 新功能"

# 批量推送所有修改的文件
push_all_via_api "feat: 批量更新"
```

### 3. 在 Cron 任务中使用

```bash
# 在 git 操作前自动修复
/home/ubuntu/scripts/fix_github_hosts.sh && git push origin main

# 如果 git push 超时，降级到 API 推送
git push origin main || source /home/ubuntu/scripts/fix_github_hosts.sh && push_all_via_api
```

## 输出说明

| 输出 | 含义 |
|------|------|
| `OK` | 当前连接正常，无需处理 |
| `FIXED:public-source` | 从公共源修复成功 |
| `FIXED:xxx.xxx.xxx.xxx` | 从 IP 池修复成功 |
| `OK:commit_sha` | API 推送成功 |
| `FAILED` | 所有方案都失败 |
| `PARTIAL` | 批量推送部分成功 |

## 日志文件

- 修复日志：`/tmp/github_fix.log`
- 查看日志：`tail -f /tmp/github_fix.log`

## IP 池维护指南

### 检查当前 IP 是否可用

```bash
# 测试单个 IP 的 443 端口
timeout 3 bash -c "echo >/dev/tcp/140.82.114.4/443" && echo "✓ 可用" || echo "✗ 不可用"

# 批量测试 IP 池
for ip in 140.82.114.4 140.82.114.20 140.82.112.4 140.82.113.4 20.205.243.166; do
    timeout 3 bash -c "echo >/dev/tcp/$ip/443" 2>/dev/null && echo "✓ $ip" || echo "✗ $ip"
done
```

### 获取最新可用 IP

```bash
# 方法 1：通过 DNS 查询
nslookup github.com
dig github.com +short

# 方法 2：从公共源提取
curl -s https://hosts.gitcdn.top/hosts.txt | grep github.com

# 方法 3：在线查询
# https://www.ipaddress.com/website/github.com/
# https://github.com.ipaddress.com/
```

### 更新 IP 池

编辑脚本中的 `IP_POOL` 数组：

```bash
# /home/ubuntu/scripts/fix_github_hosts.sh
IP_POOL=(
    "140.82.114.4"    # 优先级 1
    "140.82.114.20"   # 优先级 2
    "140.82.112.4"    # 优先级 3
    # 添加新发现的 IP：
    # "xxx.xxx.xxx.xxx"
)
```

### 维护频率（自动化）

**每周一三五日自动检查更新：**

```bash
# 添加到 crontab（每周一三五日 02:00 执行）
0 2 * * 0,1,3,5 /home/ubuntu/scripts/check_and_update_github_ips.sh >> /tmp/github_ip_check.log 2>&1
```

**手动检查：**
```bash
# 立即执行一次检查
/home/ubuntu/scripts/check_and_update_github_ips.sh
```

### 快速诊断命令

```bash
# 查看当前 hosts 配置
grep github /etc/hosts

# 查看最近修复日志
tail -20 /tmp/github_fix.log

# 测试 git 连接
git ls-remote https://github.com/octocat/Hello-World.git HEAD
```

## 注意事项

1. **IP 有效期**：GitHub IP 可能在几个月后失效，建议每月检查一次
2. **公共源依赖**：hosts.gitcdn.top 可能不可用，脚本会自动降级到 IP 池
3. **Token 安全**：`.git-credentials` 文件包含敏感信息，注意权限设置
4. **API 限制**：GitHub API 有频率限制，批量推送时注意控制频率
5. **sudo 权限**：修改 `/etc/hosts` 需要 sudo 权限

## 适用场景

- 服务器在国内，连接 GitHub 不稳定
- 使用 hosts 文件手动配置 GitHub IP
- 需要自动化 git push/pull 的场景
- git push 经常超时，需要兜底方案

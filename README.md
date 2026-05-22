# GitHub IP Auto Fix

自动修复 GitHub hosts IP 的工具，解决服务器连接 GitHub 443 端口超时问题。

## 三级降级方案

| 方案 | 优先级 | 说明 |
|------|--------|------|
| 公共源 | 🥇 优先 | hosts.gitcdn.top 自动维护的公共 hosts 文件 |
| 手动 IP 池 | 🥈 降级 | 预设的 GitHub IP 列表轮换测试 |
| GitHub REST API | 🥉 兜底 | git push 超时时直接调用 API 推送 |

## 快速使用

```bash
# 1. 复制脚本到本地
cp scripts/fix_github_hosts.sh ~/scripts/
chmod +x ~/scripts/fix_github_hosts.sh

# 2. 手动测试
~/scripts/fix_github_hosts.sh

# 3. 添加到 crontab（每30分钟自动执行）
(crontab -l 2>/dev/null; echo "*/30 * * * * /home/\$USER/scripts/fix_github_hosts.sh >> /tmp/fix_github_hosts.log 2>&1") | crontab -
```

## 输出说明

- `OK` - GitHub 连接正常，无需修复
- `FIXED:public-source` - 从公共源修复成功
- `FIXED:140.82.114.20` - 从手动 IP 池修复成功
- `FAILED` - 所有方案都失败

## Git Push 超时？用 API 推送

```bash
# 设置 GitHub Token
export GITHUB_TOKEN="your_github_token"

# 加载函数
source ~/scripts/fix_github_hosts.sh

# 使用 API 推送文件
push_via_api "README.md" "docs: update README"
```

## 文件结构

```
├── SKILL.md                    # Hermes Agent skill 文档
├── scripts/
│   └── fix_github_hosts.sh     # 修复脚本
└── README.md                   # 本文件
```

## 适用场景

- 服务器无法访问 github.com:443
- git push/pull 超时
- 国内服务器访问 GitHub 不稳定

## License

MIT

#!/bin/bash
# GitHub hosts IP 自动修复脚本
# 使用方法: /home/ubuntu/scripts/fix_github_hosts.sh
# 输出: OK | FIXED:来源 | FAILED

HOSTS_FILE="/etc/hosts"
BACKUP_FILE="/etc/hosts.bak.$(date +%Y%m%d%H%M%S)"
LOG_FILE="/tmp/fix_github_hosts.log"

# 公共 hosts 源（优先使用）
PUBLIC_HOSTS_URL="https://hosts.gitcdn.top/hosts.txt"

# 手动 IP 池（降级方案）
IP_POOL=(
    "140.82.114.4"
    "140.82.114.20"
    "140.82.112.4"
    "140.82.113.4"
    "20.205.243.166"
)

DOMAINS=("github.com" "gist.github.com" "api.github.com" "raw.githubusercontent.com" "github.io")

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 测试 GitHub 连接
test_github() {
    local timeout=5
    local test_urls=("https://github.com" "https://api.github.com")
    
    for url in "${test_urls[@]}"; do
        if curl -s --connect-timeout "$timeout" --max-time 10 "$url" > /dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# 备份 hosts 文件
backup_hosts() {
    if [ -f "$HOSTS_FILE" ]; then
        cp "$HOSTS_FILE" "$BACKUP_FILE"
        log "Hosts 备份: $BACKUP_FILE"
    fi
}

# 清理 hosts 中的 GitHub 条目
clean_github_hosts() {
    sudo sed -i '/github\.com/d' "$HOSTS_FILE"
    sudo sed -i '/github\.io/d' "$HOSTS_FILE"
    sudo sed -i '/githubusercontent\.com/d' "$HOSTS_FILE"
}

# 方案1: 从公共源更新
update_from_public() {
    log "尝试从公共源更新..."
    
    local temp_file="/tmp/public_hosts.txt"
    if curl -s --connect-timeout 10 --max-time 30 "$PUBLIC_HOSTS_URL" -o "$temp_file"; then
        # 提取 GitHub 相关条目
        local github_lines=$(grep -i "github" "$temp_file" | grep -v "^#" | head -20)
        
        if [ -n "$github_lines" ]; then
            backup_hosts
            clean_github_hosts
            echo "$github_lines" | sudo tee -a "$HOSTS_FILE" > /dev/null
            log "公共源更新成功"
            rm -f "$temp_file"
            return 0
        fi
    fi
    
    rm -f "$temp_file"
    log "公共源更新失败"
    return 1
}

# 方案2: 使用手动 IP 池
update_from_pool() {
    log "尝试使用手动 IP 池..."
    
    backup_hosts
    clean_github_hosts
    
    # 使用第一个可用的 IP
    local selected_ip="${IP_POOL[0]}"
    
    for domain in "${DOMAINS[@]}"; do
        echo "$selected_ip $domain" | sudo tee -a "$HOSTS_FILE" > /dev/null
    done
    
    log "手动 IP 池更新: $selected_ip"
    return 0
}

# 刷新 DNS 缓存
refresh_dns() {
    if command -v systemd-resolve &> /dev/null; then
        sudo systemd-resolve --flush-caches 2>/dev/null
    elif command -v resolvectl &> /dev/null; then
        sudo resolvectl flush-caches 2>/dev/null
    fi
    log "DNS 缓存已刷新"
}

# 主流程
main() {
    log "========== 开始检测 =========="
    
    # 1. 测试当前连接
    if test_github; then
        log "GitHub 连接正常"
        echo "OK"
        exit 0
    fi
    
    log "GitHub 连接异常，开始修复..."
    
    # 2. 方案1: 公共源
    if update_from_public; then
        refresh_dns
        sleep 2
        if test_github; then
            log "公共源修复成功"
            echo "FIXED:public-source"
            exit 0
        fi
    fi
    
    # 3. 方案2: 手动 IP 池
    for ip in "${IP_POOL[@]}"; do
        log "尝试 IP: $ip"
        update_from_pool
        refresh_dns
        sleep 2
        
        if test_github; then
            log "手动 IP 池修复成功: $ip"
            echo "FIXED:$ip"
            exit 0
        fi
    done
    
    # 4. 所有方案失败
    log "所有修复方案失败"
    echo "FAILED"
    exit 1
}

# git push 超时时的 API 推送方案
# 使用方式: source fix_github_hosts.sh; push_via_api "file.txt" "commit message"
push_via_api() {
    local file_path="$1"
    local commit_message="${2:-Update $file_path}"
    local repo="yangjh-dev/todolist"
    local branch="main"
    
    if [ -z "$GITHUB_TOKEN" ]; then
        echo "错误: 请设置 GITHUB_TOKEN 环境变量"
        return 1
    fi
    
    # 获取文件内容的 SHA
    local file_content=$(base64 -w 0 "$file_path")
    local current_sha=$(curl -s "https://api.github.com/repos/$repo/contents/$file_path" | grep '"sha"' | head -1 | cut -d'"' -f4)
    
    # 构建 JSON
    local json="{\"message\":\"$commit_message\",\"content\":\"$file_content\",\"branch\":\"$branch\""
    if [ -n "$current_sha" ]; then
        json="$json,\"sha\":\"$current_sha\""
    fi
    json="$json}"
    
    # 推送
    local response=$(curl -s -X PUT "https://api.github.com/repos/$repo/contents/$file_path" \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$json")
    
    if echo "$response" | grep -q '"sha"'; then
        log "API 推送成功: $file_path"
        echo "OK"
    else
        log "API 推送失败: $response"
        echo "FAILED: $response"
        return 1
    fi
}

main "$@"

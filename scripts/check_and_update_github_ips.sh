#!/bin/bash
# GitHub IP 自动检查和更新脚本
# 每周一三五日 02:00 自动执行
# 功能：检测当前 IP 是否可用，从多个来源获取最新 IP，自动更新脚本中的 IP 池

SCRIPT_PATH="/home/ubuntu/scripts/fix_github_hosts.sh"
LOG_FILE="/tmp/github_ip_check.log"
BACKUP_DIR="/tmp/github_ip_backups"

# 创建备份目录
mkdir -p "$BACKUP_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "========== 开始 GitHub IP 检查更新 =========="

# 1. 测试当前配置的 IP 是否可用
test_current_ip() {
    local current_ip=$(grep -oP 'github\.com\s+\K[\d.]+' /etc/hosts)
    if [ -z "$current_ip" ]; then
        log "当前 hosts 未配置 github.com"
        return 1
    fi
    
    log "当前 hosts IP: $current_ip"
    timeout 3 bash -c "echo >/dev/tcp/$current_ip/443" 2>/dev/null
    if [ $? -eq 0 ]; then
        log "当前 IP $current_ip 443 端口正常"
        return 0
    else
        log "当前 IP $current_ip 443 端口不通"
        return 1
    fi
}

# 2. 从多个来源获取可用 IP
get_available_ips() {
    local ips=()
    
    # 来源 1：从 hosts.gitcdn.top 公共源提取
    log "从 hosts.gitcdn.top 获取 IP..."
    local public_ips=$(curl -s --connect-timeout 10 https://hosts.gitcdn.top/hosts.txt 2>/dev/null | grep github.com | awk '{print $1}' | sort -u)
    if [ -n "$public_ips" ]; then
        while IFS= read -r ip; do
            # 验证 IP 格式
            if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                ips+=("$ip")
                log "从公共源获取: $ip"
            fi
        done <<< "$public_ips"
    fi
    
    # 来源 2：DNS 查询
    log "从 DNS 查询获取 IP..."
    local dns_ips=$(nslookup github.com 2>/dev/null | grep -A5 "Name:" | grep "Address:" | awk '{print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    if [ -n "$dns_ips" ]; then
        while IFS= read -r ip; do
            ips+=("$ip")
            log "从 DNS 获取: $ip"
        done <<< "$dns_ips"
    fi
    
    # 来源 3：dig 查询
    log "从 dig 查询获取 IP..."
    local dig_ips=$(dig github.com +short 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    if [ -n "$dig_ips" ]; then
        while IFS= read -r ip; do
            ips+=("$ip")
            log "从 dig 获取: $ip"
        done <<< "$dig_ips"
    fi
    
    # 来源 4：硬编码的备用 IP（已知可用的）
    local backup_ips=(
        "140.82.114.4"
        "140.82.114.20"
        "140.82.112.4"
        "140.82.113.4"
        "20.205.243.166"
        "20.205.243.168"
        "140.82.112.6"
        "140.82.114.3"
    )
    
    for ip in "${backup_ips[@]}"; do
        ips+=("$ip")
    done
    
    # 去重
    local unique_ips=($(echo "${ips[@]}" | tr ' ' '\n' | sort -u))
    
    echo "${unique_ips[@]}"
}

# 3. 测试 IP 可用性并排序
test_and_rank_ips() {
    local ips=("$@")
    local available_ips=()
    
    log "开始测试 ${#ips[@]} 个 IP 的可用性..."
    
    for ip in "${ips[@]}"; do
        # 测试 443 端口
        if timeout 3 bash -c "echo >/dev/tcp/$ip/443" 2>/dev/null; then
            available_ips+=("$ip")
            log "✓ $ip - 443 端口正常"
        else
            log "✗ $ip - 443 端口不通"
        fi
    done
    
    echo "${available_ips[@]}"
}

# 4. 更新脚本中的 IP 池
update_ip_pool() {
    local new_ips=("$@")
    
    if [ ${#new_ips[@]} -eq 0 ]; then
        log "没有可用的 IP，跳过更新"
        return 1
    fi
    
    # 备份原脚本
    local backup_file="$BACKUP_DIR/fix_github_hosts.sh.$(date +%Y%m%d_%H%M%S)"
    cp "$SCRIPT_PATH" "$backup_file"
    log "已备份原脚本到: $backup_file"
    
    # 构建新的 IP_POOL 数组
    local ip_pool_str=""
    for ip in "${new_ips[@]}"; do
        ip_pool_str+="    \"$ip\"\n"
    done
    
    # 使用 sed 替换 IP_POOL 数组
    # 先找到 IP_POOL=( 开始的行，然后替换到 ) 结束的行
    local temp_file=$(mktemp)
    local in_ip_pool=false
    local pool_replaced=false
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^IP_POOL=\( ]]; then
            in_ip_pool=true
            echo "IP_POOL=(" >> "$temp_file"
            echo -e "$ip_pool_str" >> "$temp_file"
            continue
        fi
        
        if $in_ip_pool; then
            if [[ "$line" =~ ^\) ]]; then
                in_ip_pool=false
                pool_replaced=true
                echo ")" >> "$temp_file"
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$SCRIPT_PATH"
    
    if $pool_replaced; then
        mv "$temp_file" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        log "✓ IP 池已更新"
        
        # 显示新 IP 池
        log "新 IP 池:"
        for ip in "${new_ips[@]}"; do
            log "  - $ip"
        done
        
        return 0
    else
        log "✗ 未找到 IP_POOL 数组，更新失败"
        rm -f "$temp_file"
        return 1
    fi
}

# 5. 主流程
main() {
    # 测试当前 IP
    if test_current_ip; then
        log "当前 IP 正常，但仍检查是否有更新..."
    fi
    
    # 获取所有可能的 IP
    local all_ips=($(get_available_ips))
    log "共获取 ${#all_ips[@]} 个候选 IP"
    
    # 测试并筛选可用 IP
    local available_ips=($(test_and_rank_ips "${all_ips[@]}"))
    log "共 ${#available_ips[@]} 个 IP 通过测试"
    
    if [ ${#available_ips[@]} -eq 0 ]; then
        log "✗ 没有找到可用的 IP"
        echo "FAILED: No available IPs"
        return 1
    fi
    
    # 取前 8 个最优先的 IP
    local top_ips=("${available_ips[@]:0:8}")
    
    # 更新脚本
    if update_ip_pool "${top_ips[@]}"; then
        log "✓ IP 池更新完成"
        
        # 如果当前 hosts 的 IP 不可用，立即修复
        if ! test_current_ip; then
            log "当前 hosts IP 不可用，执行修复..."
            /home/ubuntu/scripts/fix_github_hosts.sh
        fi
        
        echo "UPDATED: ${#top_ips[@]} IPs"
        return 0
    else
        log "✗ IP 池更新失败"
        echo "FAILED: Update failed"
        return 1
    fi
}

# 执行主流程
main

log "========== 检查更新完成 =========="

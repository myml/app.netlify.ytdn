#!/bin/bash

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
GITHUB_OUTPUT=${GITHUB_OUTPUT:-/tmp/output.txt}
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 获取 GitHub API 的 releases 信息
get_latest_release() {
    local repo=$1
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    curl -s -H "Accept: application/vnd.github.v3+json" "$api_url"
}

# 获取下载 URL 和文件名
get_download_url() {
    local repo=$1
    local file_name=$2
    curl -Is https://github.com/$1/releases/latest/download/$file_name | tr -d '\r' | grep location | awk '{print $2}'
}

# 计算文件的 SHA256 哈希值
calculate_sha256() {
    local file_path=$1
    sha256sum "$file_path" | cut -d' ' -f1
}

# 下载文件
download_file() {
    local url=$1
    local output=$2
    log "下载文件: $url"
    curl -L -o "$output" "$url"
}

# 更新 linglong.yaml 文件
update_yaml_file() {
    local repo=$1
    local new_url=$2
    local new_digest=$3
    
    log "更新文件: $file_name"
    log "新 URL: $new_url"
    log "新 Digest: $new_digest"
    set -x
    # 替换url
    sed -i "s#url:.*$repo.*#url: $new_url#" linglong.yaml
    # 替换digest
    sed -i "\#url:.*$repo#{n;s/.*/    digest: $new_digest/}" linglong.yaml
}

update_yaml_version() {
    local new_version=$1
    local t=$(date +%m%d)
    log "更新版本号: $new_version"
    sed -i "s|  version:.*|  version: $new_version.$t|" linglong.yaml
}

# 主函数
main() {
    log "开始检查更新..."
    
    # 项目配置
    declare -A projects=(
        ["ytDownloader"]="aandrew-me/ytDownloader YTDownloader_Linux.deb"
        ["yt-dlp"]="yt-dlp/yt-dlp yt-dlp_linux"
    )
    
    local has_changes=false
    
    for project in "${!projects[@]}"; do
        IFS=' ' read -r repo file_name <<< "${projects[$project]}"
        log "检查项目: $project ($repo)"
        
        # 获取最新发布信息
        local download_url=`get_download_url "$repo" "$file_name"`
        if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
            warn "未找到匹配的发布地址: $repo"
            continue
        fi
        if grep -q "$download_url" linglong.yaml; then
            log "项目 $project 已是最新版本"
            continue
        fi
        echo "下载地址: $download_url"
        
        log "最新版本: $tag_name"
        log "文件名称: $file_name"
        
        # 下载文件
        local temp_file="/tmp/$file_name"
        download_file "$download_url" "$temp_file"
        
        # 计算哈希值
        local new_digest=$(calculate_sha256 "$temp_file")
        log "计算得到的 SHA256: $new_digest"
        
        # 使用代理下载（与 linglong.yaml 中一致）
        local proxy_url="https://edgeone.gh-proxy.com/$download_url"
        # 更新 YAML 文件
        update_yaml_file "$repo" "$proxy_url" "$new_digest"
        # 清理临时文件
        rm -f "$temp_file"
        
        has_changes=true
        log "项目 $project 更新完成"
    done
    
    if [ "$has_changes" = true ]; then
        log "检测到更新，文件已修改"
        local version=$(get_latest_release "$repo" | jq -r '.name')
        update_yaml_version $version
        echo "has_changes=true" >> "$GITHUB_OUTPUT"
    else
        log "没有检测到更新"
        echo "has_changes=false" >> "$GITHUB_OUTPUT"
    fi
}

# 运行主函数
main "$@"
#!/bin/bash

# 严格模式，任何命令失败则脚本退出
set -e

# --- 解析命令行参数 ---
show_help() {
    echo "用法: $0 [选项] <视频URL>"
    echo ""
    echo "选项:"
    echo "  -hd               下载高清视频（保存为 _hd 文件）"
    echo "  -o, --output NAME 指定输出文件名前缀（不含扩展名）"
    echo "  -c, --continue    启用续传功能"
    echo "  -h, --help        显示帮助信息"
    echo ""
    echo "支持的平台:"
    echo "  - YouTube (youtube.com, youtu.be)"
    echo "  - Instagram (instagram.com)"
    echo "  - Bilibili (bilibili.com)"
    echo ""
    echo "示例:"
    echo "  $0 https://www.youtube.com/watch?v=VIDEO_ID"
    echo "  $0 -hd https://youtu.be/VIDEO_ID"
    echo "  $0 -o my_video https://youtu.be/VIDEO_ID"
    echo "  $0 -hd -o video_1751544231_7932 -c https://youtu.be/VIDEO_ID"
    echo ""
    echo "说明:"
    echo "  - 默认下载最低分辨率以加速处理"
    echo "  - 使用 -hd 下载最高分辨率（文件名带 _hd）"
    echo "  - 使用 -o 指定自定义文件名前缀"
    echo "  - 使用 -c 启用续传功能，断点续传未完成的下载"
    echo "  - 仅使用Edge浏览器的Cookie进行下载"
    echo "  - 智能重试：先尝试3次普通下载，再尝试3次代理下载"
    echo "  - 需要在Edge浏览器中登录相应网站账户"
}

# 初始化变量
VIDEO_URL=""
HD_MODE=false
CUSTOM_OUTPUT=""
ENABLE_CONTINUE=false

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -hd)
            HD_MODE=true
            shift
            ;;
        -o|--output)
            CUSTOM_OUTPUT="$2"
            shift 2
            ;;
        -c|--continue)
            ENABLE_CONTINUE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo "未知选项: $1"
            show_help
            exit 1
            ;;
        *)
            if [ -z "$VIDEO_URL" ]; then
                VIDEO_URL="$1"
            else
                echo "错误：只能指定一个视频URL"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# 检查输入参数
if [ -z "$VIDEO_URL" ]; then
    echo "错误：请提供一个视频URL作为参数。"
    show_help
    exit 1
fi

# 检查是否是本地文件
if [ -f "$VIDEO_URL" ]; then
    echo "检测到本地视频文件: $VIDEO_URL"
    
    # 生成目标文件名
    if [ -n "$CUSTOM_OUTPUT" ]; then
        if [ "$HD_MODE" = true ]; then
            TARGET_FILENAME="${CUSTOM_OUTPUT}_hd.mp4"
        else
            TARGET_FILENAME="${CUSTOM_OUTPUT}.mp4"
        fi
    else
        # 没有指定输出名称时，直接使用原文件
        TARGET_FILENAME="$VIDEO_URL"
    fi
    
    # 检查是否需要复制文件
    if [ "$TARGET_FILENAME" = "$VIDEO_URL" ]; then
        # 目标文件就是原文件，无需复制
        echo "直接使用原文件: $TARGET_FILENAME"
        FINAL_FILENAME="$TARGET_FILENAME"
    elif [ -f "$TARGET_FILENAME" ] && [ -s "$TARGET_FILENAME" ]; then
        # 目标文件已存在
        echo "目标文件已存在，直接使用: $TARGET_FILENAME"
        FINAL_FILENAME="$TARGET_FILENAME"
    else
        # 需要复制文件
        echo "复制文件到: $TARGET_FILENAME"
        if cp "$VIDEO_URL" "$TARGET_FILENAME"; then
            echo "✅ 文件复制成功"
            FINAL_FILENAME="$TARGET_FILENAME"
        else
            echo "❌ 文件复制失败"
            exit 1
        fi
    fi
    
    echo "===================================================="
    echo "✅ 视频文件准备完成！"
    echo "原文件: $VIDEO_URL"
    echo "使用文件: $FINAL_FILENAME"
    echo "文件大小: $(ls -lh "$FINAL_FILENAME" | awk '{print $5}')"
    echo ""
    echo "📝 下一步建议："
    echo "1. 运行第一阶段处理: ./process_video_part1.sh \"$FINAL_FILENAME\""
    echo "2. 手动翻译生成的字幕文件"
    echo "3. 运行第二阶段处理: ./process_video_part2_plus.sh \"$FINAL_FILENAME\""
    echo "===================================================="
    
    # 输出文件信息供其他脚本使用
    echo "DOWNLOADED_FILE:$FINAL_FILENAME"
    exit 0
fi

# 生成唯一文件名（使用自定义名称或时间戳生成）
if [ -n "$CUSTOM_OUTPUT" ]; then
    # 使用自定义文件名
    if [ "$HD_MODE" = true ]; then
        TARGET_FILENAME="${CUSTOM_OUTPUT}_hd"
    else
        TARGET_FILENAME="$CUSTOM_OUTPUT"
    fi
else
    # 生成时间戳文件名
    if [ "$HD_MODE" = true ]; then
        TARGET_FILENAME="video_$(date +%s)_$(jot -r 1 1000 9999)_hd"
    else
        TARGET_FILENAME="video_$(date +%s)_$(jot -r 1 1000 9999)"
    fi
fi

# 检查yt-dlp是否已安装
if ! command -v yt-dlp &> /dev/null; then
    echo "错误：yt-dlp 未安装。请先安装 yt-dlp："
    echo "  pip install yt-dlp"
    echo "  或者使用 brew install yt-dlp"
    exit 1
fi

echo "开始下载视频: $VIDEO_URL"
if [ -n "$CUSTOM_OUTPUT" ]; then
    echo "使用自定义文件名: $TARGET_FILENAME"
fi
if [ "$ENABLE_CONTINUE" = true ]; then
    echo "续传功能: 启用"
fi
echo "使用Edge浏览器Cookie进行认证..."
echo "智能重试策略：普通下载3次 → 代理下载3次"
echo "=================================================="

# 检查目标文件是否已存在（避免重复下载）
EXPECTED_FILES=("${TARGET_FILENAME}.mp4" "${TARGET_FILENAME}.mkv" "${TARGET_FILENAME}.webm")
EXISTING_FILE=""

for expected_file in "${EXPECTED_FILES[@]}"; do
    if [ -f "$expected_file" ] && [ -s "$expected_file" ]; then
        EXISTING_FILE="$expected_file"
        break
    fi
done

if [ -n "$EXISTING_FILE" ]; then
    echo "✅ 目标文件已存在，跳过下载: $EXISTING_FILE"
    echo "===================================================="
    echo "✅ 使用已存在的视频文件！"
    echo "视频文件: $EXISTING_FILE"
    echo "文件大小: $(ls -lh "$EXISTING_FILE" | awk '{print $5}')"
    echo ""
    echo "📝 下一步建议："
    echo "1. 运行第一阶段处理: ./process_video_part1.sh \"$EXISTING_FILE\""
    echo "2. 手动翻译生成的字幕文件"
    echo "3. 运行第二阶段处理: ./process_video_part2_plus.sh \"$EXISTING_FILE\""
    echo "===================================================="
    
    # 输出文件信息供其他脚本使用
    echo "DOWNLOADED_FILE:$EXISTING_FILE"
    exit 0
fi

# 确定下载格式
if [ "$HD_MODE" = true ]; then
    # 尝试下载最佳质量，优先选择高分辨率
    DOWNLOAD_FORMAT="bestvideo[height>=720]+bestaudio/best[height>=720]/best"
else
    # 下载360p或最低质量
    DOWNLOAD_FORMAT="18/worst"
fi

echo "正在下载视频（格式: $DOWNLOAD_FORMAT）..."

# 设置续传参数
CONTINUE_ARG=""
if [ "$ENABLE_CONTINUE" = true ]; then
    CONTINUE_ARG="--continue"
    echo "🔄 启用续传功能"
fi

# 尝试下载函数（使用Edge Cookie）
download_with_edge() {
    local attempt=$1
    local max_attempts=$2
    local use_proxy=${3:-false}
    
    if [ "$use_proxy" = true ]; then
        echo "尝试 $attempt/$max_attempts: 使用Edge浏览器Cookie + 代理下载..."
    else
        echo "尝试 $attempt/$max_attempts: 使用Edge浏览器Cookie下载..."
    fi
    
    # 记录下载前的文件列表
    local before_files=$(find . -maxdepth 1 \( -name "*.mp4" -o -name "*.mkv" -o -name "*.webm" -o -name "*.mov" \) -type f | sort)
    
    # 准备代理参数
    local proxy_args=""
    if [ "$use_proxy" = true ]; then
        # 使用系统代理或常见代理设置
        # 首先尝试检测系统代理设置
        if [ -n "$HTTP_PROXY" ] || [ -n "$http_proxy" ]; then
            proxy_args="--proxy ${HTTP_PROXY:-$http_proxy}"
        elif [ -n "$HTTPS_PROXY" ] || [ -n "$https_proxy" ]; then
            proxy_args="--proxy ${HTTPS_PROXY:-$https_proxy}"
        else
            # 使用常见的本地代理端口
            proxy_args="--proxy http://127.0.0.1:1087"
        fi
        echo "使用代理: $proxy_args"
    else
        # 明确禁用代理
        proxy_args="--proxy ''"
    fi
    
    # 执行下载（添加超时和详细错误信息）
    # 使用macOS兼容的超时机制
    if [ "$use_proxy" = true ]; then
        yt-dlp \
            --cookies-from-browser edge \
            --format "$DOWNLOAD_FORMAT" \
            --output "${TARGET_FILENAME}.%(ext)s" \
            --no-playlist \
            --embed-metadata \
            --no-post-overwrites \
            --no-mtime \
            $CONTINUE_ARG \
            $proxy_args \
            --socket-timeout 30 \
            --retries 1 \
            --user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
            --no-check-certificate \
            --prefer-insecure \
            --extractor-args "youtube:skip=dash,hls" \
            --legacy-server-connect \
            "$VIDEO_URL" &
    else
        yt-dlp \
            --cookies-from-browser edge \
            --format "$DOWNLOAD_FORMAT" \
            --output "${TARGET_FILENAME}.%(ext)s" \
            --no-playlist \
            --embed-metadata \
            --no-post-overwrites \
            --no-mtime \
            $CONTINUE_ARG \
            --proxy "" \
            --socket-timeout 30 \
            --retries 1 \
            --user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
            --no-check-certificate \
            --prefer-insecure \
            --extractor-args "youtube:skip=dash,hls" \
            --legacy-server-connect \
            "$VIDEO_URL" &
    fi
    
    # 获取yt-dlp进程ID
    local ytdlp_pid=$!
    
    # 等待最多300秒（5分钟）
    local timeout_seconds=300
    local elapsed=0
    
    while kill -0 $ytdlp_pid 2>/dev/null && [ $elapsed -lt $timeout_seconds ]; do
        sleep 1
        elapsed=$((elapsed + 1))
        # 每30秒显示一次进度
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "下载进行中... 已用时 ${elapsed}秒"
        fi
    done
    
    # 检查进程是否仍在运行
    if kill -0 $ytdlp_pid 2>/dev/null; then
        echo "⏰ 下载超时，终止进程..."
        kill -TERM $ytdlp_pid 2>/dev/null || true
        sleep 2
        kill -KILL $ytdlp_pid 2>/dev/null || true
        return 1
    fi
    
    # 等待进程结束并获取退出状态
    wait $ytdlp_pid
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        
        # 记录下载后的文件列表
        local after_files=$(find . -maxdepth 1 \( -name "*.mp4" -o -name "*.mkv" -o -name "*.webm" -o -name "*.mov" \) -type f | sort)
        
        # 查找新下载的文件
        local new_files=$(comm -13 <(echo "$before_files") <(echo "$after_files"))
        
        # 优先查找目标文件名模式
        for expected_file in "${EXPECTED_FILES[@]}"; do
            if [ -f "$expected_file" ] && [ -s "$expected_file" ]; then
                DOWNLOADED_FILE="$expected_file"
                echo "✅ 下载成功: $DOWNLOADED_FILE"
                return 0
            fi
        done
        
        # 如果没有找到预期文件名，但有新文件，使用新文件
        if [ -n "$new_files" ]; then
            DOWNLOADED_FILE=$(echo "$new_files" | head -1)
            if [ -f "$DOWNLOADED_FILE" ] && [ -s "$DOWNLOADED_FILE" ]; then
                echo "✅ 下载成功（非预期文件名）: $DOWNLOADED_FILE"
                return 0
            fi
        fi
        
        echo "❌ 下载命令成功但未找到有效文件"
        return 1
    else
        echo "❌ 下载命令失败（尝试 $attempt/$max_attempts）"
        return 1
    fi
}

# 主下载逻辑（先尝试3次普通下载，再尝试3次代理下载）
DOWNLOADED_FILE=""
echo "第一阶段：尝试普通下载（3次）..."

# 第一阶段：普通下载（3次尝试）
success=false
for attempt in {1..3}; do
    if download_with_edge $attempt 3 false; then
        success=true
        break
    fi
    
    if [ $attempt -lt 3 ]; then
        echo "等待5秒后重试..."
        sleep 5
    fi
done

# 第二阶段：如果普通下载失败，尝试代理下载（3次尝试）
if [ "$success" = false ]; then
    echo ""
    echo "=========================================="
    echo "第二阶段：普通下载失败，尝试代理下载（3次）..."
    echo "=========================================="
    
    for attempt in {1..3}; do
        if download_with_edge $attempt 3 true; then
            success=true
            break
        fi
        
        if [ $attempt -lt 3 ]; then
            echo "等待5秒后重试..."
            sleep 5
        fi
    done
fi

# 检查下载结果
if [ -n "$DOWNLOADED_FILE" ] && [ -f "$DOWNLOADED_FILE" ] && [ -s "$DOWNLOADED_FILE" ]; then
    echo "=================================================="
    echo "✅ 视频下载成功！"
    echo "视频文件: $DOWNLOADED_FILE"
    echo "视频大小: $(ls -lh "$DOWNLOADED_FILE" | awk '{print $5}')"
    echo ""
    echo "📝 下一步建议："
    echo "1. 运行第一阶段处理: ./process_video_part1.sh \"$DOWNLOADED_FILE\""
    echo "2. 手动翻译生成的字幕文件"
    echo "3. 运行第二阶段处理: ./process_video_part2_plus.sh \"$DOWNLOADED_FILE\""
    echo "=================================================="
    
    # 输出文件信息供其他脚本使用
    echo "DOWNLOADED_FILE:$DOWNLOADED_FILE"
else
    echo "=================================================="
    echo "❌ 下载失败！"
    echo ""
    echo "已尝试6次下载，均失败："
    echo "- 普通下载：3次尝试"
    echo "- 代理下载：3次尝试"
    echo ""
    echo "可能的原因："
    echo "1. Edge浏览器Cookie可能过期或无效"
    echo "2. 需要在Edge浏览器中重新登录相应网站"
    echo "3. 网络连接问题或需要不同的代理设置"
    echo "4. 视频URL可能无效或需要特殊权限"
    echo ""
    echo "📋 解决方案："
    echo "1. 在Edge浏览器中访问并登录 $VIDEO_URL 所在的网站"
    echo "2. 确保视频可以正常播放"
    echo "3. 检查代理设置（如使用代理，请设置环境变量 HTTP_PROXY 或 http_proxy）"
    echo "4. 重新运行此脚本"
    echo ""
    echo "或者手动下载视频后运行："
    echo "  ./process_video_part1.sh \"你的视频文件.mp4\""
    echo "=================================================="
    exit 1
fi
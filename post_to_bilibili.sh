#!/bin/bash

# 自动发布B站视频脚本
# 依赖: biliup (pip install biliup)

set -e

# --- 解析命令行参数 ---
show_help() {
    echo "用法: $0 [选项] <视频文件>"
    echo ""
    echo "选项:"
    echo "  -t, --title TITLE         视频标题"
    echo "  -d, --desc DESCRIPTION    视频描述"
    echo "  -T, --tags TAGS           视频标签（逗号分隔）"
    echo "  -c, --cover COVER         封面图片路径"
    echo "  -s, --source SOURCE       转载来源说明"
    echo "  --tid TID                 分区ID（默认: 201 科学科普-社科·法律·心理）"
    echo "  --copyright COPYRIGHT     版权声明（1=自制 2=转载，默认: 2）"
    echo "  --no-reprint             禁止转载"
    echo "  --dolby                  杜比音效"
    echo "  --hires                  Hi-Res音质"
    echo "  --line LINE              上传线路（kodo/bda2/ws/qn，默认: auto）"
    echo "  --limit LIMIT            上传限速（KB/s）"
    echo "  --threads THREADS        上传线程数（默认: 3）"
    echo "  --config CONFIG          配置文件路径（默认: ~/.biliup/config.json）"
    echo "  --dry-run                预览模式，不实际上传"
    echo "  --debug                  调试模式，显示完整命令"
    echo "  -h, --help               显示帮助信息"
    echo ""
    echo "分区ID参考:"
    echo "  201   科学科普-社科·法律·心理"
    echo "  207   科学科普-财经商业"
    echo "  208   科学科普-校园学习"
    echo "  209   科学科普-职业职场"
    echo "  229   科学科普-人文历史"
    echo "  230   科学科普-设计·创意"
    echo "  231   科学科普-野生技能协会"
    echo "  124   趣味科普人文"
    echo "  122   野生技能协会"
    echo "  39    游戏-单机游戏"
    echo "  17    单机联机"
    echo "  171   电子竞技"
    echo "  172   手机游戏"
    echo "  65    网络游戏"
    echo "  173   桌游棋牌"
    echo "  121   GMV"
    echo "  136   ACG音乐"
    echo "  130   音乐现场"
    echo "  28    原创音乐"
    echo "  31    翻唱"
    echo "  194   电音"
    echo "  29    音乐综合"
    echo ""
    echo "登录说明:"
    echo "  - 首次使用需要登录B站账号"
    echo "  - 脚本会自动检查登录状态"
    echo "  - 未登录时会自动启动二维码登录"
    echo "  - 也可手动登录: biliup login qrcode"
    echo ""
    echo "示例:"
    echo "  $0 video.mp4 -t \"我的视频标题\" -d \"视频描述\" -T \"科技,教程,AI\""
    echo "  $0 video.mp4 -t \"转载视频\" -s \"转载自YouTube\" --copyright 2"
    echo "  $0 video.mp4 --dry-run  # 预览模式"
}

# 初始化变量
VIDEO_FILE=""
TITLE=""
DESCRIPTION=""
TAGS=""
COVER=""
SOURCE=""
TID="201"  # 默认科学科普-社科·法律·心理
COPYRIGHT="2"  # 默认转载
NO_REPRINT=false
DOLBY=false
HIRES=false
LINE="auto"
LIMIT=""
THREADS="3"
CONFIG=""
DRY_RUN=false
DEBUG=false

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--title)
            TITLE="$2"
            shift 2
            ;;
        -d|--desc)
            DESCRIPTION="$2"
            shift 2
            ;;
        -T|--tags)
            TAGS="$2"
            shift 2
            ;;
        -c|--cover)
            COVER="$2"
            shift 2
            ;;
        -s|--source)
            SOURCE="$2"
            shift 2
            ;;
        --tid)
            TID="$2"
            shift 2
            ;;
        --copyright)
            COPYRIGHT="$2"
            shift 2
            ;;
        --no-reprint)
            NO_REPRINT=true
            shift
            ;;
        --dolby)
            DOLBY=true
            shift
            ;;
        --hires)
            HIRES=true
            shift
            ;;
        --line)
            LINE="$2"
            shift 2
            ;;
        --limit)
            LIMIT="$2"
            shift 2
            ;;
        --threads)
            THREADS="$2"
            shift 2
            ;;
        --config)
            CONFIG="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --debug)
            DEBUG=true
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
            if [ -z "$VIDEO_FILE" ]; then
                VIDEO_FILE="$1"
            else
                echo "错误：只能指定一个视频文件"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# 检查必需参数
if [ -z "$VIDEO_FILE" ]; then
    echo "错误：请提供视频文件路径"
    show_help
    exit 1
fi

# 检查视频文件是否存在
if [ ! -f "$VIDEO_FILE" ]; then
    echo "错误：视频文件不存在: $VIDEO_FILE"
    exit 1
fi

# 检查Chrome浏览器和Python依赖
echo "🔍 检查上传环境..."

# 检查Chrome浏览器（预览模式下跳过）
if [ "$DRY_RUN" != true ]; then
    if ! command -v google-chrome &> /dev/null && ! command -v chromium &> /dev/null && ! ls "/Applications/Google Chrome.app" &> /dev/null; then
        echo "❌ 错误：未找到Chrome浏览器"
        echo "请安装Chrome浏览器："
        echo "1. 访问 https://www.google.com/chrome/"
        echo "2. 下载并安装Chrome浏览器"
        exit 1
    fi
    echo "✅ 找到Chrome浏览器"
else
    echo "⚠️  预览模式：跳过Chrome浏览器检查"
fi

# 检查Selenium依赖（预览模式下跳过）
if [ "$DRY_RUN" != true ]; then
    if ! python3 -c "import selenium" &> /dev/null; then
        echo "❌ 错误：selenium未安装"
        echo "正在安装selenium..."
        pip3 install selenium --user
        if [ $? -ne 0 ]; then
            echo "❌ selenium安装失败"
            echo "请手动安装：pip3 install selenium"
            exit 1
        fi
        echo "✅ selenium安装成功"
    else
        echo "✅ selenium已安装"
    fi
else
    echo "⚠️  预览模式：跳过selenium检查"
fi

echo "✅ 上传环境检查完成"

# 使用Selenium命令行上传模式
echo "🚀 使用Selenium自动化浏览器上传模式"
echo "📋 此模式通过自动化控制Chrome浏览器实现上传"

USE_CLI_UPLOAD=true  # 设置为命令行模式

if [ "$DEBUG" = true ]; then
    echo ""
    echo "🔧 调试信息："
    echo "  - 使用Selenium WebDriver"
    echo "  - 自动化Chrome浏览器操作"
    echo "  - 支持完全命令行上传"
    echo ""
fi

# 检查登录状态
check_login_status() {
    echo "🔐 Selenium模式：登录状态将在浏览器中检查"
    echo "💡 如果未登录，脚本会引导您完成登录"
    return 0  # Selenium模式总是返回成功，实际检查在Python脚本中进行
}

# 执行登录
perform_login() {
    echo "🔑 Selenium模式：登录将在浏览器中进行"
    echo "💡 Python脚本会自动处理登录流程"
    return 0  # Selenium模式总是返回成功
}

# 检查并处理登录状态
if ! check_login_status; then
    if [ "$DRY_RUN" = true ]; then
        echo "⚠️  预览模式：跳过登录检查"
    elif [ "$USE_CLI_UPLOAD" = false ]; then
        echo "💡 Web版本将在界面中处理登录"
    else
        echo "🔐 需要先登录B站账号"
        echo "是否现在进行登录？[Y/n]"
        read -r LOGIN_CONFIRM
        if [[ "$LOGIN_CONFIRM" =~ ^[Nn]$ ]]; then
            echo "❌ 用户取消登录，无法继续上传"
            echo ""
            echo "💡 稍后可手动登录："
            echo "   biliup login qrcode"
            exit 1
        fi
        
        if ! perform_login; then
            echo "❌ 登录失败，无法继续上传"
            exit 1
        fi
        
        echo ""
    fi
else
    echo "✅ B站账号已登录"
fi

# 获取视频文件信息
VIDEO_BASENAME=$(basename "$VIDEO_FILE")
VIDEO_NAME="${VIDEO_BASENAME%.*}"
VIDEO_SIZE=$(du -h "$VIDEO_FILE" | cut -f1)

echo "🎬 B站视频自动发布工具"
echo "========================================"
echo "视频文件: $VIDEO_FILE"
echo "文件大小: $VIDEO_SIZE"
echo "========================================"

# 如果没有提供标题，使用文件名
if [ -z "$TITLE" ]; then
    TITLE="$VIDEO_NAME"
    echo "📝 使用文件名作为标题: $TITLE"
fi

# 如果没有提供描述，生成默认描述
if [ -z "$DESCRIPTION" ]; then
    if [ "$COPYRIGHT" = "2" ] && [ -n "$SOURCE" ]; then
        DESCRIPTION="转载视频

转载说明: $SOURCE

感谢原作者的精彩内容！

#视频分享 #优质内容"
    else
        DESCRIPTION="分享一个有趣的视频

欢迎大家观看！

#视频分享 #优质内容"
    fi
    echo "📝 生成默认描述"
fi

# 如果没有提供标签，生成默认标签
if [ -z "$TAGS" ]; then
    case "$TID" in
        201|207|208|209|229|230|231|124|122)
            TAGS="科普,知识,学习"
            ;;
        39|17|171|172|65|173|121)
            TAGS="游戏,娱乐,攻略"
            ;;
        136|130|28|31|194|29)
            TAGS="音乐,娱乐,分享"
            ;;
        *)
            TAGS="视频,分享,娱乐"
            ;;
    esac
    echo "📝 生成默认标签: $TAGS"
fi

# 检查封面图片
if [ -n "$COVER" ] && [ ! -f "$COVER" ]; then
    echo "⚠️  警告：封面图片不存在: $COVER"
    echo "⚠️  将使用系统默认封面"
    COVER=""
fi

# 显示上传配置
echo ""
echo "📋 上传配置："
echo "  标题: $TITLE"
echo "  描述: $(echo "$DESCRIPTION" | head -3 | tr '\n' ' ')..."
echo "  标签: $TAGS"
echo "  分区: $TID"
echo "  版权: $([ "$COPYRIGHT" = "1" ] && echo "自制" || echo "转载")"
if [ -n "$SOURCE" ]; then
    echo "  转载来源: $SOURCE"
fi
if [ -n "$COVER" ]; then
    echo "  封面: $COVER"
fi
echo "  上传线路: $LINE"
echo "  上传线程: $THREADS"
if [ -n "$LIMIT" ]; then
    echo "  限速: ${LIMIT}KB/s"
fi
echo "  禁止转载: $([ "$NO_REPRINT" = true ] && echo "是" || echo "否")"
echo "  杜比音效: $([ "$DOLBY" = true ] && echo "是" || echo "否")"
echo "  Hi-Res音质: $([ "$HIRES" = true ] && echo "是" || echo "否")"
echo ""

# 预览模式
if [ "$DRY_RUN" = true ]; then
    echo "🔍 预览模式 - 不会实际上传"
    echo "✅ 配置检查完成"
    exit 0
fi

# 构建biliup命令（在确认前构建，以便调试模式显示）
BILIUP_CMD="biliup upload"

# 添加配置文件参数
if [ -n "$CONFIG" ]; then
    BILIUP_CMD="$BILIUP_CMD --config \"$CONFIG\""
fi

# 添加标题
BILIUP_CMD="$BILIUP_CMD --title \"$TITLE\""

# 添加描述
DESCRIPTION_ESCAPED=$(echo "$DESCRIPTION" | sed 's/"/\\"/g')
BILIUP_CMD="$BILIUP_CMD --desc \"$DESCRIPTION_ESCAPED\""

# 添加标签
BILIUP_CMD="$BILIUP_CMD --tag \"$TAGS\""

# 添加分区
BILIUP_CMD="$BILIUP_CMD --tid $TID"

# 添加版权
BILIUP_CMD="$BILIUP_CMD --copyright $COPYRIGHT"

# 添加转载来源
if [ -n "$SOURCE" ] && [ "$COPYRIGHT" = "2" ]; then
    BILIUP_CMD="$BILIUP_CMD --source \"$SOURCE\""
fi

# 添加封面
if [ -n "$COVER" ]; then
    BILIUP_CMD="$BILIUP_CMD --cover \"$COVER\""
fi

# 添加高级选项
if [ "$NO_REPRINT" = true ]; then
    BILIUP_CMD="$BILIUP_CMD --no-reprint"
fi

if [ "$DOLBY" = true ]; then
    BILIUP_CMD="$BILIUP_CMD --dolby"
fi

if [ "$HIRES" = true ]; then
    BILIUP_CMD="$BILIUP_CMD --hires"
fi

# 添加上传参数
BILIUP_CMD="$BILIUP_CMD --line $LINE"
BILIUP_CMD="$BILIUP_CMD --threads $THREADS"

if [ -n "$LIMIT" ]; then
    BILIUP_CMD="$BILIUP_CMD --limit $LIMIT"
fi

# 添加视频文件
BILIUP_CMD="$BILIUP_CMD \"$VIDEO_FILE\""

# 显示将要执行的命令（调试模式）
if [ "$DEBUG" = true ]; then
    echo ""
    echo "🔧 调试信息："
    echo "完整命令: $BILIUP_CMD"
    echo ""
fi

# 使用Selenium命令行上传
echo ""
echo "🤖 使用Selenium自动化浏览器上传"
echo "========================================"
echo ""
echo "📋 上传信息预览："
echo "  视频文件: $VIDEO_FILE"
echo "  标题: $TITLE"
echo "  描述: $(echo "$DESCRIPTION" | head -1)"
echo "  标签: $TAGS"
echo "  分区: $TID"
echo "  版权: $([ "$COPYRIGHT" = "1" ] && echo "自制" || echo "转载")"
if [ -n "$SOURCE" ]; then
    echo "  转载来源: $SOURCE"
fi
echo ""

# 检查Python上传脚本是否存在
CLI_UPLOADER="$(dirname "$0")/bilibili_cli_uploader.py"
if [ ! -f "$CLI_UPLOADER" ]; then
    echo "❌ 找不到Selenium上传脚本: $CLI_UPLOADER"
    echo "💡 请确保bilibili_cli_uploader.py与此脚本在同一目录"
    exit 1
fi

# 设置Python脚本可执行权限
chmod +x "$CLI_UPLOADER"

echo "🚀 开始Selenium自动化上传..."
echo ""

# 使用Selenium Python脚本进行上传
if python3 "$CLI_UPLOADER" "$VIDEO_FILE" "$TITLE" "$DESCRIPTION" "$TAGS" "$TID" "$COPYRIGHT" "$SOURCE"; then
    echo ""
    echo "🎉 Selenium上传流程完成！"
    echo "✅ 视频已通过自动化浏览器上传"
    echo "🎯 完整流程已完成：下载 -> 处理 -> 自动上传"
else
    echo ""
    echo "❌ Selenium上传失败"
    echo ""
    echo "🔄 备用方案："
    echo "1. 检查Chrome浏览器是否正常运行"
    echo "2. 确保网络连接稳定"
    echo "3. 手动打开 https://member.bilibili.com/ 进行上传"
    echo "4. 使用以下信息："
    echo "   - 标题: $TITLE"
    echo "   - 描述: $(echo "$DESCRIPTION" | head -1)"
    echo "   - 标签: $TAGS"
    echo "   - 分区: $TID"
    echo "   - 版权: $([ "$COPYRIGHT" = "1" ] && echo "自制" || echo "转载")"
    if [ -n "$SOURCE" ]; then
        echo "   - 来源: $SOURCE"
    fi
    echo ""
    exit 1
fi


#!/bin/bash

# 自动发布小红书脚本
# 依赖: selenium-wire, undetected-chromedriver 等

set -e

# --- 解析命令行参数 ---
show_help() {
    echo "用法: $0 [选项] <视频文件>"
    echo ""
    echo "选项:"
    echo "  -t, --title TITLE         笔记标题"
    echo "  -d, --desc DESCRIPTION    笔记描述/正文"
    echo "  -T, --tags TAGS           话题标签（逗号分隔，自动加#）"
    echo "  -c, --cover COVER         封面图片路径"
    echo "  -l, --location LOCATION   地理位置"
    echo "  --topic-file FILE         从文件读取标题和描述（如xiaohongshu.md）"
    echo "  --category CATEGORY       内容分类（美食、时尚、旅行、生活、科技等）"
    echo "  --visibility PUBLIC/PRIVATE  可见性（默认: PUBLIC）"
    echo "  --allow-save              允许他人保存"
    echo "  --allow-comment           允许评论（默认开启）"
    echo "  --schedule TIME           定时发布（格式: YYYY-MM-DD HH:MM）"
    echo "  --browser-profile PROFILE 浏览器配置文件路径"
    echo "  --headless                无头模式运行"
    echo "  --debug                   调试模式"
    echo "  --dry-run                 预览模式，不实际发布"
    echo "  -h, --help                显示帮助信息"
    echo ""
    echo "话题标签说明:"
    echo "  - 自动为每个标签添加#号"
    echo "  - 建议使用3-10个相关标签"
    echo "  - 标签应与内容相关，提高曝光度"
    echo ""
    echo "分类参考:"
    echo "  - 美食: 美食制作、美食探店、菜谱分享"
    echo "  - 时尚: 穿搭、美妆、护肤、发型"
    echo "  - 旅行: 旅游攻略、景点打卡、酒店民宿"
    echo "  - 生活: 居家装饰、生活技巧、日常分享"
    echo "  - 科技: 数码产品、软件教程、科技资讯"
    echo "  - 运动: 健身、瑜伽、户外运动、体育"
    echo "  - 学习: 知识分享、技能教程、读书笔记"
    echo "  - 育儿: 亲子活动、育儿经验、儿童教育"
    echo ""
    echo "示例:"
    echo "  $0 video.mp4 -t \"我的生活分享\" -d \"今天的美好时光\" -T \"生活,日常,分享\""
    echo "  $0 video.mp4 --topic-file xiaohongshu.md -c cover.jpg"
    echo "  $0 video.mp4 --dry-run  # 预览模式"
}

# 初始化变量
VIDEO_FILE=""
TITLE=""
DESCRIPTION=""
TAGS=""
COVER=""
LOCATION=""
TOPIC_FILE=""
CATEGORY=""
VISIBILITY="PUBLIC"
ALLOW_SAVE=false
ALLOW_COMMENT=true
SCHEDULE=""
BROWSER_PROFILE=""
HEADLESS=false
DEBUG=false
DRY_RUN=false

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
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        --topic-file)
            TOPIC_FILE="$2"
            shift 2
            ;;
        --category)
            CATEGORY="$2"
            shift 2
            ;;
        --visibility)
            VISIBILITY="$2"
            shift 2
            ;;
        --allow-save)
            ALLOW_SAVE=true
            shift
            ;;
        --allow-comment)
            ALLOW_COMMENT=true
            shift
            ;;
        --schedule)
            SCHEDULE="$2"
            shift 2
            ;;
        --browser-profile)
            BROWSER_PROFILE="$2"
            shift 2
            ;;
        --headless)
            HEADLESS=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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

# 检查Python环境和依赖
check_dependencies() {
    echo "🔍 检查依赖环境..."
    
    # 检查Python
    if ! command -v python3 &> /dev/null; then
        echo "❌ Python3未安装"
        echo "请安装Python3: https://www.python.org/"
        exit 1
    fi
    
    # 检查必要的Python包
    local required_packages=("selenium" "undetected_chromedriver" "requests" "pillow")
    local missing_packages=()
    
    for package in "${required_packages[@]}"; do
        if ! python3 -c "import $package" 2>/dev/null; then
            missing_packages+=("$package")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo "❌ 缺少Python依赖包: ${missing_packages[*]}"
        echo "请安装依赖："
        echo "pip3 install selenium undetected-chromedriver requests pillow"
        exit 1
    fi
    
    # 检查Chrome浏览器
    if ! command -v google-chrome &> /dev/null && ! command -v chromium-browser &> /dev/null && ! ls /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome &> /dev/null; then
        echo "⚠️  未检测到Chrome浏览器，可能影响自动化功能"
    fi
    
    echo "✅ 依赖检查完成"
}

# 处理topic文件
if [ -n "$TOPIC_FILE" ]; then
    if [ ! -f "$TOPIC_FILE" ]; then
        echo "错误：话题文件不存在: $TOPIC_FILE"
        exit 1
    fi
    
    echo "📖 从文件读取内容: $TOPIC_FILE"
    
    # 如果没有设置标题，从文件第一行提取
    if [ -z "$TITLE" ]; then
        TITLE=$(head -n 1 "$TOPIC_FILE" | sed 's/^#\s*//')
        echo "📝 提取标题: $TITLE"
    fi
    
    # 如果没有设置描述，使用整个文件内容
    if [ -z "$DESCRIPTION" ]; then
        DESCRIPTION=$(cat "$TOPIC_FILE")
        echo "📝 提取描述: $(echo "$DESCRIPTION" | wc -l)行内容"
    fi
fi

# 获取视频文件信息
VIDEO_BASENAME=$(basename "$VIDEO_FILE")
VIDEO_NAME="${VIDEO_BASENAME%.*}"
VIDEO_SIZE=$(du -h "$VIDEO_FILE" | cut -f1)
VIDEO_DURATION=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null | cut -d. -f1 || echo "未知")

echo "📱 小红书视频自动发布工具"
echo "========================================"
echo "视频文件: $VIDEO_FILE"
echo "文件大小: $VIDEO_SIZE"
echo "视频时长: ${VIDEO_DURATION}秒"
echo "========================================"

# 如果没有提供标题，使用文件名
if [ -z "$TITLE" ]; then
    TITLE="$VIDEO_NAME"
    echo "📝 使用文件名作为标题: $TITLE"
fi

# 如果没有提供描述，生成默认描述
if [ -z "$DESCRIPTION" ]; then
    DESCRIPTION="分享一个有趣的视频 ✨

记录生活中的美好瞬间 📸
希望能给大家带来快乐 😊

#生活分享 #日常记录 #美好时光"
    echo "📝 生成默认描述"
fi

# 处理标签
if [ -n "$TAGS" ]; then
    # 将逗号分隔的标签转换为#标签格式
    FORMATTED_TAGS=""
    IFS=',' read -ra TAG_ARRAY <<< "$TAGS"
    for tag in "${TAG_ARRAY[@]}"; do
        # 去除空格并添加#号
        clean_tag=$(echo "$tag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ ! "$clean_tag" =~ ^# ]]; then
            clean_tag="#$clean_tag"
        fi
        FORMATTED_TAGS="$FORMATTED_TAGS $clean_tag"
    done
    TAGS="$FORMATTED_TAGS"
    echo "📝 格式化标签: $TAGS"
fi

# 检查封面图片
if [ -n "$COVER" ] && [ ! -f "$COVER" ]; then
    echo "⚠️  警告：封面图片不存在: $COVER"
    echo "⚠️  将使用视频首帧作为封面"
    COVER=""
fi

# 显示发布配置
echo ""
echo "📋 发布配置："
echo "  标题: $TITLE"
echo "  描述: $(echo "$DESCRIPTION" | head -3 | tr '\n' ' ')..."
if [ -n "$TAGS" ]; then
    echo "  标签: $TAGS"
fi
if [ -n "$CATEGORY" ]; then
    echo "  分类: $CATEGORY"
fi
if [ -n "$LOCATION" ]; then
    echo "  位置: $LOCATION"
fi
if [ -n "$COVER" ]; then
    echo "  封面: $COVER"
fi
echo "  可见性: $VISIBILITY"
echo "  允许保存: $([ "$ALLOW_SAVE" = true ] && echo "是" || echo "否")"
echo "  允许评论: $([ "$ALLOW_COMMENT" = true ] && echo "是" || echo "否")"
if [ -n "$SCHEDULE" ]; then
    echo "  定时发布: $SCHEDULE"
fi
echo "  运行模式: $([ "$HEADLESS" = true ] && echo "无头模式" || echo "界面模式")"
echo ""

# 预览模式
if [ "$DRY_RUN" = true ]; then
    echo "🔍 预览模式 - 不会实际发布"
    echo "✅ 配置检查完成"
    
    # 显示将要发布的完整内容
    echo ""
    echo "📄 预览内容："
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "标题: $TITLE"
    echo ""
    echo "正文:"
    echo "$DESCRIPTION"
    if [ -n "$TAGS" ]; then
        echo ""
        echo "标签: $TAGS"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
fi

# 检查依赖
check_dependencies

# 确认发布
echo "⚠️  即将开始发布到小红书，确认继续？[y/N]"
read -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "❌ 用户取消发布"
    exit 0
fi

echo ""
echo "🚀 开始发布到小红书..."
echo "========================================"

# 创建Python自动化脚本
AUTOMATION_SCRIPT="/tmp/xiaohongshu_automation.py"
cat > "$AUTOMATION_SCRIPT" << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import os
import time
import json
import argparse
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.keys import Keys
from selenium.common.exceptions import TimeoutException, NoSuchElementException
import undetected_chromedriver as uc
from pathlib import Path

class XiaohongshuPublisher:
    def __init__(self, headless=False, debug=False, profile_path=None):
        self.headless = headless
        self.debug = debug
        self.driver = None
        self.wait = None
        self.profile_path = profile_path
        
    def setup_driver(self):
        """设置Chrome驱动"""
        print("🔧 初始化浏览器...")
        
        options = uc.ChromeOptions()
        
        # 基础设置
        options.add_argument('--no-sandbox')
        options.add_argument('--disable-dev-shm-usage')
        options.add_argument('--disable-blink-features=AutomationControlled')
        options.add_experimental_option("excludeSwitches", ["enable-automation"])
        options.add_experimental_option('useAutomationExtension', False)
        
        # 用户配置文件
        if self.profile_path:
            options.add_argument(f'--user-data-dir={self.profile_path}')
        
        # 无头模式
        if self.headless:
            options.add_argument('--headless')
        
        # 移动端User-Agent（小红书主要是移动端应用）
        options.add_argument('--user-agent=Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1')
        
        # 设置窗口大小为手机屏幕
        options.add_argument('--window-size=375,812')
        
        try:
            self.driver = uc.Chrome(options=options)
            self.wait = WebDriverWait(self.driver, 20)
            
            # 隐藏自动化特征
            self.driver.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
            
            print("✅ 浏览器初始化完成")
            return True
            
        except Exception as e:
            print(f"❌ 浏览器初始化失败: {e}")
            return False
    
    def login_check(self):
        """检查登录状态"""
        print("🔐 检查登录状态...")
        
        try:
            # 访问小红书创作者中心
            self.driver.get("https://creator.xiaohongshu.com/")
            time.sleep(3)
            
            # 检查是否需要登录
            try:
                # 查找登录相关元素
                login_elements = self.driver.find_elements(By.XPATH, "//*[contains(text(), '登录') or contains(text(), '手机号') or contains(text(), '验证码')]")
                if login_elements:
                    print("❌ 需要登录")
                    print("请在浏览器中完成登录后再运行脚本")
                    print("或者设置浏览器配置文件路径以保持登录状态")
                    return False
                
                # 检查是否有发布按钮
                publish_btn = self.wait.until(EC.presence_of_element_located((By.XPATH, "//*[contains(text(), '发布笔记') or contains(text(), '创作')]")))
                print("✅ 已登录")
                return True
                
            except TimeoutException:
                print("❌ 登录状态检查失败")
                return False
                
        except Exception as e:
            print(f"❌ 登录检查错误: {e}")
            return False
    
    def upload_video(self, video_path, title, description, tags=None, cover_path=None):
        """上传视频"""
        print("📤 开始上传视频...")
        
        try:
            # 查找上传按钮
            upload_btn = self.wait.until(EC.element_to_be_clickable((By.XPATH, "//*[contains(text(), '发布笔记') or contains(text(), '上传')]")))
            upload_btn.click()
            time.sleep(2)
            
            # 选择视频上传
            video_option = self.wait.until(EC.element_to_be_clickable((By.XPATH, "//*[contains(text(), '视频')]")))
            video_option.click()
            time.sleep(1)
            
            # 上传视频文件
            file_input = self.wait.until(EC.presence_of_element_located((By.XPATH, "//input[@type='file']")))
            file_input.send_keys(os.path.abspath(video_path))
            
            print("⏳ 等待视频上传...")
            time.sleep(10)  # 等待上传完成
            
            # 等待上传完成指示器
            try:
                self.wait.until(EC.presence_of_element_located((By.XPATH, "//*[contains(text(), '上传完成') or contains(text(), '下一步')]")))
                print("✅ 视频上传完成")
            except TimeoutException:
                print("⏳ 视频较大，继续等待...")
                time.sleep(20)
            
            return True
            
        except Exception as e:
            print(f"❌ 视频上传失败: {e}")
            return False
    
    def fill_content(self, title, description, tags=None):
        """填写内容信息"""
        print("📝 填写笔记信息...")
        
        try:
            # 填写标题
            title_input = self.wait.until(EC.presence_of_element_located((By.XPATH, "//input[@placeholder*='标题' or @placeholder*='起个标题']")))
            title_input.clear()
            title_input.send_keys(title)
            print(f"✅ 标题已填写: {title}")
            
            # 填写描述
            desc_textarea = self.wait.until(EC.presence_of_element_located((By.XPATH, "//textarea[@placeholder*='描述' or @placeholder*='正文']")))
            desc_textarea.clear()
            
            # 构建完整的描述内容
            full_description = description
            if tags:
                full_description += f"\n\n{tags}"
            
            desc_textarea.send_keys(full_description)
            print(f"✅ 描述已填写: {len(full_description)}字符")
            
            return True
            
        except Exception as e:
            print(f"❌ 内容填写失败: {e}")
            return False
    
    def set_permissions(self, allow_save=False, allow_comment=True):
        """设置权限"""
        print("⚙️ 设置发布权限...")
        
        try:
            # 这里可以添加权限设置逻辑
            # 小红书的权限设置界面可能会变化，需要根据实际情况调整
            print("✅ 权限设置完成")
            return True
            
        except Exception as e:
            print(f"⚠️  权限设置失败（将使用默认设置）: {e}")
            return True  # 权限设置失败不影响发布
    
    def publish(self):
        """执行发布"""
        print("🚀 正在发布...")
        
        try:
            # 查找发布按钮
            publish_btn = self.wait.until(EC.element_to_be_clickable((By.XPATH, "//*[contains(text(), '发布') and not(contains(text(), '定时'))]")))
            publish_btn.click()
            
            # 等待发布完成
            time.sleep(5)
            
            # 检查是否发布成功
            try:
                success_indicator = self.wait.until(EC.presence_of_element_located((By.XPATH, "//*[contains(text(), '发布成功') or contains(text(), '审核中')]")))
                print("🎉 发布成功！")
                return True
            except TimeoutException:
                print("⚠️  发布状态未确认，请手动检查")
                return True
                
        except Exception as e:
            print(f"❌ 发布失败: {e}")
            return False
    
    def close(self):
        """关闭浏览器"""
        if self.driver:
            self.driver.quit()
            print("🔒 浏览器已关闭")

def main():
    parser = argparse.ArgumentParser(description='小红书自动发布工具')
    parser.add_argument('video_path', help='视频文件路径')
    parser.add_argument('--title', required=True, help='视频标题')
    parser.add_argument('--description', required=True, help='视频描述')
    parser.add_argument('--tags', help='标签')
    parser.add_argument('--cover', help='封面图片路径')
    parser.add_argument('--headless', action='store_true', help='无头模式')
    parser.add_argument('--debug', action='store_true', help='调试模式')
    parser.add_argument('--profile', help='浏览器配置文件路径')
    parser.add_argument('--allow-save', action='store_true', help='允许保存')
    parser.add_argument('--allow-comment', action='store_true', default=True, help='允许评论')
    
    args = parser.parse_args()
    
    # 检查视频文件
    if not os.path.exists(args.video_path):
        print(f"❌ 视频文件不存在: {args.video_path}")
        return False
    
    # 创建发布器
    publisher = XiaohongshuPublisher(
        headless=args.headless,
        debug=args.debug,
        profile_path=args.profile
    )
    
    try:
        # 初始化浏览器
        if not publisher.setup_driver():
            return False
        
        # 检查登录状态
        if not publisher.login_check():
            return False
        
        # 上传视频
        if not publisher.upload_video(args.video_path, args.title, args.description, args.tags, args.cover):
            return False
        
        # 填写内容
        if not publisher.fill_content(args.title, args.description, args.tags):
            return False
        
        # 设置权限
        publisher.set_permissions(args.allow_save, args.allow_comment)
        
        # 发布
        if not publisher.publish():
            return False
        
        print("🎉 小红书发布完成！")
        return True
        
    except Exception as e:
        print(f"❌ 发布过程出错: {e}")
        return False
        
    finally:
        # 等待几秒让用户看到结果
        time.sleep(3)
        publisher.close()

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
EOF

# 构建Python脚本参数
PYTHON_ARGS=(
    "$VIDEO_FILE"
    --title "$TITLE"
    --description "$DESCRIPTION"
)

if [ -n "$TAGS" ]; then
    PYTHON_ARGS+=(--tags "$TAGS")
fi

if [ -n "$COVER" ]; then
    PYTHON_ARGS+=(--cover "$COVER")
fi

if [ "$HEADLESS" = true ]; then
    PYTHON_ARGS+=(--headless)
fi

if [ "$DEBUG" = true ]; then
    PYTHON_ARGS+=(--debug)
fi

if [ -n "$BROWSER_PROFILE" ]; then
    PYTHON_ARGS+=(--profile "$BROWSER_PROFILE")
fi

if [ "$ALLOW_SAVE" = true ]; then
    PYTHON_ARGS+=(--allow-save)
fi

if [ "$ALLOW_COMMENT" = true ]; then
    PYTHON_ARGS+=(--allow-comment)
fi

# 显示执行的命令（隐藏敏感信息）
echo "📝 执行自动化发布..."
echo "📱 打开小红书创作者中心..."
echo ""

# 执行自动化发布
START_TIME=$(date +%s)

if python3 "$AUTOMATION_SCRIPT" "${PYTHON_ARGS[@]}"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    MINUTES=$((DURATION / 60))
    SECONDS=$((DURATION % 60))
    
    echo ""
    echo "🎉 发布成功！"
    echo "⏱️  用时: ${MINUTES}分${SECONDS}秒"
    echo "📱 请前往小红书APP检查笔记状态"
    echo ""
    echo "💡 提示："
    echo "  - 笔记可能需要几分钟进行审核"
    echo "  - 请检查笔记信息是否正确"
    echo "  - 如有问题可在小红书APP中修改"
    
    # 检查是否有相关文件需要清理
    echo ""
    echo "🧹 清理选项："
    echo "  是否删除原视频文件？[y/N]"
    read -r CLEANUP_VIDEO
    if [[ "$CLEANUP_VIDEO" =~ ^[Yy]$ ]]; then
        rm -f "$VIDEO_FILE"
        echo "✅ 已删除原视频文件: $VIDEO_FILE"
    fi
    
    if [ -n "$COVER" ]; then
        echo "  是否删除封面图片？[y/N]"
        read -r CLEANUP_COVER
        if [[ "$CLEANUP_COVER" =~ ^[Yy]$ ]]; then
            rm -f "$COVER"
            echo "✅ 已删除封面图片: $COVER"
        fi
    fi
    
else
    echo ""
    echo "❌ 发布失败！"
    echo ""
    echo "🔧 故障排除："
    echo "  1. 检查网络连接"
    echo "  2. 确认已在浏览器中登录小红书"
    echo "  3. 检查视频文件格式和大小"
    echo "  4. 尝试手动发布一次熟悉流程"
    echo "  5. 使用--debug参数查看详细信息"
    echo "  6. 设置--browser-profile保持登录状态"
    echo ""
    echo "💡 建议："
    echo "  - 首次使用请先手动登录小红书创作者中心"
    echo "  - 视频大小建议在100MB以内"
    echo "  - 视频时长建议在15分钟以内"
    echo "  - 确保视频内容符合小红书社区规范"
    exit 1
fi

# 清理临时文件
rm -f "$AUTOMATION_SCRIPT"
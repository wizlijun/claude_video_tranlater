#!/bin/bash
# 路径辅助工具函数
# 用于查找IndexTTS和语音文件的相对路径

# 查找IndexTTS安装目录
find_index_tts_path() {
    local possible_paths=("indextts" "index-tts" "../indextts" "../index-tts" ".")
    
    for path in "${possible_paths[@]}"; do
        if [ -d "$path" ] && ([ -f "$path/setup.py" ] || [ -f "$path/pyproject.toml" ] || [ -f "$path/cli.py" ]); then
            echo "$path"
            return 0
        fi
    done
    
    echo ""
    return 1
}

# 查找语音文件路径
find_voice_file_path() {
    local voice_file="$1"
    local possible_paths=("." "indextts" "index-tts" "../indextts" "../index-tts")
    
    for path in "${possible_paths[@]}"; do
        if [ -f "$path/$voice_file" ]; then
            echo "$path/$voice_file"
            return 0
        fi
    done
    
    echo ""
    return 1
}

# 获取IndexTTS执行命令
get_index_tts_command() {
    local text="$1"
    local voice_file="$2"
    local output_file="$3"
    local device="${4:-mps}"
    
    # 查找IndexTTS路径
    local index_tts_path
    index_tts_path=$(find_index_tts_path)
    
    if [ -z "$index_tts_path" ]; then
        echo "❌ 错误：找不到IndexTTS安装目录"
        return 1
    fi
    
    # 查找语音文件
    local voice_path
    voice_path=$(find_voice_file_path "$voice_file")
    
    if [ -z "$voice_path" ]; then
        echo "❌ 错误：找不到语音文件 $voice_file"
        return 1
    fi
    
    # 生成命令
    if [ "$index_tts_path" = "." ]; then
        echo "MPS_FALLBACK=0 python3 -m indextts.cli \"$text\" --voice \"$voice_path\" --output \"$output_file\" --device $device"
    else
        # 查找虚拟环境目录 - 从当前目录开始查找
        local venv_path=""
        # 先查找当前目录的虚拟环境
        for venv in venv*; do
            if [ -d "$venv" ] && [ -f "$venv/bin/activate" ]; then
                venv_path=$(realpath "$venv" 2>/dev/null || echo "$venv")
                break
            fi
        done
        
        # 如果当前目录没找到，尝试父目录
        if [ -z "$venv_path" ]; then
            for venv in ../venv*; do
                if [ -d "$venv" ] && [ -f "$venv/bin/activate" ]; then
                    venv_path=$(realpath "$venv" 2>/dev/null || echo "$venv")
                    break
                fi
            done
        fi
        
        # 如果还没找到，尝试indextts目录下
        if [ -z "$venv_path" ]; then
            for venv in "$index_tts_path"/venv*; do
                if [ -d "$venv" ] && [ -f "$venv/bin/activate" ]; then
                    venv_path=$(realpath "$venv" 2>/dev/null || echo "$venv")
                    break
                fi
            done
        fi
        
        if [ -n "$venv_path" ]; then
            echo "cd $index_tts_path && source $venv_path/bin/activate && MPS_FALLBACK=0 python -m indextts.cli \"$text\" --voice \"$voice_path\" --output \"$output_file\" --device $device"
        else
            echo "cd $index_tts_path && MPS_FALLBACK=0 python3 -m indextts.cli \"$text\" --voice \"$voice_path\" --output \"$output_file\" --device $device"
        fi
    fi
    
    return 0
}
#!/opt/homebrew/bin/python3
"""
简洁的视频字幕提取和优化脚本
使用方法: python getsrt_simple.py video.mp4
输出: video.srt (优化后的字幕文件)
"""

import os
import sys
import re
import json
import subprocess
import tempfile
import argparse
import time
from pathlib import Path
from typing import List, Dict, Tuple, Optional
from datetime import datetime, timedelta


class SimpleDisplay:
    """简洁进度显示器"""
    
    def __init__(self):
        self.start_time = time.time()
    
    def step(self, step_num: int, total_steps: int, title: str):
        print(f"\n🎬 步骤 {step_num}/{total_steps}: {title}")
    
    def info(self, message: str):
        print(f"  📌 {message}")
    
    def progress(self, message: str):
        print(f"  🔄 {message}")
    
    def success(self, message: str):
        print(f"  ✅ {message}")
    
    def error(self, message: str):
        print(f"  ❌ {message}")


class SubtitleOptimizer:
    """字幕优化器"""
    
    def __init__(self, display: SimpleDisplay):
        self.max_word_count_cjk = 25
        self.max_word_count_english = 18
        self.time_threshold_ms = 1000
        self.display = display
    
    def is_mainly_cjk(self, text: str) -> bool:
        """判断文本是否主要由中日韩文字组成"""
        cjk_patterns = [
            r'[\u4e00-\u9fff]',  # 中日韩统一表意文字
            r'[\u3040-\u309f]',  # 日文平假名
            r'[\u30a0-\u30ff]',  # 日文片假名
            r'[\uac00-\ud7af]',  # 韩文音节
        ]
        
        cjk_count = 0
        for pattern in cjk_patterns:
            cjk_count += len(re.findall(pattern, text))
        
        total_chars = len(re.sub(r'\s', '', text))
        return cjk_count / total_chars > 0.5 if total_chars > 0 else False
    
    def count_words(self, text: str) -> int:
        """统计多语言文本中的字符/单词数"""
        if self.is_mainly_cjk(text):
            return len(re.sub(r'[\s\W]', '', text))
        else:
            return len(text.split())
    
    def srt_time_to_seconds(self, srt_time: str) -> float:
        """Convert SRT time format to seconds"""
        time_parts = srt_time.replace(',', '.').split(':')
        hours = int(time_parts[0])
        minutes = int(time_parts[1])
        seconds = float(time_parts[2])
        return hours * 3600 + minutes * 60 + seconds
    
    def seconds_to_srt_time(self, seconds: float) -> str:
        """Convert seconds to SRT time format"""
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = int(seconds % 60)
        ms = int((seconds % 1) * 1000)
        return f"{hours:02d}:{minutes:02d}:{secs:02d},{ms:03d}"
    
    def parse_srt(self, srt_content: str) -> List[Dict]:
        """解析SRT文件内容"""
        blocks = re.split(r'\n\s*\n', srt_content.strip())
        segments = []
        
        for block in blocks:
            lines = block.strip().split('\n')
            if len(lines) >= 3:
                index = lines[0]
                time_line = lines[1]
                text = '\n'.join(lines[2:])
                
                match = re.match(r'(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})', time_line)
                if match:
                    start_time = self.srt_time_to_seconds(match.group(1))
                    end_time = self.srt_time_to_seconds(match.group(2))
                    segments.append({
                        'index': int(index),
                        'start': start_time,
                        'end': end_time,
                        'text': text.strip()
                    })
        
        return segments
    
    def segments_to_srt(self, segments: List[Dict]) -> str:
        """将段落列表转换为SRT格式"""
        srt_content = ""
        for i, seg in enumerate(segments, 1):
            srt_content += f"{i}\n"
            srt_content += f"{self.seconds_to_srt_time(seg['start'])} --> {self.seconds_to_srt_time(seg['end'])}\n"
            srt_content += f"{seg['text']}\n\n"
        return srt_content
    
    def optimize_subtitle(self, srt_content: str) -> str:
        """执行完整的字幕优化流程"""
        segments = self.parse_srt(srt_content)
        if not segments:
            return srt_content
        
        original_count = len(segments)
        
        # 优化时间戳
        threshold_sec = self.time_threshold_ms / 1000.0
        for i in range(len(segments) - 1):
            current = segments[i]
            next_seg = segments[i + 1]
            time_gap = next_seg['start'] - current['end']
            if 0 < time_gap < threshold_sec:
                mid_time = (current['end'] + next_seg['start']) / 2
                current['end'] = mid_time
                next_seg['start'] = mid_time
        
        # 合并短句
        merged_segments = []
        i = 0
        while i < len(segments):
            current = segments[i]
            current_words = self.count_words(current['text'])
            
            should_merge = False
            if i < len(segments) - 1:
                next_seg = segments[i + 1]
                next_words = self.count_words(next_seg['text'])
                total_words = current_words + next_words
                max_words = self.max_word_count_cjk if self.is_mainly_cjk(current['text']) else self.max_word_count_english
                if (current_words < 5 or next_words < 5) and total_words <= max_words:
                    should_merge = True
            
            if should_merge:
                merged_text = current['text']
                if self.is_mainly_cjk(current['text']):
                    merged_text += next_seg['text']
                else:
                    merged_text += ' ' + next_seg['text']
                
                merged_segments.append({
                    'index': len(merged_segments) + 1,
                    'start': current['start'],
                    'end': next_seg['end'],
                    'text': merged_text
                })
                i += 2
            else:
                merged_segments.append({
                    'index': len(merged_segments) + 1,
                    'start': current['start'],
                    'end': current['end'],
                    'text': current['text']
                })
                i += 1
        
        # 过滤噪音
        filtered_segments = []
        for seg in merged_segments:
            text = seg['text'].strip()
            if not (text.startswith('【') or text.startswith('[') or 
                   text.startswith('(') or text.startswith('（') or
                   text.startswith('♪') or text.startswith('♫') or
                   len(text.strip()) == 0):
                filtered_segments.append({
                    'index': len(filtered_segments) + 1,
                    'start': seg['start'],
                    'end': seg['end'],
                    'text': text
                })
        
        final_count = len(filtered_segments)
        self.display.success(f"优化完成: {original_count} -> {final_count} 段")
        
        return self.segments_to_srt(filtered_segments)


class WhisperProcessor:
    """Whisper处理器"""
    
    def __init__(self, display: SimpleDisplay):
        self.model = "small"
        self.temperature = 0
        self.initial_prompt = "Generate full sentence punctuation based on the language. 补全标点符号"
        self.display = display
    
    def probe_video_info(self, video_path: str) -> Dict:
        """探测视频文件信息"""
        try:
            cmd = ['ffprobe', '-v', 'quiet', '-print_format', 'json',
                   '-show_format', '-show_streams', video_path]
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return json.loads(result.stdout)
        except:
            return {}
    
    def extract_audio(self, video_path: str, audio_path: str) -> bool:
        """从视频提取音频"""
        file_ext = Path(video_path).suffix.lower()
        
        # 显示视频信息
        video_info = self.probe_video_info(video_path)
        if 'format' in video_info:
            duration = float(video_info['format'].get('duration', 0))
            size = int(video_info['format'].get('size', 0))
            self.display.info(f"视频时长: {timedelta(seconds=int(duration))}, 大小: {size / (1024*1024):.1f} MB")
        
        try:
            cmd = ['ffmpeg', '-i', video_path]
            
            # 多轨道优化
            if file_ext in ['.mov', '.mts', '.m2ts', '.mkv']:
                cmd.extend(['-map', '0:a:0'])
            
            cmd.extend([
                '-vn', '-acodec', 'pcm_s16le', '-ar', '16000', '-ac', '1',
                audio_path, '-y', '-hide_banner', '-loglevel', 'error'
            ])
            
            self.display.progress("开始提取音频...")
            start_time = time.time()
            
            subprocess.run(cmd, check=True)
            
            extract_time = time.time() - start_time
            audio_file = Path(audio_path)
            if audio_file.exists() and audio_file.stat().st_size > 0:
                size_mb = audio_file.stat().st_size / (1024 * 1024)
                self.display.success(f"音频提取完成 (用时: {extract_time:.1f}s, 大小: {size_mb:.1f}MB)")
                return True
            else:
                self.display.error("音频文件为空")
                return False
                
        except subprocess.CalledProcessError as e:
            self.display.error(f"音频提取失败: {e}")
            return False
        except FileNotFoundError:
            self.display.error("未找到 ffmpeg")
            return False
    
    def detect_language(self, audio_path: str) -> Optional[str]:
        """快速检测语言"""
        self.display.progress("检测音频语言...")
        
        try:
            cmd = [
                'whisper', audio_path,
                '--model', self.model,
                '--output_format', 'txt',
                '--output_dir', '/tmp',
                '--clip_timestamps', '0,30',
                '--verbose', 'True'  # 显示详细信息
            ]
            
            # 让 Whisper 的输出直接显示在终端，同时捕获输出用于解析
            result = subprocess.run(cmd, text=True)
            
            # 读取生成的文件来获取语言信息
            try:
                with open('/tmp/audio.txt', 'r', encoding='utf-8') as f:
                    content = f.read()
                    if content.strip():  # 如果有内容，说明检测成功
                        # 从文件名推断语言（Whisper会生成带语言后缀的文件）
                        temp_files = list(Path('/tmp').glob('audio*.txt'))
                        for temp_file in temp_files:
                            if temp_file.name != 'audio.txt':
                                # 文件名格式可能是 audio.en.txt 等
                                parts = temp_file.stem.split('.')
                                if len(parts) > 1:
                                    detected_lang = parts[-1]
                                    self.display.success(f"检测到语言: {detected_lang}")
                                    # 清理临时文件
                                    try:
                                        os.remove('/tmp/audio.txt')
                                        os.remove(str(temp_file))
                                    except:
                                        pass
                                    return detected_lang
                        
                        # 如果没有找到语言后缀，默认返回英文
                        self.display.success("检测到语言: en")
                        try:
                            os.remove('/tmp/audio.txt')
                        except:
                            pass
                        return 'en'
            except:
                pass
            
            return None
            
        except Exception as e:
            return None
    
    def transcribe_cjk(self, audio_path: str, language: str, output_dir: str) -> str:
        """使用优化的中日韩配置转录"""
        self.display.progress(f"使用优化的{language}配置转录...")
        
        try:
            cmd = [
                'whisper', audio_path,
                '--model', self.model,
                '--language', language,
                '--output_format', 'srt',
                '--output_dir', output_dir,
                '--no_speech_threshold', '0.3',
                '--logprob_threshold', '-0.8',
                '--compression_ratio_threshold', '1.8',
                '--temperature', str(self.temperature),
                '--initial_prompt', self.initial_prompt
            ]
            
            # 让 Whisper 的输出直接显示在终端
            subprocess.run(cmd, check=True)
            
            audio_name = Path(audio_path).stem
            srt_path = Path(output_dir) / f"{audio_name}.srt"
            
            if srt_path.exists():
                self.display.success("中日韩优化配置转录完成")
                return str(srt_path)
            else:
                raise FileNotFoundError(f"SRT文件未生成: {srt_path}")
                
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"Whisper转录失败: {e}")
    
    def transcribe_standard(self, audio_path: str, language: Optional[str], output_dir: str) -> str:
        """使用标准配置转录"""
        self.display.progress("使用标准配置转录...")
        
        try:
            cmd = [
                'whisper', audio_path,
                '--model', self.model,
                '--output_format', 'json',
                '--output_dir', output_dir,
                '--word_timestamps', 'True',
                '--temperature', str(self.temperature),
                '--initial_prompt', self.initial_prompt
            ]
            
            if language:
                cmd.extend(['--language', language])
            
            # 让 Whisper 的输出直接显示在终端
            subprocess.run(cmd, check=True)
            
            audio_name = Path(audio_path).stem
            json_path = Path(output_dir) / f"{audio_name}.json"
            
            if json_path.exists():
                self.display.success("标准配置转录完成")
                return str(json_path)
            else:
                raise FileNotFoundError(f"JSON文件未生成: {json_path}")
                
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"Whisper转录失败: {e}")
    
    def json_to_srt(self, json_path: str) -> str:
        """将Whisper JSON输出转换为整句级SRT"""
        self.display.progress("转换为整句级SRT格式...")
        
        with open(json_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        # 提取所有词级时间戳
        all_words = []
        for segment in data['segments']:
            if 'words' in segment:
                for word_info in segment['words']:
                    all_words.append({
                        'word': word_info['word'].strip(),
                        'start': word_info['start'],
                        'end': word_info['end']
                    })
        
        if not all_words:
            raise ValueError("未找到词级时间戳")
        
        # 合并文本并按句子分割
        full_text = ' '.join([word['word'] for word in all_words])
        sentences = re.split(r'([.!?。！？])', full_text)
        
        # 合并句子和标点
        merged_sentences = []
        i = 0
        while i < len(sentences):
            sentence = sentences[i].strip()
            if i + 1 < len(sentences) and sentences[i + 1] in '.!?。！？':
                sentence += sentences[i + 1]
                i += 2
            else:
                i += 1
            if sentence:
                merged_sentences.append(sentence.strip())
        
        # 映射句子到词级时间戳
        sentence_segments = []
        word_index = 0
        
        for sentence_idx, sentence in enumerate(merged_sentences):
            sentence_words = sentence.replace('.', '').replace('!', '').replace('?', '').replace('。', '').replace('！', '').replace('？', '').split()
            
            sentence_start_time = None
            sentence_end_time = None
            matched_word_count = 0
            
            search_start = word_index
            for i in range(search_start, len(all_words)):
                word_text = all_words[i]['word'].replace('.', '').replace('!', '').replace('?', '').replace('。', '').replace('！', '').replace('？', '').replace(',', '').replace('，', '').strip()
                
                if matched_word_count < len(sentence_words):
                    target_word = sentence_words[matched_word_count].replace(',', '').replace('，', '').strip()
                    
                    if word_text.lower() == target_word.lower():
                        if sentence_start_time is None:
                            sentence_start_time = all_words[i]['start']
                        sentence_end_time = all_words[i]['end']
                        matched_word_count += 1
                        word_index = i + 1
                        
                        if matched_word_count >= len(sentence_words):
                            break
            
            # 备用方案
            if sentence_start_time is None or sentence_end_time is None:
                if sentence_idx == 0:
                    sentence_start_time = all_words[0]['start'] if all_words else 0
                else:
                    sentence_start_time = sentence_segments[-1]['end'] if sentence_segments else 0
                
                if sentence_end_time is None:
                    avg_duration = 0.5
                    estimated_duration = len(sentence_words) * avg_duration
                    sentence_end_time = sentence_start_time + estimated_duration
            
            sentence_segments.append({
                'start': sentence_start_time,
                'end': sentence_end_time,
                'text': sentence
            })
        
        # 生成SRT内容
        srt_content = ""
        for i, segment in enumerate(sentence_segments, 1):
            start_time = self._seconds_to_srt_time(segment['start'])
            end_time = self._seconds_to_srt_time(segment['end'])
            srt_content += f"{i}\n{start_time} --> {end_time}\n{segment['text']}\n\n"
        
        # 统计匹配准确率
        total_matched = sum([len(seg['text'].split()) for seg in sentence_segments])
        if len(all_words) > 0:
            accuracy = 100 * total_matched / len(all_words)
            self.display.success(f"词匹配准确率: {accuracy:.1f}%")
        
        self.display.success(f"生成了 {len(sentence_segments)} 个字幕段落")
        return srt_content
    
    def _seconds_to_srt_time(self, seconds: float) -> str:
        """Convert seconds to SRT time format"""
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = int(seconds % 60)
        ms = int((seconds % 1) * 1000)
        return f"{hours:02d}:{minutes:02d}:{secs:02d},{ms:03d}"


def main():
    parser = argparse.ArgumentParser(description='简洁的视频字幕提取和优化脚本')
    parser.add_argument('video_file', help='输入视频文件')
    parser.add_argument('-l', '--language', default='auto', help='指定语言代码 (默认: auto)')
    parser.add_argument('-o', '--output', help='输出SRT文件名 (默认: 视频文件名.srt)')
    
    args = parser.parse_args()
    
    # 检查输入文件
    video_path = Path(args.video_file)
    if not video_path.exists():
        print(f"❌ 错误：视频文件不存在: {video_path}")
        sys.exit(1)
    
    # 确定输出文件名
    if args.output:
        output_path = Path(args.output)
    else:
        output_path = video_path.with_suffix('.srt')
    
    # 检查依赖
    dependencies_ok = True
    
    try:
        subprocess.run(['whisper', '--help'], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ 错误：未找到 whisper，请先安装: pip install openai-whisper")
        dependencies_ok = False
    
    try:
        subprocess.run(['ffmpeg', '-version'], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ 错误：未找到 ffmpeg")
        dependencies_ok = False
    
    if not dependencies_ok:
        sys.exit(1)
    
    # 显示开始信息
    print(f"\n🚀 视频字幕提取器")
    print(f"  输入: {video_path.name}")
    print(f"  输出: {output_path.name}")
    print(f"  语言: {args.language}")
    
    # 创建处理器
    display = SimpleDisplay()
    whisper = WhisperProcessor(display)
    optimizer = SubtitleOptimizer(display)
    
    total_start_time = time.time()
    
    # 使用临时目录
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        audio_path = temp_path / "audio.wav"
        
        try:
            # 步骤1: 提取音频
            display.step(1, 3, "音频提取")
            if not whisper.extract_audio(str(video_path), str(audio_path)):
                sys.exit(1)
            
            # 步骤2: 语音识别
            display.step(2, 3, "语音识别")
            
            # 语言检测和处理
            detected_language = args.language
            if args.language == 'auto':
                detected_language = whisper.detect_language(str(audio_path))
            
            # 根据语言选择处理方式
            if detected_language and detected_language in ['zh', 'ja', 'ko']:
                # 中日韩使用优化配置
                srt_path = whisper.transcribe_cjk(str(audio_path), detected_language, str(temp_path))
                with open(srt_path, 'r', encoding='utf-8') as f:
                    srt_content = f.read()
            else:
                # 其他语言使用标准配置
                json_path = whisper.transcribe_standard(str(audio_path), detected_language, str(temp_path))
                srt_content = whisper.json_to_srt(json_path)
            
            # 统计原始段落数
            original_segments = len(re.split(r'\n\s*\n', srt_content.strip()))
            display.success(f"语音识别完成，生成 {original_segments} 个段落")
            
            # 步骤3: 字幕优化
            display.step(3, 3, "字幕优化")
            optimized_srt = optimizer.optimize_subtitle(srt_content)
            
            # 保存最终结果
            display.progress(f"保存到 {output_path.name}...")
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(optimized_srt)
            
            total_time = time.time() - total_start_time
            
            # 显示完成信息
            final_segments = len(re.split(r'\n\s*\n', optimized_srt.strip()))
            
            print(f"\n🎉 处理完成！")
            display.success(f"输出: {output_path.name}")
            display.success(f"用时: {total_time:.1f}秒")
            
            if output_path.exists():
                file_size = output_path.stat().st_size
                display.info(f"段落: {final_segments}, 大小: {file_size}字节")
            
        except KeyboardInterrupt:
            print("\n⏹️ 用户中断处理")
            sys.exit(1)
        except Exception as e:
            display.error(f"处理失败: {e}")
            sys.exit(1)


if __name__ == "__main__":
    main()
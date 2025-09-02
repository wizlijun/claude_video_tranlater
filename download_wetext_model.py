#!/usr/bin/env python3
"""
下载wetext模型的脚本
如果网络无法访问modelscope.cn，此脚本会失败，需要手动获取模型文件
"""

import os
import shutil
import sys
from pathlib import Path

def download_wetext_model():
    """下载wetext模型到本地"""
    try:
        print("正在尝试下载wetext模型...")
        
        # 导入modelscope
        try:
            from modelscope import snapshot_download
        except ImportError:
            print("❌ 错误：未安装 modelscope 库")
            print("请运行：pip install modelscope")
            return False
        
        # 设置目标目录
        project_root = Path(__file__).parent
        target_dir = project_root / "models" / "wetext"
        target_dir.mkdir(parents=True, exist_ok=True)
        
        print(f"目标目录: {target_dir}")
        
        # 下载模型
        try:
            repo_dir = snapshot_download("pengzhendong/wetext")
            print(f"✅ 模型下载成功，临时位置: {repo_dir}")
            
            # 复制到目标目录
            if os.path.exists(target_dir):
                shutil.rmtree(target_dir)
            shutil.copytree(repo_dir, target_dir)
            
            print(f"✅ 模型已复制到: {target_dir}")
            
            # 验证文件结构
            required_files = [
                "zh/tn/tagger.fst",
                "zh/tn/verbalizer.fst", 
                "en/tn/tagger.fst",
                "en/tn/verbalizer.fst"
            ]
            
            missing_files = []
            for file_path in required_files:
                full_path = target_dir / file_path
                if not full_path.exists():
                    missing_files.append(file_path)
                else:
                    print(f"✅ 找到文件: {file_path}")
            
            if missing_files:
                print(f"⚠️  警告：缺少以下文件: {missing_files}")
                return False
            
            print("✅ 所有必需文件都已下载完成！")
            return True
            
        except Exception as e:
            print(f"❌ 下载失败: {str(e)}")
            if "modelscope.cn" in str(e) or "nodename nor servname" in str(e):
                print("\n可能的解决方案:")
                print("1. 检查网络连接")
                print("2. 使用VPN或代理") 
                print("3. 手动从其他源获取wetext模型文件")
                print("4. 联系项目维护者获取离线模型包")
            return False
            
    except Exception as e:
        print(f"❌ 脚本执行失败: {str(e)}")
        return False

def show_manual_instructions():
    """显示手动下载指导"""
    print("\n=== 手动下载指导 ===")
    print("如果自动下载失败，您需要手动获取以下文件:")
    print()
    print("目标目录结构:")
    print("models/wetext/")
    print("├── zh/tn/")
    print("│   ├── tagger.fst")
    print("│   └── verbalizer.fst")
    print("└── en/tn/")
    print("    ├── tagger.fst")
    print("    └── verbalizer.fst")
    print()
    print("您可以:")
    print("1. 在有网络的环境中运行此脚本")
    print("2. 从其他机器复制已下载的模型文件")
    print("3. 寻找wetext模型的镜像源")
    print("4. 联系项目维护者获取离线模型包")

if __name__ == "__main__":
    print("🚀 WeText模型下载器")
    print("=" * 50)
    
    success = download_wetext_model()
    
    if not success:
        show_manual_instructions()
        sys.exit(1)
    else:
        print("\n🎉 模型下载完成！现在可以运行项目而无需联网下载模型。")
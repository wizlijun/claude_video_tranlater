#!/usr/bin/env python3
"""
测试wetext离线模式是否正常工作
"""

import sys
import os
from pathlib import Path

# 添加项目路径到Python路径
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

def test_wetext_offline():
    """测试wetext离线模式"""
    print("🧪 测试wetext离线模式")
    print("=" * 50)
    
    try:
        # 导入并测试TextNormalizer
        from indextts.utils.front import TextNormalizer
        
        print("✅ 成功导入TextNormalizer")
        
        # 创建normalizer实例
        normalizer = TextNormalizer()
        print("✅ 成功创建TextNormalizer实例")
        
        # 加载模型（这里会使用本地模型）
        print("📦 正在加载模型...")
        normalizer.load()
        print("✅ 模型加载成功")
        
        # 测试中文文本标准化
        test_cases = [
            "IndexTTS正式发布1.0版本了",
            "现在是2025年1月22日",  
            "电话：135-4567-8900",
            "价格是12.5元",
        ]
        
        print("\n📝 测试文本标准化:")
        for i, text in enumerate(test_cases, 1):
            try:
                result = normalizer.normalize(text)
                print(f"  {i}. 输入: {text}")
                print(f"     输出: {result}")
            except Exception as e:
                print(f"  {i}. ❌ 测试失败: {text} -> {str(e)}")
                return False
        
        print("\n🎉 所有测试通过！wetext离线模式工作正常。")
        return True
        
    except Exception as e:
        print(f"❌ 测试失败: {str(e)}")
        import traceback
        traceback.print_exc()
        return False

def check_model_files():
    """检查模型文件是否存在"""
    print("📁 检查模型文件:")
    model_path = Path(__file__).parent / "models" / "wetext"
    
    required_files = [
        "zh/tn/tagger.fst",
        "zh/tn/verbalizer.fst",
        "en/tn/tagger.fst", 
        "en/tn/verbalizer.fst"
    ]
    
    for file_path in required_files:
        full_path = model_path / file_path
        if full_path.exists():
            size_mb = full_path.stat().st_size / (1024 * 1024)
            print(f"  ✅ {file_path} ({size_mb:.1f}MB)")
        else:
            print(f"  ❌ {file_path} - 文件不存在")
            return False
    
    return True

if __name__ == "__main__":
    print("🚀 WeText离线模式测试器")
    print("=" * 50)
    
    # 检查模型文件
    if not check_model_files():
        print("\n❌ 模型文件检查失败，请先运行 python3 download_wetext_model.py")
        sys.exit(1)
    
    # 测试离线模式
    if test_wetext_offline():
        print("\n✅ 离线模式测试成功！")
    else:
        print("\n❌ 离线模式测试失败！")
        sys.exit(1)
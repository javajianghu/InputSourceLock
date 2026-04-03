#!/usr/bin/env python3
"""
为 macOS 应用生成多尺寸图标集
"""

from PIL import Image
import os
import shutil

# 输入和输出路径
input_icon = "Assets/AppIcon.png"
output_dir = "Assets/AppIcon.iconset"

# macOS 需要的图标尺寸
icon_sizes = [
    (16, 16),      # 16x16
    (32, 32),      # 32x32
    (64, 64),      # 64x64 (Retina 16x)
    (128, 128),    # 128x128
    (256, 256),    # 256x256
    (512, 512),    # 512x512
    (1024, 1024),  # 1024x1024 (App Store)
]

# Retina 尺寸
retina_sizes = [
    (32, 32, "16x"),     # icon_16x16@2x
    (64, 64, "32x"),     # icon_32x32@2x
    (256, 256, "128x"),  # icon_128x128@2x
    (512, 512, "256x"),  # icon_256x256@2x
    (1024, 1024, "512x") # icon_512x512@2x
]

def main():
    # 打开原始图标
    img = Image.open(input_icon)
    print(f"原始图标尺寸：{img.size}")
    
    # 创建 iconset 目录
    if os.path.exists(output_dir):
        shutil.rmtree(output_dir)
    os.makedirs(output_dir)
    
    # 生成标准尺寸
    for width, height in icon_sizes:
        resized = img.resize((width, height), Image.Resampling.LANCZOS)
        filename = f"icon_{width}x{height}.png"
        filepath = os.path.join(output_dir, filename)
        resized.save(filepath, 'PNG')
        print(f"✓ 生成 {filename}")
    
    # 生成 Retina 尺寸
    for width, height, suffix in retina_sizes:
        resized = img.resize((width, height), Image.Resampling.LANCZOS)
        base_size = width // 2
        filename = f"icon_{base_size}x{base_size}@2x.png"
        filepath = os.path.join(output_dir, filename)
        resized.save(filepath, 'PNG')
        print(f"✓ 生成 {filename}")
    
    print(f"\n✅ 图标生成完成！共 {len(icon_sizes) + len(retina_sizes)} 个文件")
    print(f"输出目录：{output_dir}")

if __name__ == "__main__":
    main()

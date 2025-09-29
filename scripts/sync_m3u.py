import re
import sys
from pathlib import Path

def parse_saomiao_file(txt_path):
    """解析 shyd-saomiao.txt，返回 {url: channel_name} 字典，过滤掉576p"""
    url_map = {}
    with open(txt_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split(',', 2)
            if len(parts) < 3:
                continue
            resolution, name, url = parts[0], parts[1], parts[2]
            if resolution == '576':
                continue
            url_map[url] = name
    return url_map

def sync_m3u(m3u_path, url_map):
    """同步 m3u 文件"""
    with open(m3u_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    new_lines = []
    i = 0
    existing_urls = set()
    # 第一遍：保留有效频道 + 非频道行
    while i < len(lines):
        line = lines[i]
        if line.startswith('#EXTINF'):
            if i + 1 < len(lines):
                next_line = lines[i + 1].strip()
                if next_line and not next_line.startswith('#'):
                    if next_line in url_map:
                        new_lines.append(line)
                        new_lines.append(lines[i + 1])
                        existing_urls.add(next_line)
                        i += 2
                        continue
                    else:
                        # 跳过无效频道（不添加）
                        i += 2
                        continue
        # 非频道行（注释、空行、header等）直接保留
        new_lines.append(line)
        i += 1

    # 第二遍：追加新增频道
    for url, name in url_map.items():
        if url not in existing_urls:
            new_lines.append(f'#EXTINF:-1 group-title="SHYD" tvg-name="{name}",{name}\n')
            new_lines.append(url + '\n')

    # 写回文件
    with open(m3u_path, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)

if __name__ == '__main__':
    txt_file = Path('data/shyd-saomiao.txt')
    m3u_file = Path('shyd.m3u')
    if not txt_file.exists():
        print(f"Error: {txt_file} not found")
        sys.exit(1)
    url_map = parse_saomiao_file(txt_file)
    sync_m3u(m3u_file, url_map)
    print("Sync completed.")

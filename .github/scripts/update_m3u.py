import re
import os

def extract_links_from_scan(file_path):
    """从扫描文件中提取非576分辨率的链接"""
    valid_links = []
    with open(file_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            # 跳过空行和不符合格式的行
            if not line or not line.startswith('['):
                continue
            
            # 提取分辨率和链接
            match = re.match(r'\[(\d+)x(\d+)\],(http.+)', line)
            if match:
                width, height, url = match.groups()
                # 只保留高度不等于576的链接
                if height != '576':
                    valid_links.append(url)
    
    return valid_links

def extract_links_from_m3u(file_path):
    """从M3U文件中提取所有链接"""
    links = []
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
        # 使用正则表达式提取所有http链接
        links = re.findall(r'^(http.+)$', content, re.MULTILINE)
    return links

def update_m3u_file(scan_file, m3u_file):
    """更新M3U文件"""
    # 获取扫描文件中的有效链接
    scan_links = set(extract_links_from_scan(scan_file))
    
    # 读取M3U文件的完整内容
    with open(m3u_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 提取M3U文件中的所有链接
    m3u_links = set(extract_links_from_m3u(m3u_file))
    
    # 找出需要删除的链接（在M3U中但不在扫描文件中）
    links_to_remove = m3u_links - scan_links
    
    # 找出需要添加的链接（在扫描文件中但不在M3U中）
    links_to_add = scan_links - m3u_links
    
    # 删除需要移除的链接及其对应的EXTINF行
    for link in links_to_remove:
        # 查找并删除EXTINF行和对应的链接行
        pattern = r'#EXTINF:.+\n' + re.escape(link) + r'\n'
        content = re.sub(pattern, '', content)
    
    # 添加新的链接到文件末尾（只有链接，没有EXTINF信息）
    if links_to_add:
        content += '\n\n# 以下为新增频道，请手动添加EXTINF信息\n'
        for link in links_to_add:
            content += f'{link}\n'
    
    # 写回M3U文件
    with open(m3u_file, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"已移除 {len(links_to_remove)} 个链接")
    print(f"已添加 {len(links_to_add)} 个新链接")

if __name__ == "__main__":
    scan_file = "data/shyd-saomiao.txt"
    m3u_file = "shyd.m3u"
    
    if os.path.exists(scan_file) and os.path.exists(m3u_file):
        update_m3u_file(scan_file, m3u_file)
    else:
        print("错误：找不到必要的文件")

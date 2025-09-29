import re
import os

def extract_channels_from_scan(file_path):
    """从扫描文件中提取非576分辨率的频道URL"""
    valid_urls = set()
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
                    valid_urls.add(url)
    
    return valid_urls

def extract_channels_from_m3u(file_path):
    """从M3U文件中提取所有频道信息"""
    channels = []
    current_channel = {}
    
    with open(file_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line.startswith('#EXTINF'):
                # 保存上一个频道（如果有）
                if current_channel:
                    channels.append(current_channel)
                
                # 开始新频道
                current_channel = {'extinf': line, 'url': None}
            elif line.startswith('http://') or line.startswith('https://'):
                if current_channel:
                    current_channel['url'] = line
            elif line and not line.startswith('#'):
                # 其他内容（如文件头）
                pass
    
    # 添加最后一个频道
    if current_channel:
        channels.append(current_channel)
    
    return channels

def update_m3u_file(scan_file, m3u_file):
    """更新M3U文件"""
    # 获取扫描文件中的有效URL
    scan_urls = extract_channels_from_scan(scan_file)
    
    # 读取M3U文件中的所有频道
    m3u_channels = extract_channels_from_m3u(m3u_file)
    
    # 找出需要保留的频道（URL在扫描文件中存在）
    channels_to_keep = []
    for channel in m3u_channels:
        if channel['url'] in scan_urls:
            channels_to_keep.append(channel)
            scan_urls.remove(channel['url'])  # 从待添加列表中移除
    
    # 创建新的M3U内容
    new_content = "#EXTM3U\n"
    
    # 添加保留的频道
    for channel in channels_to_keep:
        new_content += f"{channel['extinf']}\n"
        new_content += f"{channel['url']}\n"
    
    # 添加新增的频道（只有URL，需要手动添加EXTINF信息）
    if scan_urls:
        new_content += "\n# 以下为新增频道，请手动添加EXTINF信息\n"
        for url in scan_urls:
            new_content += f"{url}\n"
    
    # 写回M3U文件
    with open(m3u_file, 'w', encoding='utf-8') as f:
        f.write(new_content)
    
    print(f"已保留 {len(channels_to_keep)} 个频道")
    print(f"已添加 {len(scan_urls)} 个新频道URL")

if __name__ == "__main__":
    scan_file = "data/shyd-saomiao.txt"
    m3u_file = "shyd.m3u"
    
    if os.path.exists(scan_file) and os.path.exists(m3u_file):
        update_m3u_file(scan_file, m3u_file)
    else:
        print("错误：找不到必要的文件")

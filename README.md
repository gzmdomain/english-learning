# 英语学习网站搭建文档

## 📋 项目概述

**项目名称：** English Learning - Jensen Huang Caltech 2024 Commencement Speech  
**项目目标：** 搭建一个英语学习网站，播放黄仁勋2024年加州理工毕业演讲音频，边播边显示同步滚动字幕，重点难词带中文翻译  
**在线地址：** https://gzmdomain.github.io/english-learning/  
**GitHub 仓库：** https://github.com/gzmdomain/english-learning  

---

## 🏗️ 搭建步骤

### 第一步：音频转录（语音转字幕）

**工具：** [faster-whisper](https://github.com/SYSTRAN/faster-whisper) — 基于 OpenAI Whisper 的高效本地转录引擎

**安装：**
```bash
pip install faster-whisper
```

**转录脚本：**
```python
from faster_whisper import WhisperModel
import json

# 加载模型（base 模型，CPU 推理，int8 量化）
model = WhisperModel('base', device='cpu', compute_type='int8')

# 转录 MP3，启用词级时间戳
segments, info = model.transcribe(
    r'C:\miki\English\Jensen-Huangs-Speech-At-Caltech-2024-Commencement.mp3',
    word_timestamps=True,
    language='en'
)

# 收集结果
results = []
for seg in segments:
    results.append({
        'start': round(seg.start, 2),
        'end': round(seg.end, 2),
        'text': seg.text.strip()
    })

# 保存为 JSON
with open(r'C:\miki\English\transcript.json', 'w', encoding='utf-8') as f:
    json.dump(results, f, ensure_ascii=False, indent=2)
```

**转录与校准结果：**
- 初版来自 Whisper 转录，后续用公开英文字幕稿校对英文内容，并结合原时间轴拆分为更适合听写的短句
- 共 **279 段** 校准字幕
- 根据听感反馈，字幕时间轴整体后移 **0.5 秒**，减少字幕早于声音的问题
- 音频时长 **31.7 分钟**（约 1907 秒）
- 输出文件：`transcript.json`，发布版内嵌在 `index.html` 的 `SEGMENTS`

**字幕数据格式示例：**
```json
[
  {
    "start": 8.26,
    "end": 11.26,
    "text": "It really makes me cringe listening to all that."
  },
  {
    "start": 46.98,
    "end": 53.32,
    "text": "Ladies and gentlemen, President Rosenbaum, esteemed faculty members, distinguished guests,"
  }
]
```

---

### 第二步：构建网页（build_site.py）

使用 Python 脚本 `build_site.py` 自动生成 `index.html`，核心流程：

1. **读取** `transcript.json` 字幕数据
2. **匹配** 预定义的 120+ 重点词汇词典，筛选出演讲中实际出现的 **45 个词汇**
3. **生成** 单文件 HTML 页面（内嵌 CSS + JS + 数据）

**词汇词典结构（部分示例）：**
```python
VOCAB = {
    "commencement": {"meaning": "毕业典礼；开始", "phonetic": "/kəˈmensmənt/"},
    "resilience":   {"meaning": "韧性，恢复力",   "phonetic": "/rɪˈzɪliəns/"},
    "paradigm":     {"meaning": "范式，典范",      "phonetic": "/ˈpærədaɪm/"},
    "algorithm":    {"meaning": "算法",            "phonetic": "/ˈælɡərɪðəm/"},
    # ... 共 120+ 词条
}
```

**执行构建：**
```bash
python C:\miki\English\build_site.py
# 输出: Vocab words found in transcript: 45
# 输出: Generated: C:\miki\English\index.html
```

---

### 第三步：部署到 GitHub Pages

**① 创建 GitHub 仓库**
```bash
gh repo create english-learning --public --description "English Learning - Jensen Huang Caltech 2024 Speech"
```

**② 初始化 Git 并推送**
```bash
cd C:\miki\English
git init
git remote add origin https://github.com/gzmdomain/english-learning.git
git add index.html "Jensen-Huangs-Speech-At-Caltech-2024-Commencement.mp3"
git commit -m "English learning site: Jensen Huang Caltech 2024 Speech"
git branch -M main
git push -u origin main
```

**③ 启用 GitHub Pages**
```bash
gh api repos/gzmdomain/english-learning/pages \
  -X POST \
  -f "build_type=legacy" \
  -f "source[branch]=main" \
  -f "source[path]=/"
```

**部署完成：** https://gzmdomain.github.io/english-learning/

---

## 🎯 网站功能清单

| 功能 | 说明 |
|------|------|
| 🎵 **同步滚动字幕** | 播放时自动高亮当前句，平滑滚动至视窗中央 |
| 📖 **重点词汇高亮** | 45 个难词在字幕中用黄色标注，悬停显示音标 + 中文释义 |
| 📚 **词汇面板** | 右侧边栏列出全部词汇，支持搜索，点击跳转到对应句子 |
| 🔁 **单句循环** | 每句字幕右侧有循环按钮，适合精听跟读 |
| ⏱ **变速播放** | 0.5x / 0.75x / 1x / 1.25x / 1.5x 五档可调 |
| ⏮⏭ **句子导航** | 上一句 / 下一句快速跳转 |
| ↩️↪️ **快退快进** | 前后各 5 秒微调 |
| 🔊 **音量控制** | 滑块 + 静音切换 |
| 📱 **响应式布局** | 手机端自动隐藏词汇面板，底部浮动按钮可展开 |
| ⌨️ **键盘快捷键** | 空格=播放/暂停，←→=前后5秒，↑↓=上下句 |

---

## 📁 项目文件结构

```
C:\miki\English\
├── index.html                                              # 主页面（单文件，内嵌所有代码和数据）
├── Jensen-Huangs-Speech-At-Caltech-2024-Commencement.mp3   # 音频文件（7MB）
├── transcript.json                                         # Whisper 转录的字幕数据
└── build_site.py                                           # 网站生成脚本（含词汇词典）
```

---

## 📱 iPhone 使用方法

1. 用 **Safari** 打开 https://gzmdomain.github.io/english-learning/
2. 点击底部 **分享按钮** (⬆️)
3. 选择 **"添加到主屏幕"**
4. 主屏幕上会出现一个图标，点开即可使用，如同原生 App

---

## 🔧 技术栈

| 组件 | 技术 |
|------|------|
| 语音转文字 | faster-whisper (Whisper base 模型, CPU int8) |
| 前端框架 | 纯 HTML/CSS/JS，无第三方依赖 |
| UI 设计 | NVIDIA 品牌色 (#76b900)，暗色主题 |
| 字体 | Inter (英文) + Noto Sans SC (中文) via Google Fonts |
| 部署 | GitHub Pages (免费静态托管) |
| 版本管理 | Git + GitHub |

---

## 🔄 如何更新内容

**添加新词汇：** 编辑 `build_site.py` 中的 `VOCAB` 字典，然后重新运行：
```bash
python build_site.py
git add index.html && git commit -m "Update vocab" && git push
```

**更换音频：** 替换 MP3 文件，重新运行转录和构建流程即可。

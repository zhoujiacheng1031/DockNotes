# DockNotes

把便签收在屏幕边缘，需要时随手展开。DockNotes 是一款原生 macOS 便签应用，让笔记、待办和提醒待在桌面上，又不会一直挡住工作。

**[下载 DockNotes v0.9.0](https://github.com/zhoujiacheng1031/DockNotes/releases/tag/v0.9.0)** · [查看更新记录](docs/releases/v0.9.0.md)

当前安装包适用于 **Apple Silicon Mac**，需要 **macOS 15 或更高版本**。

## 开始使用

1. 从上方的 Release 页面下载 `DockNotes-macOS-v0.9.0.zip`，解压后把 `DockNotes.app` 移入“应用程序”。
2. 打开 DockNotes，在屏幕边缘新建便签。便签平时显示为侧边标签，点击标签即可查看和编辑；也可以将它展开为独立的桌面便签。
3. 用工作区整理不同项目的便签，或从菜单栏打开任务中心查看所有工作区的待办。

## 主要功能

- **桌面便签：**将标签停靠在屏幕左侧或右侧；调整颜色、字体和透明度，也可以归档到便签库。
- **工作区：**按项目或场景分组，在工作区之间切换、排序或移动便签。
- **任务与提醒：**在便签中记录待办，在任务中心集中查看；支持重复任务、到期通知和每日摘要。
- **导入与备份：**批量导入或导出 Markdown/TXT；可选 Obsidian 归档备份。
- **可选集成：**同步到指定的系统日历，或配置 OpenAI 兼容接口及 Anthropic Messages API。

### 常用快捷键

| 操作 | 快捷键 |
| --- | --- |
| 快速记录 | `⇧⌘Space`，可在设置中更改 |
| 新建便签 | `⌥⌘N` |
| 切换到前 9 个工作区 | `⌥⌘1` 至 `⌥⌘9` |
| 打开设置 | `⌘,` |

## 数据与权限

便签数据保存在本机的 Application Support 目录。系统日历同步、通知和 Obsidian 备份都需要由你在应用中启用；日历同步会先请求系统授权。升级到 v0.9.0 时，旧版便签会进入默认工作区，并保留迁移前备份。

## 从源码构建

需要 macOS 15 或更高版本及 Swift 6 工具链：

```bash
cd macOS
./scripts/build-app.sh
```

构建结果位于 `macOS/build/DockNotes.app`。运行内置自检：

```bash
./build/DockNotes.app/Contents/MacOS/DockNotes --self-test
```

仓库中的 `macOS/` 是原生应用，`prototype/` 是 React/Vite 交互原型，`docs/` 存放产品规划与更新记录。

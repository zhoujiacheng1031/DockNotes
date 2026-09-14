# DockNotes

DockNotes 是一款原生 macOS 桌面便签应用。便签可以收纳在屏幕左侧或右侧，以轻量的侧边标签形式随时访问，也可以展开为独立桌面便签。

## 当前功能

- 屏幕边缘便签栏，支持左右停靠、垂直居中和拖拽排序
- 可见标签数量可设为 1–7 个，超出部分进入“更多便签”列表
- 独立桌面便签、置顶、日期、归档与便签库
- 渐变色、RGB/Hex 自定义颜色、材质、字体和透明度
- 有序列表、待办事项、搜索与听写
- OpenAI 兼容接口与 Anthropic Messages API，可针对当前便签提问并追加结果
- 应用内归档库，以及可选的 Obsidian Markdown/双向链接索引备份
- 简体中文、English 和跟随系统语言
- 本地持久化存储

启用 Obsidian 备份后，DockNotes 会在所选目录写入归档 Markdown，并创建或更新 `DockNotes Archive Index.md` 双向链接索引。

## 下载应用

可从 [GitHub Releases](https://github.com/zhoujiacheng1031/DockNotes/releases/latest) 下载最新的 `DockNotes-macOS.zip`，解压后将 `DockNotes.app` 移入“应用程序”文件夹。

## 目录

- `macOS/`：SwiftUI 原生 macOS 应用
- `prototype/`：React/Vite 交互原型
- `docs/`：产品规格与竞品研究记录

## 构建 macOS 应用

要求 macOS 15 或更高版本，以及 Swift 6 工具链。

```bash
cd macOS
./scripts/build-app.sh
```

生成的应用位于 `macOS/build/DockNotes.app`。

运行内置自检：

```bash
cd macOS
.build/debug/DockNotes --self-test
```

## 运行网页原型

```bash
cd prototype
npm install
npm run dev
```

## 数据说明

DockNotes 的便签数据保存在用户的 Application Support 目录，不会写入或提交到此仓库。

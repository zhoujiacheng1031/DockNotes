# DockNotes

当前版本：**v0.9.0**（macOS 15 或更高版本）。工作区把侧边标签按项目或场景分组；任务中心、提醒和系统日历仍汇总所有工作区。旧版便签会迁移到默认工作区，并保留迁移前备份。

在“偏好设置 → 提醒与计划 → 系统日历”中授权后，可创建专用 `DockNotes` 日历或选择已有的可写日历，再开启同步。普通任务会生成一个 30 分钟事件，重复任务会投影当前实例与未来 7 天计划；若事件在系统日历中被修改或删除，DockNotes 会要求选择“重新同步”或“采用日历更改”，不会静默覆盖。

DockNotes 是一款原生 macOS 桌面便签应用。便签可以收纳在屏幕左侧或右侧，以轻量的侧边标签形式随时访问，也可以展开为独立桌面便签。

## 当前功能

- 屏幕边缘便签栏，支持左右停靠、贴边唤起，以及流畅、可连续使用的拖拽排序
- 工作区标签组，支持即时切换、组内/跨组拖动、`⌥⌘1…9` 快捷切换、管理与安全删除撤销
- 可见标签数量可设为 1–7 个，超出部分进入“更多便签”列表
- 独立桌面便签、可靠置顶、日期、归档与便签库，支持归档和永久删除
- 任务中心集中展示待处理、今天、未来 7 天、即将到期、已逾期和已完成事项
- 重复任务支持每天、工作日、每周、每月及自定义间隔，可完成推进、跳过、单次改期或修改整个系列
- 任务到期本地通知、每日任务摘要，以及通知内完成、稍后提醒和来源跳转
- 提醒时间支持时钟选择，也支持手动输入 12 小时制或 24 小时制时间
- Markdown/TXT 批量导入导出
- 渐变色、RGB/Hex 自定义颜色、材质、字体和透明度
- 有序列表、待办事项、搜索与听写
- OpenAI 兼容接口与 Anthropic Messages API，提供模型预设、自定义模型和持久化配置
- 中性 glass 风格的设置、任务中心、便签库和工作区管理页面；这些窗口可以同时打开
- 应用内归档库，以及可选的 Obsidian Markdown/双向链接索引备份
- 简体中文、English 和跟随系统语言
- 本地持久化存储

启用 Obsidian 备份后，DockNotes 会在所选目录写入归档 Markdown，并创建或更新 `DockNotes Archive Index.md` 双向链接索引。

## 下载应用

从 [v0.9.0 Release](https://github.com/zhoujiacheng1031/DockNotes/releases/tag/v0.9.0) 下载 `DockNotes-macOS-v0.9.0.zip`，解压后将 `DockNotes.app` 移入“应用程序”文件夹。完整更新内容见 [v0.9.0 更新记录](docs/releases/v0.9.0.md)。

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
./scripts/build-app.sh
./build/DockNotes.app/Contents/MacOS/DockNotes --self-test
```

## 运行网页原型

```bash
cd prototype
npm install
npm run dev
```

## 数据说明

DockNotes 的便签数据保存在用户的 Application Support 目录，不会写入或提交到此仓库。

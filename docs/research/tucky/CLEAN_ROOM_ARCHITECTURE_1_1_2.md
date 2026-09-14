# Tucky 1.1.2 洁净室架构蓝图

> 检查日期：2026-09-11  
> 样本：本机 `/Applications/Tucky.app`，版本 1.1.2（build 18）  
> 用途：为 DockNotes 提供独立实现的行为与模块边界；本文不包含 Tucky 私有源码。

## 1. 能恢复与不能恢复的内容

应用包中没有 `.swift`、`.swiftinterface`、`.swiftmodule` 或 `.dSYM`，因此不能恢复开发者的原始工程、注释、变量命名历史或可直接编译的 Swift 源码。发布二进制仍保留了部分 Swift 类型和方法符号，结合实机行为，可以建立可信的结构地图。

DockNotes 只使用以下信息：公开界面行为、系统框架依赖、应用包元数据、可见资源名称及二进制符号名称。实现代码由 DockNotes 独立编写，不复制 Tucky 的机器码、专有图片、字体或文案资源。

## 2. 已确认技术边界

- 原生 Swift 应用，界面由 SwiftUI 与 AppKit 混合实现。
- `NSPanel` 承担 Edge Deck、便签编辑器、Ask Bar、语音 HUD 等浮层。
- 普通 `NSWindow` 承担 Settings 与 Library。
- 本地 SQLite 存储；正文为 AES-GCM 加密 BLOB。
- 使用 Combine 同步窗口控制器与 SwiftUI 状态。
- 使用 Sparkle 更新；另依赖 EventKit、Speech、ScreenCaptureKit、UserNotifications、WebKit、CryptoKit 与 ServiceManagement。

## 3. 从符号恢复的模块地图

```text
AppDelegate
├── DeckManager
│   ├── decks: [DisplayID: DeckController]
│   ├── rebuild()
│   ├── refreshAll()
│   └── focused
├── SettingsWindow
├── LibraryWindow
├── AskBarPanel
└── MicHUDPanel

DeckController (每块显示器一个)
├── DeckModel
├── DeckPanel
│   ├── DeckHostingView
│   ├── DeckContentView
│   └── DeckRootView / FanColumn
├── NoteSheet / NoteSheetPanel
├── layout(for: DeckState)
├── pointerEntered() / pointerExited()
├── expand(noteID) / collapse() / dismiss()
├── collapseToRest() / applyRestingState()
├── noteActivity() / startIdleWatch()
├── installOutsideMonitor()
└── beginPillDrag(with:)

SettingsWindow
├── SettingsModel
│   ├── pane
│   ├── deckStyle / deckScale / edgeWidth
│   ├── onLeftEdge / alwaysShown
│   ├── openOnHover / tabPreview
│   ├── noteSizeIndex / fontSize / markdown
│   └── launchAtLogin / overFullScreen
└── SettingsView
    ├── Shortcuts
    ├── Deck
    ├── Notes
    ├── Connectors
    ├── AI
    └── Updates
```

## 4. Deck 状态机

恢复出的 `DeckState`、`setState(_:)`、`collapseToRest()`、`applyRestingState()`、`pointerEntered()`、`pointerExited()` 与 idle timer 表明 Deck 不是单个布尔值，而是由控制器驱动的状态机。

```text
resting ──pointerEntered──▶ fanned
fanned  ──open note───────▶ noteOpen(noteID)
noteOpen ──Close──────────▶ fanned
fanned  ──pointerExited───▶ resting（延迟）
noteOpen ──outside click──▶ resting（未固定）
noteOpen ──outside click──▶ noteOpen（已固定）
```

实现约束：

1. 每张便签拥有稳定的 `sortOrder`；打开便签只令原槽位为空，后续标签不补位。
2. `DeckLayout` 根据面板高度、单项高度、间距和 More 控件高度计算容量。
3. 超出容量的收起便签进入 `+N`，不通过缩小或挤压标签解决。
4. Settings、Library 和 NoteSheet 是独立窗口；打开 Settings 不得写入 active note 或 deck 展开状态。
5. 外部点击由窗口控制器统一判定，固定便签例外。

## 5. DockNotes 对应实现

| Tucky 边界 | DockNotes 边界 | 当前状态 |
| --- | --- | --- |
| `DeckManager` / `DeckController` | `PanelCoordinator` | 已建立独立窗口协调层 |
| `DeckModel` | `NotesStore.deckState` | 已实现 resting / fanned / noteOpen 状态机与延迟收回 |
| `DeckLayout` | `DeckLayout` / `DeckPlan` | 已按高度计算容量并保留活动槽位 |
| `DeckPanel` | `TransparentPanel` + `DeckWindowView` | 透明无阴影，窗口背景为 clear |
| `NoteSheetPanel` | `TransparentPanel` + `NoteWindowView` | 可成为 key window，支持文本编辑 |
| `SettingsWindow` | 独立 `NSWindow` + `SettingsWindowView` | 不再与便签面板共用生命周期 |

## 6. 后续复刻顺序

1. 补齐 Tucky Deck 设置：样式、尺寸、边缘、检测区、悬停预览、悬停打开、全屏与登录启动；保持展开已完成。
2. 按实机尺寸校准 NoteSheet，并补齐快捷键和右键菜单。
3. 实现独立 Library、Archive、搜索与导入导出。
4. 最后再接入可选 AI、语音和连接器；这些不能影响本地便签主流程。

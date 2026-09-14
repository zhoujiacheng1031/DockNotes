import Foundation

enum L10nKey: String {
    case preferences
    case language
    case systemDefault
    case simplifiedChinese
    case english
    case languageHint
    case opacity
    case expanded
    case collapsed
    case opacityHint
    case saved
    case addTask
    case newNote
    case appearance
    case warmPaper
    case collapse
    case pin
    case archive
    case due
    case savedNow
    case task
    case search
    case dictate
    case plain
    case paper
    case delete
    case close
    case moreNotes
    case customColor
    case dueDate
    case clear
    case findInNote
    case matches
    case askAI
    case aiNotConfigured
    case invalidColor
    case apply
    case material
    case general
    case deck
    case notes
    case generalHint
    case deckHint
    case notesHint
    case noteAppearanceHint
    case deckBehavior
    case keepDeckOpen
    case library
    case allNotes
    case archivedNotes
    case restore
    case noArchivedNotes
    case font
    case fontFamily
    case fontSize
    case fontSystem
    case fontRounded
    case fontSerif
    case fontMonospaced
    case fontHandwriting
    case openOnDesktop
    case returnToEdge
    case unpin
    case gradient
    case solidColor
    case startColor
    case endColor
    case visibleTabs
    case deckPosition
    case leftEdge
    case rightEdge
    case ai
    case aiSettingsHint
    case aiServiceURL
    case aiProvider
    case openAICompatible
    case anthropic
    case aiModel
    case aiAPIKey
    case aiAPIKeyHint
    case aiPrompt
    case send
    case aiResponse
    case openAISettings
    case appendToNote
    case copy
    case archiveSettings
    case archiveSettingsHint
    case obsidianBackup
    case obsidianFolder
    case chooseFolder
    case noFolderSelected
    case obsidianBackupHint
    case lastBackup
    case backupFailed
    case aiInvalidEndpoint
    case aiInvalidResponse
    case aiRequestFailedCode
}

enum L10n {
    private static let zh: [L10nKey: String] = [
        .preferences: "偏好设置",
        .language: "界面语言",
        .systemDefault: "跟随系统",
        .simplifiedChinese: "简体中文",
        .english: "English",
        .languageHint: "仅更改应用界面语言，不会翻译笔记内容。",
        .opacity: "透明度",
        .expanded: "展开状态",
        .collapsed: "收起状态",
        .opacityHint: "分别控制便签展开后与收起为侧边标签时的透明度。",
        .saved: "已保存",
        .addTask: "添加待办事项…",
        .newNote: "新建便签",
        .appearance: "外观",
        .warmPaper: "暖色纸张",
        .collapse: "收起便签",
        .pin: "固定",
        .archive: "归档",
        .due: "日期",
        .savedNow: "已保存 · 刚刚",
        .task: "任务",
        .search: "搜索",
        .dictate: "听写",
        .plain: "纯色",
        .paper: "纸张",
        .delete: "删除",
        .close: "收起",
        .moreNotes: "更多便签",
        .customColor: "自定义颜色",
        .dueDate: "到期日期",
        .clear: "清除",
        .findInNote: "在当前便签中查找",
        .matches: "找到 %d 处",
        .askAI: "询问 AI",
        .aiNotConfigured: "AI 服务尚未配置。便签和其他本地功能不受影响。",
        .invalidColor: "请输入 0–255 的 RGB，或 6 位 Hex 颜色。",
        .apply: "应用",
        .material: "材质",
        .general: "通用",
        .deck: "边缘便签",
        .notes: "便签",
        .generalHint: "控制 DockNotes 的界面语言与基础行为。",
        .deckHint: "调整展开便签和屏幕边缘标签的显示方式。",
        .notesHint: "便签外观以 Tucky 的纯色设计为基础。",
        .noteAppearanceHint: "每张便签可在底部调色板中选择预设色、RGB、Hex 和材质。",
        .deckBehavior: "标签行为",
        .keepDeckOpen: "保持标签展开",
        .library: "便签库",
        .allNotes: "所有便签",
        .archivedNotes: "已归档",
        .restore: "恢复",
        .noArchivedNotes: "还没有归档的便签",
        .font: "字体",
        .fontFamily: "字体样式",
        .fontSize: "字号",
        .fontSystem: "系统",
        .fontRounded: "圆体",
        .fontSerif: "衬线",
        .fontMonospaced: "等宽",
        .fontHandwriting: "手写",
        .openOnDesktop: "展开为桌面便签",
        .returnToEdge: "收回侧边标签",
        .unpin: "取消置顶",
        .gradient: "渐变",
        .solidColor: "纯色",
        .startColor: "起始色",
        .endColor: "结束色",
        .visibleTabs: "可见标签",
        .deckPosition: "停靠位置",
        .leftEdge: "桌面左侧",
        .rightEdge: "桌面右侧",
        .ai: "AI 模型",
        .aiSettingsHint: "支持 OpenAI 兼容接口与 Anthropic Messages API；仅在你主动提问时读取当前便签。",
        .aiServiceURL: "服务地址",
        .aiProvider: "提供商",
        .openAICompatible: "OpenAI 兼容",
        .anthropic: "Anthropic",
        .aiModel: "模型名称",
        .aiAPIKey: "API Key（可选）",
        .aiAPIKeyHint: "API Key 保存在 macOS 钥匙串中，不写入便签文件。",
        .aiPrompt: "询问、总结或改写当前便签…",
        .send: "发送",
        .aiResponse: "AI 回复",
        .openAISettings: "打开 AI 设置",
        .appendToNote: "追加到便签",
        .copy: "复制",
        .archiveSettings: "归档与备份",
        .archiveSettingsHint: "DockNotes 始终保留应用内归档，也可以同步备份为 Obsidian Markdown。",
        .obsidianBackup: "备份到 Obsidian",
        .obsidianFolder: "Vault / 文件夹",
        .chooseFolder: "选择文件夹…",
        .noFolderSelected: "尚未选择文件夹",
        .obsidianBackupHint: "归档时写入 Markdown，并维护 [[DockNotes Archive Index]] 索引。",
        .lastBackup: "最近备份",
        .backupFailed: "备份失败",
        .aiInvalidEndpoint: "AI 服务地址无效。",
        .aiInvalidResponse: "AI 服务返回了无法读取的响应。",
        .aiRequestFailedCode: "AI 请求失败（HTTP %d）。"
    ]

    private static let en: [L10nKey: String] = [
        .preferences: "Preferences",
        .language: "Language",
        .systemDefault: "System Default",
        .simplifiedChinese: "简体中文",
        .english: "English",
        .languageHint: "Changes the app interface only. Note content is never translated.",
        .opacity: "Opacity",
        .expanded: "Expanded note",
        .collapsed: "Collapsed tabs",
        .opacityHint: "Adjust transparency separately for the open note and edge tabs.",
        .saved: "Saved",
        .addTask: "Add a to-do…",
        .newNote: "New note",
        .appearance: "Appearance",
        .warmPaper: "Warm paper",
        .collapse: "Collapse note",
        .pin: "Pin",
        .archive: "Archive",
        .due: "Due",
        .savedNow: "Saved · just now",
        .task: "Task",
        .search: "Find",
        .dictate: "Dictate",
        .plain: "Plain",
        .paper: "Paper",
        .delete: "Delete",
        .close: "Close",
        .moreNotes: "More Notes",
        .customColor: "Custom Color",
        .dueDate: "Due Date",
        .clear: "Clear",
        .findInNote: "Find in Note",
        .matches: "%d matches",
        .askAI: "Ask AI",
        .aiNotConfigured: "No AI provider is configured yet. Notes and other local features still work normally.",
        .invalidColor: "Enter RGB values from 0–255 or a 6-digit Hex color.",
        .apply: "Apply",
        .material: "Material",
        .general: "General",
        .deck: "Edge Deck",
        .notes: "Notes",
        .generalHint: "Control the interface language and core DockNotes behavior.",
        .deckHint: "Adjust the open note and the tabs resting at the screen edge.",
        .notesHint: "Note appearance follows Tucky's quiet, solid-color design.",
        .noteAppearanceHint: "Use the palette under each note for presets, exact RGB or Hex, and material.",
        .deckBehavior: "Behavior",
        .keepDeckOpen: "Keep the deck open",
        .library: "Notes Library",
        .allNotes: "All Notes",
        .archivedNotes: "Archived",
        .restore: "Restore",
        .noArchivedNotes: "No archived notes yet",
        .font: "Font",
        .fontFamily: "Typeface",
        .fontSize: "Size",
        .fontSystem: "System",
        .fontRounded: "Rounded",
        .fontSerif: "Serif",
        .fontMonospaced: "Monospaced",
        .fontHandwriting: "Handwriting",
        .openOnDesktop: "Open as Desktop Note",
        .returnToEdge: "Return to Edge",
        .unpin: "Unpin",
        .gradient: "Gradient",
        .solidColor: "Solid",
        .startColor: "Start Color",
        .endColor: "End Color",
        .visibleTabs: "Visible Tabs",
        .deckPosition: "Dock Side",
        .leftEdge: "Left",
        .rightEdge: "Right",
        .ai: "AI Model",
        .aiSettingsHint: "Use an OpenAI-compatible service or Anthropic Messages API. AI reads the note only when you ask.",
        .aiServiceURL: "Service URL",
        .aiProvider: "Provider",
        .openAICompatible: "OpenAI Compatible",
        .anthropic: "Anthropic",
        .aiModel: "Model",
        .aiAPIKey: "API Key (Optional)",
        .aiAPIKeyHint: "Your API key is stored in macOS Keychain, never in the notes file.",
        .aiPrompt: "Ask, summarize, or rewrite this note…",
        .send: "Send",
        .aiResponse: "AI Response",
        .openAISettings: "Open AI Settings",
        .appendToNote: "Append to Note",
        .copy: "Copy",
        .archiveSettings: "Archive & Backup",
        .archiveSettingsHint: "DockNotes always keeps its local archive and can also back up Obsidian-compatible Markdown.",
        .obsidianBackup: "Back up to Obsidian",
        .obsidianFolder: "Vault / Folder",
        .chooseFolder: "Choose Folder…",
        .noFolderSelected: "No folder selected",
        .obsidianBackupHint: "Writes Markdown on archive and maintains a [[DockNotes Archive Index]] note.",
        .lastBackup: "Last Backup",
        .backupFailed: "Backup Failed",
        .aiInvalidEndpoint: "The AI service URL is invalid.",
        .aiInvalidResponse: "The AI service returned an unreadable response.",
        .aiRequestFailedCode: "AI request failed (HTTP %d)."
    ]

    static func text(_ key: L10nKey, language: AppLanguage) -> String {
        let resolved: AppLanguage
        if language == .system {
            resolved = Locale.preferredLanguages.first?.hasPrefix("zh") == true
                ? .simplifiedChinese
                : .english
        } else {
            resolved = language
        }
        return (resolved == .simplifiedChinese ? zh : en)[key] ?? en[key] ?? key.rawValue
    }
}

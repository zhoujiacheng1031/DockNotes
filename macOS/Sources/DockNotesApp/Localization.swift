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
    case workspaces
    case newWorkspace
    case moveToWorkspace
    case allWorkspaces
    case currentWorkspace
    case manageWorkspaces
    case workspaceName
    case renameWorkspace
    case selectedNotes
    case workspaceDeleted
    case quickCapture
    case quickCaptureHint
    case quickCaptureShortcut
    case shortcutConflict
    case cancel
    case save
    case appearance
    case appearanceSettingsHint
    case warmPaper
    case collapse
    case pin
    case archive
    case due
    case savedNow
    case saving
    case saveFailed
    case task
    case taskCenter
    case taskInbox
    case weekPlan
    case upcoming
    case completed
    case noTasks
    case searchTasks
    case sourceNote
    case unscheduled
    case repeatTask
    case repeatDaily
    case repeatWeekdays
    case repeatWeekly
    case repeatMonthly
    case repeatInterval
    case onlyThisOccurrence
    case entireSeries
    case skipThisOccurrence
    case stopRepeating
    case projectedOccurrence
    case importNotes
    case exportNotes
    case exportMarkdown
    case exportText
    case transferComplete
    case transferFailed
    case search
    case dictate
    case plain
    case paper
    case delete
    case deletedNote
    case undo
    case close
    case moreNotes
    case moreActions
    case customColor
    case dueDate
    case timeInput
    case timeInputHint
    case invalidTime
    case reminderHint
    case reminders
    case reminderSettingsHint
    case notificationPermission
    case notificationsAllowed
    case notificationsDenied
    case notificationsNotRequested
    case notificationsUnknown
    case enableNotifications
    case openNotificationSettings
    case taskReminders
    case taskRemindersHint
    case dailySummary
    case dailySummaryHint
    case dailySummaryTime
    case scheduledNotifications
    case taskReminderBody
    case dailySummaryTitle
    case dailySummaryBody
    case markTaskComplete
    case snoozeFifteenMinutes
    case openTaskCenter
    case today
    case overdue
    case deadlineReached
    case clear
    case findInNote
    case matches
    case searchLibrary
    case titleMatch
    case contentMatch
    case noSearchResults
    case filter
    case sort
    case incomplete
    case recentModified
    case dueFirst
    case newestCreated
    case preview
    case openNote
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
    case bold
    case underline
    case strikethrough
    case highlight
    case fontFamily
    case fontSize
    case fontSystem
    case fontRounded
    case fontSerif
    case fontMonospaced
    case fontHandwriting
    case openOnDesktop
    case returnToEdge
    case moveDesktopNote
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
    case aiConnection
    case recommendedModels
    case customModel
    case saveConfiguration
    case configurationSaved
    case configurationSaveFailed
    case restoreDefault
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
        .workspaces: "工作区",
        .newWorkspace: "新建工作区",
        .moveToWorkspace: "移到工作区",
        .allWorkspaces: "全部工作区",
        .currentWorkspace: "当前工作区",
        .manageWorkspaces: "管理工作区",
        .workspaceName: "工作区名称",
        .renameWorkspace: "重命名工作区",
        .selectedNotes: "已选择便签",
        .workspaceDeleted: "已删除工作区，便签已移到默认工作区",
        .quickCapture: "快速记录",
        .quickCaptureHint: "输入内容后按 ⌘Return 保存",
        .quickCaptureShortcut: "快速记录快捷键",
        .shortcutConflict: "快捷键已被其他应用占用，请选择另一组。",
        .cancel: "取消",
        .save: "保存",
        .appearance: "外观",
        .appearanceSettingsHint: "在一个页面里调整界面、侧边标签与便签显示。",
        .warmPaper: "暖色纸张",
        .collapse: "收起便签",
        .pin: "固定",
        .archive: "归档",
        .due: "截止时间",
        .savedNow: "已保存 · 刚刚",
        .saving: "保存中…",
        .saveFailed: "保存失败 · 点击重试",
        .task: "任务",
        .taskCenter: "任务中心",
        .taskInbox: "待处理",
        .weekPlan: "未来 7 天",
        .upcoming: "即将到期",
        .completed: "已完成",
        .noTasks: "这里还没有任务",
        .searchTasks: "搜索任务与来源便签",
        .sourceNote: "来源便签",
        .unscheduled: "未设置日期",
        .repeatTask: "重复任务",
        .repeatDaily: "每天",
        .repeatWeekdays: "工作日",
        .repeatWeekly: "每周",
        .repeatMonthly: "每月",
        .repeatInterval: "间隔",
        .onlyThisOccurrence: "仅本次",
        .entireSeries: "整个系列",
        .skipThisOccurrence: "跳过本次",
        .stopRepeating: "停止重复",
        .projectedOccurrence: "计划实例",
        .importNotes: "导入",
        .exportNotes: "导出",
        .exportMarkdown: "导出 Markdown",
        .exportText: "导出 TXT",
        .transferComplete: "操作完成",
        .transferFailed: "导入或导出失败",
        .search: "搜索",
        .dictate: "听写",
        .plain: "纯色",
        .paper: "纸张",
        .delete: "删除",
        .deletedNote: "已删除便签",
        .undo: "撤销",
        .close: "收起",
        .moreNotes: "更多便签",
        .moreActions: "更多操作",
        .customColor: "自定义颜色",
        .dueDate: "截止日期与时间",
        .timeInput: "手动输入时间",
        .timeInputHint: "支持 21:30 或 9:30 PM",
        .invalidTime: "请输入有效时间，例如 21:30 或 9:30 PM。",
        .reminderHint: "设置后将在截止时间发送 macOS 本地提醒；首次使用需要允许通知。",
        .reminders: "提醒与计划",
        .reminderSettingsHint: "在任务到期时提醒，并在每天固定时间汇总今天和逾期事项。",
        .notificationPermission: "通知权限",
        .notificationsAllowed: "已允许",
        .notificationsDenied: "已关闭",
        .notificationsNotRequested: "尚未请求",
        .notificationsUnknown: "正在检查…",
        .enableNotifications: "允许通知",
        .openNotificationSettings: "打开系统设置",
        .taskReminders: "任务到期提醒",
        .taskRemindersHint: "任务到期时显示通知，可直接完成、稍后提醒或打开来源便签。",
        .dailySummary: "每日任务摘要",
        .dailySummaryHint: "汇总当天到期和已经逾期的任务；没有待处理任务时不会打扰你。",
        .dailySummaryTime: "摘要时间",
        .scheduledNotifications: "已安排 %d 条提醒",
        .taskReminderBody: "任务到期：%@",
        .dailySummaryTitle: "DockNotes 今日计划",
        .dailySummaryBody: "今天 %d 项 · 已逾期 %d 项",
        .markTaskComplete: "标记完成",
        .snoozeFifteenMinutes: "15 分钟后提醒",
        .openTaskCenter: "打开任务中心",
        .today: "今天",
        .overdue: "已逾期",
        .deadlineReached: "截止时间已到",
        .clear: "清除",
        .findInNote: "在当前便签中查找",
        .matches: "找到 %d 处",
        .searchLibrary: "搜索标题与便签内容",
        .titleMatch: "标题",
        .contentMatch: "正文",
        .noSearchResults: "没有匹配的便签",
        .filter: "筛选",
        .sort: "排序",
        .incomplete: "未完成待办",
        .recentModified: "最近修改",
        .dueFirst: "最早到期",
        .newestCreated: "最新创建",
        .preview: "预览",
        .openNote: "打开便签",
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
        .deckBehavior: "标签收起",
        .keepDeckOpen: "点击桌面后收起标签",
        .library: "便签库",
        .allNotes: "所有便签",
        .archivedNotes: "已归档",
        .restore: "恢复",
        .noArchivedNotes: "还没有归档的便签",
        .font: "字体",
        .bold: "加粗",
        .underline: "下划线",
        .strikethrough: "删除线",
        .highlight: "高亮",
        .fontFamily: "字体样式",
        .fontSize: "字号",
        .fontSystem: "系统",
        .fontRounded: "圆体",
        .fontSerif: "衬线",
        .fontMonospaced: "等宽",
        .fontHandwriting: "手写",
        .openOnDesktop: "展开为桌面便签",
        .returnToEdge: "收回侧边标签",
        .moveDesktopNote: "按住拖动桌面便签",
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
        .aiConnection: "连接配置",
        .recommendedModels: "推荐模型",
        .customModel: "也可以直接输入服务商支持的模型名称",
        .saveConfiguration: "保存 AI 配置",
        .configurationSaved: "配置已保存，API Key 已写入 macOS 钥匙串",
        .configurationSaveFailed: "普通配置已保存，但 API Key 无法写入钥匙串",
        .restoreDefault: "恢复默认地址",
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
        .workspaces: "Workspaces",
        .newWorkspace: "New Workspace",
        .moveToWorkspace: "Move to Workspace",
        .allWorkspaces: "All Workspaces",
        .currentWorkspace: "Current Workspace",
        .manageWorkspaces: "Manage Workspaces",
        .workspaceName: "Workspace Name",
        .renameWorkspace: "Rename Workspace",
        .selectedNotes: "Selected Notes",
        .workspaceDeleted: "Workspace deleted; notes moved to the default workspace",
        .quickCapture: "Quick Capture",
        .quickCaptureHint: "Type a note, then press ⌘Return to save",
        .quickCaptureShortcut: "Quick Capture Shortcut",
        .shortcutConflict: "This shortcut is already in use. Choose another combination.",
        .cancel: "Cancel",
        .save: "Save",
        .appearance: "Appearance",
        .appearanceSettingsHint: "Adjust the interface, edge tabs, and note presentation in one place.",
        .warmPaper: "Warm paper",
        .collapse: "Collapse note",
        .pin: "Pin",
        .archive: "Archive",
        .due: "Deadline",
        .savedNow: "Saved · just now",
        .saving: "Saving…",
        .saveFailed: "Save failed · Retry",
        .task: "Task",
        .taskCenter: "Task Center",
        .taskInbox: "To Do",
        .weekPlan: "Next 7 Days",
        .upcoming: "Upcoming",
        .completed: "Completed",
        .noTasks: "No tasks here yet",
        .searchTasks: "Search tasks and source notes",
        .sourceNote: "Source Note",
        .unscheduled: "No Date",
        .repeatTask: "Repeat Task",
        .repeatDaily: "Daily",
        .repeatWeekdays: "Weekdays",
        .repeatWeekly: "Weekly",
        .repeatMonthly: "Monthly",
        .repeatInterval: "Interval",
        .onlyThisOccurrence: "This Occurrence",
        .entireSeries: "Entire Series",
        .skipThisOccurrence: "Skip This Occurrence",
        .stopRepeating: "Stop Repeating",
        .projectedOccurrence: "Planned occurrence",
        .importNotes: "Import",
        .exportNotes: "Export",
        .exportMarkdown: "Export Markdown",
        .exportText: "Export TXT",
        .transferComplete: "Transfer complete",
        .transferFailed: "Import or export failed",
        .search: "Find",
        .dictate: "Dictate",
        .plain: "Plain",
        .paper: "Paper",
        .delete: "Delete",
        .deletedNote: "Note deleted",
        .undo: "Undo",
        .close: "Close",
        .moreNotes: "More Notes",
        .moreActions: "More Actions",
        .customColor: "Custom Color",
        .dueDate: "Deadline Date & Time",
        .timeInput: "Enter Time",
        .timeInputHint: "Use 21:30 or 9:30 PM",
        .invalidTime: "Enter a valid time, such as 21:30 or 9:30 PM.",
        .reminderHint: "DockNotes sends a local macOS reminder at the deadline. Notification permission is requested the first time.",
        .reminders: "Reminders & Planning",
        .reminderSettingsHint: "Get notified when tasks are due and receive a daily summary of today's and overdue work.",
        .notificationPermission: "Notification Permission",
        .notificationsAllowed: "Allowed",
        .notificationsDenied: "Off",
        .notificationsNotRequested: "Not Requested",
        .notificationsUnknown: "Checking…",
        .enableNotifications: "Allow Notifications",
        .openNotificationSettings: "Open System Settings",
        .taskReminders: "Task Due Reminders",
        .taskRemindersHint: "Complete, snooze, or open the source note directly from a due notification.",
        .dailySummary: "Daily Task Summary",
        .dailySummaryHint: "Summarizes tasks due today and overdue tasks. DockNotes stays quiet when there is nothing pending.",
        .dailySummaryTime: "Summary Time",
        .scheduledNotifications: "%d reminders scheduled",
        .taskReminderBody: "Task due: %@",
        .dailySummaryTitle: "DockNotes Daily Plan",
        .dailySummaryBody: "%d due today · %d overdue",
        .markTaskComplete: "Mark Complete",
        .snoozeFifteenMinutes: "Remind in 15 Minutes",
        .openTaskCenter: "Open Task Center",
        .today: "Today",
        .overdue: "Overdue",
        .deadlineReached: "Deadline reached",
        .clear: "Clear",
        .findInNote: "Find in Note",
        .matches: "%d matches",
        .searchLibrary: "Search titles and note content",
        .titleMatch: "Title",
        .contentMatch: "Content",
        .noSearchResults: "No matching notes",
        .filter: "Filter",
        .sort: "Sort",
        .incomplete: "Incomplete Tasks",
        .recentModified: "Recently Modified",
        .dueFirst: "Due First",
        .newestCreated: "Newest Created",
        .preview: "Preview",
        .openNote: "Open Note",
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
        .deckBehavior: "Collapse Labels",
        .keepDeckOpen: "Collapse labels after clicking the desktop",
        .library: "Notes Library",
        .allNotes: "All Notes",
        .archivedNotes: "Archived",
        .restore: "Restore",
        .noArchivedNotes: "No archived notes yet",
        .font: "Font",
        .bold: "Bold",
        .underline: "Underline",
        .strikethrough: "Strikethrough",
        .highlight: "Highlight",
        .fontFamily: "Typeface",
        .fontSize: "Size",
        .fontSystem: "System",
        .fontRounded: "Rounded",
        .fontSerif: "Serif",
        .fontMonospaced: "Monospaced",
        .fontHandwriting: "Handwriting",
        .openOnDesktop: "Open as Desktop Note",
        .returnToEdge: "Return to Edge",
        .moveDesktopNote: "Drag to move desktop note",
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
        .aiConnection: "Connection",
        .recommendedModels: "Recommended models",
        .customModel: "You can also enter any model name supported by your provider",
        .saveConfiguration: "Save AI Configuration",
        .configurationSaved: "Settings saved; API key stored in macOS Keychain",
        .configurationSaveFailed: "Settings were saved, but the API key could not be stored in Keychain",
        .restoreDefault: "Restore Default URL",
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

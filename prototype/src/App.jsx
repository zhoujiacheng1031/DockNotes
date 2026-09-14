import { useEffect, useMemo, useState } from "react";
import {
  Archive,
  CalendarBlank,
  Check,
  CheckSquare,
  DotsThree,
  GearSix,
  GraduationCap,
  Lightbulb,
  ListChecks,
  MagnifyingGlass,
  Minus,
  NotePencil,
  Palette,
  Plus,
  PushPin,
  SlidersHorizontal,
  SquaresFour,
  Translate,
  UsersThree,
  WifiHigh,
  X,
} from "@phosphor-icons/react";

const COPY = {
  zh: {
    app: "DockNotes", file: "文件", edit: "编辑", view: "显示", note: "便签",
    window: "窗口", help: "帮助", due: "9月12日", addItem: "添加待办事项…",
    saved: "已保存", language: "界面语言", system: "跟随系统",
    chinese: "简体中文", english: "English", settings: "偏好设置",
    langHint: "仅更改应用界面语言，不会翻译笔记内容。",
    opacity: "透明度", expanded: "展开状态", collapsed: "收起状态",
    opacityHint: "分别控制便签展开后与收起为侧边标签时的透明度。",
    appearance: "外观", warmPaper: "暖色纸张", close: "关闭设置",
    newNote: "新建便签", collapse: "收起便签", open: "展开便签",
  },
  en: {
    app: "DockNotes", file: "File", edit: "Edit", view: "View", note: "Note",
    window: "Window", help: "Help", due: "Sep 12", addItem: "Add a to-do…",
    saved: "Saved", language: "Language", system: "System Default",
    chinese: "简体中文", english: "English", settings: "Preferences",
    langHint: "Changes the app interface only. Note content is never translated.",
    opacity: "Opacity", expanded: "Expanded note", collapsed: "Collapsed tabs",
    opacityHint: "Adjust transparency separately for the open note and edge tabs.",
    appearance: "Appearance", warmPaper: "Warm paper", close: "Close preferences",
    newNote: "New note", collapse: "Collapse note", open: "Open note",
  },
};

const INITIAL_NOTES = [
  {
    id: 1,
    title: "发布前清单",
    accent: "#e6b538",
    icon: ListChecks,
    items: [
      { id: 1, text: "检查中英文文案", done: true },
      { id: 2, text: "Export Markdown", done: false },
      { id: 3, text: "确认离线可编辑", done: false },
    ],
  },
  { id: 2, title: "灵感收集", accent: "#dc8f72", icon: Lightbulb, items: [] },
  { id: 3, title: "会议记录", accent: "#7ead94", icon: UsersThree, items: [] },
  { id: 4, title: "学习笔记", accent: "#7193bb", icon: GraduationCap, items: [] },
];

function readNumber(key, fallback) {
  const value = Number(localStorage.getItem(key));
  return Number.isFinite(value) && value >= 20 && value <= 100 ? value : fallback;
}

function resolveLanguage(choice) {
  if (choice === "system") {
    return navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en";
  }
  return choice;
}

function DockIcon({ children, label }) {
  return (
    <button className="dock-icon" type="button" aria-label={label} title={label}>
      {children}
    </button>
  );
}

export function App() {
  const [notes, setNotes] = useState(INITIAL_NOTES);
  const [activeId, setActiveId] = useState(1);
  const [isExpanded, setIsExpanded] = useState(true);
  const [settingsOpen, setSettingsOpen] = useState(true);
  const [languageChoice, setLanguageChoice] = useState(
    () => localStorage.getItem("docknotes-language") || "zh",
  );
  const [expandedOpacity, setExpandedOpacity] = useState(() =>
    readNumber("docknotes-expanded-opacity", 96),
  );
  const [collapsedOpacity, setCollapsedOpacity] = useState(() =>
    readNumber("docknotes-collapsed-opacity", 82),
  );

  const language = resolveLanguage(languageChoice);
  const t = COPY[language];
  const activeNote = notes.find((note) => note.id === activeId) || notes[0];

  useEffect(() => localStorage.setItem("docknotes-language", languageChoice), [languageChoice]);
  useEffect(
    () => localStorage.setItem("docknotes-expanded-opacity", String(expandedOpacity)),
    [expandedOpacity],
  );
  useEffect(
    () => localStorage.setItem("docknotes-collapsed-opacity", String(collapsedOpacity)),
    [collapsedOpacity],
  );

  const dateLabel = useMemo(
    () =>
      new Intl.DateTimeFormat(language === "zh" ? "zh-CN" : "en-US", {
        month: "short",
        day: "numeric",
        weekday: "short",
      }).format(new Date()),
    [language],
  );

  function selectNote(id) {
    if (id === activeId) {
      setIsExpanded((value) => !value);
      setSettingsOpen(false);
      return;
    }
    setActiveId(id);
    setIsExpanded(true);
    setSettingsOpen(false);
  }

  function toggleItem(itemId) {
    setNotes((current) =>
      current.map((note) =>
        note.id !== activeId
          ? note
          : {
              ...note,
              items: note.items.map((item) =>
                item.id === itemId ? { ...item, done: !item.done } : item,
              ),
            },
      ),
    );
  }

  function addItem() {
    setNotes((current) =>
      current.map((note) =>
        note.id !== activeId
          ? note
          : {
              ...note,
              items: [
                ...note.items,
                {
                  id: Date.now(),
                  text: language === "zh" ? "新的待办事项" : "New to-do item",
                  done: false,
                },
              ],
            },
      ),
    );
  }

  function addNote() {
    const id = Date.now();
    setNotes((current) => [
      ...current,
      {
        id,
        title: language === "zh" ? "新便签" : "New note",
        accent: "#d8b978",
        icon: NotePencil,
        items: [],
      },
    ]);
    setActiveId(id);
    setIsExpanded(true);
    setSettingsOpen(false);
  }

  const alpha = Math.max(0.2, expandedOpacity / 100);
  const ActiveEmptyIcon = activeNote.icon;

  return (
    <main className="desktop">
      <header className="menu-bar">
        <div className="menu-left">
          <span className="brand-mark" aria-hidden="true">DN</span>
          <strong>{t.app}</strong>
          <span>{t.file}</span><span>{t.edit}</span><span>{t.view}</span>
          <span>{t.note}</span><span>{t.window}</span><span>{t.help}</span>
        </div>
        <div className="menu-right">
          <WifiHigh size={18} weight="bold" />
          <MagnifyingGlass size={18} weight="bold" />
          <SlidersHorizontal size={18} weight="bold" />
          <span>{dateLabel}</span><strong>10:24</strong>
        </div>
      </header>

      <section className="workspace" aria-label="DockNotes desktop preview">
        {isExpanded && (
          <article className="note-sheet" style={{ opacity: alpha, "--note-accent": activeNote.accent }}>
            <header className="note-toolbar">
              <div className="note-title-wrap">
                <span className="note-dot" />
                <input
                  className="note-title"
                  value={activeNote.title}
                  onChange={(event) =>
                    setNotes((current) =>
                      current.map((note) =>
                        note.id === activeId ? { ...note, title: event.target.value } : note,
                      ),
                    )
                  }
                  aria-label="Note title"
                />
              </div>
              <div className="note-actions">
                <button className="date-chip" type="button"><CalendarBlank size={20} />{t.due}</button>
                <button className="icon-button" type="button" aria-label="Pin"><PushPin size={22} /></button>
                <span className="toolbar-divider" />
                <button className="icon-button" type="button" aria-label="Archive"><Archive size={22} /></button>
                <button
                  className={`icon-button ${settingsOpen ? "is-active" : ""}`}
                  type="button"
                  aria-label={t.settings}
                  onClick={() => setSettingsOpen((value) => !value)}
                >
                  <DotsThree size={25} weight="bold" />
                </button>
                <button
                  className="icon-button collapse-button"
                  type="button"
                  aria-label={t.collapse}
                  onClick={() => { setIsExpanded(false); setSettingsOpen(false); }}
                >
                  <Minus size={20} weight="bold" />
                </button>
              </div>
            </header>

            <div className="note-content">
              {activeNote.items.length ? (
                <div className="checklist">
                  {activeNote.items.map((item) => (
                    <button
                      className={`check-row ${item.done ? "is-done" : ""}`}
                      type="button"
                      key={item.id}
                      onClick={() => toggleItem(item.id)}
                    >
                      {item.done ? <CheckSquare size={28} weight="fill" /> : <span className="empty-check" />}
                      <span>{item.text}</span>
                    </button>
                  ))}
                  <button className="add-row" type="button" onClick={addItem}>
                    <span className="add-circle"><Plus size={20} weight="bold" /></span>
                    <span>{t.addItem}</span>
                  </button>
                </div>
              ) : (
                <div className="empty-note">
                  <ActiveEmptyIcon size={38} weight="duotone" />
                  <p>{language === "zh" ? "在这里开始记录…" : "Start writing here…"}</p>
                  <button type="button" onClick={addItem}><Plus size={18} />{t.addItem}</button>
                </div>
              )}
            </div>
            <footer className="saved-status"><span className="saved-dot" />{t.saved}</footer>
          </article>
        )}

        {settingsOpen && isExpanded && (
          <aside className="settings-popover" aria-label={t.settings}>
            <header className="settings-header">
              <div><span className="eyebrow">DockNotes</span><h2>{t.settings}</h2></div>
              <button className="popover-close" type="button" aria-label={t.close} onClick={() => setSettingsOpen(false)}>
                <X size={18} weight="bold" />
              </button>
            </header>

            <section className="setting-section">
              <h3><Translate size={18} />{t.language}</h3>
              <div className="language-options">
                {[
                  ["system", t.system],
                  ["zh", t.chinese],
                  ["en", t.english],
                ].map(([value, label]) => (
                  <label key={value} className="radio-row">
                    <input
                      type="radio"
                      name="language"
                      value={value}
                      checked={languageChoice === value}
                      onChange={() => setLanguageChoice(value)}
                    />
                    <span className="radio-control">{languageChoice === value && <span />}</span>
                    <span>{label}</span>
                  </label>
                ))}
              </div>
              <p>{t.langHint}</p>
            </section>

            <section className="setting-section opacity-section">
              <h3><Palette size={18} />{t.opacity}</h3>
              <OpacityControl label={t.expanded} value={expandedOpacity} onChange={setExpandedOpacity} />
              <OpacityControl label={t.collapsed} value={collapsedOpacity} onChange={setCollapsedOpacity} />
              <p>{t.opacityHint}</p>
            </section>

            <section className="appearance-row">
              <div><span>{t.appearance}</span><small>{t.warmPaper}</small></div>
              <span className="paper-swatch"><Check size={14} weight="bold" /></span>
            </section>
          </aside>
        )}

        <nav className="edge-rail" aria-label="Notes" style={{ opacity: collapsedOpacity / 100 }}>
          {notes.map((note) => {
            const Icon = note.icon;
            return (
              <button
                type="button"
                className={`edge-tab ${note.id === activeId ? "is-active" : ""}`}
                style={{ "--tab-color": note.accent }}
                key={note.id}
                onClick={() => selectNote(note.id)}
                aria-label={note.id === activeId && isExpanded ? t.collapse : t.open}
                title={note.title}
              >
                <Icon size={18} weight="duotone" /><span>{note.title}</span>
              </button>
            );
          })}
          <button className="edge-add" type="button" onClick={addNote} aria-label={t.newNote}>
            <Plus size={24} />
          </button>
        </nav>
      </section>

      <nav className="app-dock" aria-label="Desktop apps">
        <DockIcon label="Files"><SquaresFour size={27} weight="duotone" /></DockIcon>
        <DockIcon label="Notes"><NotePencil size={27} weight="duotone" /></DockIcon>
        <DockIcon label="Tasks"><ListChecks size={27} weight="duotone" /></DockIcon>
        <DockIcon label="Calendar"><CalendarBlank size={27} weight="duotone" /></DockIcon>
        <DockIcon label="People"><UsersThree size={27} weight="duotone" /></DockIcon>
        <span className="dock-divider" />
        <DockIcon label={t.settings}><GearSix size={27} weight="duotone" /></DockIcon>
      </nav>
    </main>
  );
}

function OpacityControl({ label, value, onChange }) {
  return (
    <label className="opacity-control">
      <span><span>{label}</span><output>{value}%</output></span>
      <input
        type="range"
        min="20"
        max="100"
        step="1"
        value={value}
        onChange={(event) => onChange(Number(event.target.value))}
      />
    </label>
  );
}

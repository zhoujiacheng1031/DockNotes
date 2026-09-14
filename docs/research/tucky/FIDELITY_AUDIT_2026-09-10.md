# DockNotes ↔ Tucky 忠实度审查（2026-09-10）

## 审查范围

- 产品表面：Edge Deck、便签展开/收起、设置窗口。
- 用户目标：像 Tucky 一样从屏幕边缘安静地找回便签，设置与便签互不干扰。
- 证据：本轮本机 Tucky 实机画面、用户提供的 DockNotes 截图、修改前 DockNotes 实机画面。

## 对照画面

1. Tucky Edge Deck：[`10-live-edge-deck.png`](screenshots/10-live-edge-deck.png)
2. Tucky 展开便签：[`11-live-note-editor.png`](screenshots/11-live-note-editor.png)
3. Tucky 独立设置：[`13-live-settings-shortcuts.png`](screenshots/13-live-settings-shortcuts.png)
4. DockNotes 修改前便签：[`24-docknotes-before-note.png`](screenshots/24-docknotes-before-note.png)
5. DockNotes 修改前 Edge Deck：[`25-docknotes-before-deck.png`](screenshots/25-docknotes-before-deck.png)

## 结论

修改前的 DockNotes 只复刻了“彩色便签”这个表象，没有复刻 Tucky 的窗口边界、安静程度和渐进披露关系。最大问题不是装饰，而是设置被嵌入便签、边缘标签露出过宽、按钮过黑、颜色过饱和，以及窗口外点击没有状态转换。

## 分步健康度

1. **Edge Deck 静止态 — 修改前不健康。** 标签约露出 38px，深色控制按钮抢眼；Tucky 约露出 20–22px，使用低饱和彩色标签和浅色圆形按钮。已把 DockNotes 改为 22px、108px 标签高度、低饱和 8 色与浅色控制按钮。
2. **打开与切换便签 — 修改前一般。** 内容能切换，但窗口突然出现。已加入从屏幕边缘滑入/滑出的短 ease-out 动画，并按便签 ID 做内容过渡。
3. **点击外部 — 修改前不健康。** 没有任何外部点击监听。已加入本地与全局鼠标命中检测；未固定便签收起，固定便签保留。
4. **打开设置 — 修改前不健康。** 设置与便签共享窗口并强制展开活动便签。已拆为 620×470 独立设置窗口，打开设置不再修改便签展开状态。
5. **中英文设置 — 修改前不健康。** 286px 浮层使英文分段控件与标签换行。独立窗口使用固定表单列宽，中文与英文均保持单行。

## 可访问性风险与限制

- 标签、按钮和设置页已有可访问名称，设置页使用系统控件。
- Edge Deck 实际只露出 22px，符合低干扰目标，但鼠标目标宽度较窄；后续应像 Tucky 一样加入独立的透明检测区和悬停展开，而不是扩大可见标签。
- 本轮最终构建后的 GUI 复验被 macOS 锁屏阻断；自动状态回归已通过，但窗口外点击仍需在解锁后做最后一次真实点击验证。

## 后续美观基线

- 先匹配 Tucky 的尺寸、颜色、字体、间距、窗口层级和动效，再添加 DockNotes 定制能力。
- 定制能力放在次级入口，不挤压 Tucky 的核心编辑器层级。
- 不再把“异形、强阴影、深色底板”当作高级感来源；DockNotes 的高级感应来自克制、轻量和稳定。

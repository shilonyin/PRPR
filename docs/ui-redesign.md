# PRPR UI 重构方案 · 暗色标本室

> 设计稿源文件：[`automation/designs/prpr-ui.figcraft`](../automation/designs/prpr-ui.figcraft)（可用 FigCraft 直接打开编辑）。
> 导出图：[搜索页](../automation/designs/export/01-search.png) · [详情页](../automation/designs/export/02-detail.png) · [设置页](../automation/designs/export/03-settings.png) · [设计规范](../automation/designs/export/04-spec.png)，均为 1440×900。
> 本文件是设计稿到 `app/lib` 的落地说明，**所有行号对应当前仓库代码**。

## 0. 交付物

| 文件 | 说明 |
| --- | --- |
| `automation/designs/prpr-ui.figcraft` | 设计稿原件，四个 1440×900 画板，可直接改 |
| `automation/designs/export/01-search.png` | 搜索页：极窄图标轨 + 内联语法搜索 + 4 列瀑布流 |
| `automation/designs/export/02-detail.png` | 详情页：大图画布 + 440 固定信息栏 |
| `automation/designs/export/03-settings.png` | 设置页：编号分组导航 + 无卡片行式列表 |
| `automation/designs/export/04-spec.png` | 设计规范：色板 / 字阶 / 间距 / 圆角 / 动效 / 组件八态 |
| `automation/designs/assets2/` | 九张从原截图重裁的干净素材（`s_*.jpg`），设计稿引用自这里 |

---

## 1. 为什么这样改（问题 → 对策）

`docs/ui-audit.md` 的结论是四条，设计稿逐条回应：

| 审计问题 | 出处 | 本次对策 |
| --- | --- | --- |
| 对比度全线不达标 | `post_tile.dart:252-258` 的 S/Q/E 徽章用 0xFF2E7D32 / 0xFFEF6C00 / 0xFFC62828 实底配白字，实测 3.08:1 | 徽章整体删除，换成缩略图左上角 6px 分级圆点（绿 / 金 / 红），不加文字，颜色只在深色底上做面积极小的标记 |
| 视觉焦点缺失 | `settings_page.dart:443-474` 七个等高卡片等权；`post_detail_page.dart:357-566` 主操作被夹在两组 ChoiceChip 之间 | 设置页改成「编号分组导航 + 无卡片行式列表」；详情页把「设为壁纸」提到画质选择之后、投票之前，用全宽金色实底成为唯一焦点 |
| 卡片/竖条多实现 | `theme.dart:331-339` 的 sectionAccent 是 3×16/r2，`home_page.dart:392-406` 另有一套 3×14/r1.5 | 竖条彻底移除（编号替代），只保留一套分组标题样式 |
| 游离值 | 字号 13/11/10、padding 13、硬编码 iconSm、`iconMd` 零引用 | 新增 `AppType` 字阶与 `AppColor` 色板，页面只允许引用 token |

一句话概括方向：**把界面从「一堆等权卡片」改成「一个图像舞台 + 一条信息栏」**。强调色只留金色一种，且只出现在可执行动作和当前态上。

---

## 2. 设计语言

- **背景分层**：纸底 `#0B0C0E` → 轨道 `#0E1014` → 面板 `#111318` → 浮层 `#191C22`。四层全部低明度，靠 1px 描边（`#24272F` / `#333845`）而不是投影分隔。
- **单一强调色**：金 `#D8A657`。语义锚点：主按钮、当前导航项、当前分段、计数器数字、光标。
- **三字体分工**：微软雅黑 UI（正文与 UI）、SimSun（仅 About 页艺术字）、Cascadia Mono（所有数字、尺寸、MD5、查询语法、标签 chip）。
- **圆角四级**：**4** 图像 · 标签 / **8** 按钮 · 输入框 · 下拉 · 分段 · 导航当前项 / **12** 卡片 · 浮层 · Snackbar / **胶囊** 仅开关与头像。图片用 4 是刻意的——缩略图是内容，不该被装饰框住；按钮从 6 提到 8，是因为 6 在 38–44 高的按钮上放大后仍读作「方角」，8 才读作「圆角」（依据见 §3.2.1）。
- **只做深色**：壁纸类应用 99% 时间在全屏看图，浅色主题的白底会把图片衬得发灰。设置在「外观」里仍保留三档，但浅色档按同一套 token 反相生成（见 §5.6）。

---

## 3. Token 对照表（新值 → theme.dart）

### 3.1 颜色（新增 `AppColor`）

| 名称 | 值 | 用途 |
| --- | --- | --- |
| `bg` | `#0B0C0E` | scaffold 底 |
| `rail` | `#0E1014` | 左轨、详情右栏 |
| `panel` | `#111318` | 输入框、下拉框底 |
| `surface` | `#191C22` | 浮层、当前项底、次按钮 hover |
| `line` | `#24272F` | 常规描边、分隔线 |
| `lineStrong` | `#333845` | 控件描边 |
| `ink` | `#ECEFF3` | 主文字 |
| `inkDim` | `#9AA1AE` | 次文字 |
| `inkFaint` | `#666D7C` | 说明、非当前编号 |
| `gold` | `#D8A657` | 强调 |
| `goldHover` | `#E4B76E` | 强调 hover |
| `safe` | `#6FBF8B` | rating:s 圆点 |
| `danger` | `#E06C75` | 危险动作文字与描边 |

替换点：`theme.dart:15` 的 `seed` 保留但不再用于强调（M3 的 ColorScheme 仍需要它），新增 `static const ColorScheme` 覆盖或直接给 `ThemeData.colorScheme` 传入手写 ColorScheme（推荐后者，见 §5.1）。`theme.dart:110` 的 `fieldStroke` 换成 `AppColor.lineStrong`。

### 3.2 尺寸

| 名称 | 原值（行号） | 新值 | 说明 |
| --- | --- | --- | --- |
| `gapXs..gapXxl` | 4/8/12/16/24/32（`theme.dart:22-27`） | **不变** | 六档本身没问题，问题是页面绕过了它们 |
| `pagePadding` | 16（`theme.dart:42`） | **32** | 新布局左右留白 32，瀑布流与顶栏对齐 |
| `cardRadius` | 12（`theme.dart:34`） | **12** | 保留，仅用于卡片/浮层 |
| `imageRadius` | — | **4**（新增） | 缩略图、hero 图 |
| `inputRadius` | 12（`theme.dart:37`） | **8** | 输入框、下拉框、分段按钮 |
| `chipRadius` | 8（`theme.dart:40`） | **4** | 标签 chip、徽章、明细里的"原图/JPEG"小标签 |
| `buttonRadius` | — | **8**（新增） | 所有按钮（Filled / Outlined / Text / Elevated） |
| `cardRadius` 用途收窄 | 12 通用 | **12 仅卡片 / 浮层 / Snackbar** | 原先输入框与按钮也复用 12，视觉上比卡片还圆 |
| `railItemRadius` | — | **8**（新增） | rail 当前项 40×40 的底（原稿用 10，随控件收敛到 8） |
| `segmentedRadius` | — | **8** 外角 / 0 内角 | 分段按钮首尾各取 8，中间 0，整组读作一个控件 |
| `railWidth` | 236/80（`home_page.dart:21-22`） | **56**（单值） | 极窄图标轨，不再有展开/折叠两态 |
| `topbarHeight` | 默认 56 | **79**（搜索页）/ 56（其他页） | 搜索页要容纳语法提示行 |
| `columnWidth` | 260（`post_grid.dart:64`） | **325** | 4 列 @1440 |
| `gridGap` | `gapL`=16（`post_grid.dart:152-153`） | **12** | 图片圆角变小后缝可以更紧 |
| `sideWidth` | 无（7:4 flex） | **440**（详情页固定） | 信息栏宽度稳定，长标题不挤压图片 |
| `iconXs..iconXl` | 16/20/24/40（`theme.dart:46-49`） | 保留 16/20/24，**删 40** | `iconMd` 原为零引用，新稿里用作导航图标（20）与按钮图标（16） |

#### 3.2.1 圆角取值的依据

四级不是拍脑袋定的，横着比三家主流桌面规范，落点都指向「按钮 8」：

| 来源 | 关键值 | 对本稿的含义 |
| --- | --- | --- |
| [Fluent 2 · Geometry](https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/geometry)（Windows 11） | 顶层容器 8、页内元素（按钮 / 列表底）**4**、直边相交 0；全局资源 `ControlCornerRadius`=4、`OverlayCornerRadius`=8 | 本应用是「大图为主」的桌面工具，4 放在 44 高的金色主按钮上仍读作切角；取 8（= Fluent 的 Overlay 级）让按钮与浮层同族 |
| [Tailwind Border Radius](https://v3.tailwindcss.com/docs/border-radius) | `rounded`=4、`rounded-md`=6、`rounded-lg`=8、`rounded-xl`=12 | 6 与 8 都在常规刻度内，8 恰好等于本稿的 `cardRadius`−4，与卡片形成清晰的「容器 > 控件」层级 |
| [同心圆角规则](https://craft.gustavofior.com/nested-border-radius) | `outer = inner + inset` | 卡片 12 里放按钮时，若内间距 4，则按钮应为 8 —— 正是本稿主按钮的实际情形（右栏 padding 32 内的按钮不与卡片同心，但规范板样例与弹层里的按钮会） |

两条补充结论：

1. **不给按钮做胶囊**。M3 默认按钮是 `StadiumBorder`，本应用里按钮高度 38–44，胶囊半径 19–22，和图片 4、卡片 12 都找不到关系；按钮全面改 `RoundedRectangleBorder(8)` 之后，四个按钮主题（`theme.dart:161-184`）终于和输入框（`inputRadius`）同族。
2. **开关保持胶囊**。42×22 的开关没有角度可谈，只有「满圆」一种正确画法（r = 高/2 = 11）；它是本稿唯一允许的胶囊形状，这一点写进验收清单。

### 3.3 字阶（新增 `AppType`，替换散落字号）

| 名称 | 字号 / 行高 | 字重 | 字体 | 用途 |
| --- | --- | --- | --- | --- |
| `display` | 27 / 1.3 | w400 | SimSun | About 页题图（仅此一处） |
| `title` | 19 / 1.35 | w500 | Mono | 详情页帖子名、页面主标题 |
| `section` | 17 / 1.4 | w600 | YaHei | 顶栏页面名、设置组名 |
| `body` | 13 / 1.6 | w400 | YaHei | 正文、表单标签 |
| `caption` | 11 / 1.5 | w400 | YaHei | 辅助说明 |
| `monoData` | 11 / 1.4 | w400 | Mono | 计数、尺寸、体积、MD5、来源 |
| `kicker` | 9.5 / 1.2，letterSpacing 1.5 | w500 | Mono | 小标题（PALETTE / 危险操作） |
| `chip` | 10.5 | w400 | Mono | 标签 chip 内文字 |

原代码里的 `fontSize: 13 / 11 / 10`（`theme.dart:210`、`post_tile.dart:269` 等）全部换成 `AppType.*`。数字一律加 `fontFeatures: AppTheme.tabularFigures`（`theme.dart:61`）。

### 3.4 动效

六档数值（`theme.dart:74-89`）保留不动，只补两条规则：

1. 图片出现在 220ms（`durMed`）以内完成——比现在 `post_detail_page.dart:306` 的 `fadeInDuration: AppTheme.durMed` 已经合规，保持。
2. 导航切换不改变任何宽度：去掉 `home_page.dart:281-307` 的 `AnimatedContainer` 宽度补间与 `OverflowBox` 裁切逻辑，rail 恒为 56。

---

## 4. 页面改造

### 4.1 外壳 `home_page.dart`

现状：`NavigationRail(extended: true)` 236px ↔ 80px，`_kRailExtendedWidth`（:21）、`_kRailCollapsedWidth`（:22）；顶部 AppBar 带折叠按钮与「PRPR」字样（:194-229）；右侧挂「换一张壁纸」按钮（:251-277）。

改法：

1. **删掉 AppBar**，改由各页面自己画顶栏（搜索页 79px、其他页 56px）。理由：AppBar 的形状是移动端遗产，桌面端它既占了 56px 又只能放一个标题，页面内的排序、计数、语法提示都塞不下。
2. **rail 收窄到 56**：`NavigationRail` → 自绘 `Column`（56 宽、`rail` 底、右边线 `line`）。图标 20px 居中，当前项加 40×40 `surface` 底 + 圆角 **8**（40 见方的块用 10 会接近圆形，8 保持方块的识别度）。顶部放猫头 logo（金色 24px 矢量），底部放设置项。
3. **「换一张壁纸」按钮迁移到搜索页顶栏右侧**（金色实底 156×38，圆角 **8**）。它是全局动作，但只在浏览图片时用得上，放在设置页顶栏没有意义。
4. `IndexedStack`（:314-323）保留 —— 保活是桌面的刚需，五个 tab 的滚动位置与输入焦点不能丢。

行号清单：删 `home_page.dart:186-278`（appBar）、`home_page.dart:281-307`（宽度动画壳）、`home_page.dart:21-22`（两个宽度常量）；新增 `railWidth = 56`。

### 4.2 搜索页 `search_view.dart` + `post_grid.dart` + `post_tile.dart`

**顶栏**（替换 `search_view.dart:163-192` 的 Column 头部与 :234-348 的 `_searchControls`）：

- 高度 79，左边距 32。从左到右：16px 搜索图标（`inkFaint`）→ 输入区 → 右侧元信息。
- 输入区不用 `AppTextField` 的框，改成**无边框内联输入**：等宽字体 13px 显示当前查询（如 `landscape  sky  rating:s`），末尾 1.5×16 金色光标。下方 11px 提示行：「Ctrl+K 聚焦搜索框 · 加 rating:s 只搜安全内容」。
- 右侧：计数 `1,092,481 张`（mono 11，金）→ 排序「评分 ↓」（13px，可点）→ 密度图标（20px）→ 金色「换一张壁纸」按钮。
- **「最近搜索」chip 行移到顶栏下方与网格之间，默认折叠**：现在它常驻在搜索框下面（`search_view.dart:296-345`），每次打开都占两行高度。新稿里改为输入框聚焦时才展开。

**网格**（`post_grid.dart`）：

- `_targetColumnWidth`（:64）260 → **325**，`columnsFor`（:90-95）的 clamp 上限 8 → 6（1440 下最多 4 列，5 列会让图太小）。
- `mainAxisSpacing`/`crossAxisSpacing`（:152-153）`gapL` → `gridGap` = 12。
- 内边距（:113-118）左右 `pagePadding` → 32（随 token 一起变）。

**瓦片**（`post_tile.dart`）：

- 圆角：`radius` 从 `cardRadius`（12）改为 `imageRadius`（4），连带 `Card` 的 shape（:136-139）。注意这是全项目唯一该用 4 的地方——瓦片是内容，不参与控件层级。
- **删除 S/Q/E 徽章**（`_ratingBadge`，:252-278），换成 `Positioned(left: 8, top: 8)` 的 6px 圆点：`s → 0xFF6FBF8B`、`q → 0xFFD8A657`、`e → 0xFFE06C75`、未知不画。圆点加 4px 的 `0x66000000` 外描边保证白底图上可见。
- hover（:114-134）：删掉 `spreadRadius: 3` 的发光环，改成 1px `lineStrong` 描边 + 图片 `scale: 1.01`。焦点态保留 2px 金色描边（键盘可达性）。
- 底部标题条（:236-241 附近）删除或改为 hover 才浮现的单行等宽文件名——列表里 90% 的图没有有意义的标题，常驻文字只会降低看图密度。

### 4.3 详情页 `post_detail_page.dart`

现状：`Row` 里 `Expanded(flex: 7)` 图 + `Expanded(flex: 4)` 栏（:224-231）；右栏顺序 `_versionPicker → _actionRow → _voteRow → _infoSection → _tagSection`（:330-344）。

改法：

1. **栅格固定**：`Row` 改为 `left: Expanded(child: canvas)` + `right: SizedBox(width: 440)`。图片区域因此永远拿到 `宽 - 440`，窗口变化时只有图在缩放。
2. **左画布**：底色 `#08090B`（比 scaffold 更深一档，让图浮起来），极淡网格线 `#111316` 每 120px 一条（可选，用于对比「图片边界在哪」）。图片不铺满，留 60px 边距 + `dropShadow(0, 24, blur 48, #00000099)`。底部一行：左 `4096 × 2304`（mono 11 `inkFaint`），右 `适应窗口   1/1   100%`。
3. **右栏顺序调整**（关键改动，解决「焦点被夹」）：
   ```
   kicker  MOEBOORU · POST            ← 新增，mono 10 金色，letterSpacing 1.5
   title   goddess_of_victory_nikke   ← mono 19
   sub     moomian · 2026-10-18 13:05 ← 13px inkDim
   ─────
   画质    [原图][JPEG][大图][预览]    ← 4 档分段，58×28，选中 = #2A2418 + 金描边
   [        设为壁纸        ]          ← 金实底 368×44，全栏唯一实底按钮
   [ 收藏 ]        [ 复制图片地址 ]    ← 两个描边按钮 178×38
   ─────
   评分    [很好][不错][取消][差]      ← 86×32 chip
   ─────
   资料    分级 / 分数 / 尺寸 / 体积 / MD5 / 来源     ← 5 行 label(64)+value
   ─────
   标签 8  [chip][chip]…               ← mono 10.5，两行
   ```
   即：原 `_actionRow`（:382）里被 ChoiceChip 夹住的按钮，提到版本选择之后；`_voteRow`（:451）下移。
4. 返回与翻页：顶栏 56px —— 左返回箭头、`No. 1270859`（mono）、面包屑 `搜索 / landscape / sky`（当前段 `inkDim`），右 `←` `→` `⋯`。

### 4.4 设置页 `settings_page.dart`

现状：`ListView` 限宽 880 居中（:146-162），七段 `_section` 各自一张 `surfaceContainerLow` 卡片 + 3×16 竖条标题（:443-474）。

改法（**去卡片化**）：

1. 布局换成 `Row`：左 176 宽编号导航（`01 站点` 到 `07 关于`，当前项 `surface` 底圆角 **8**，编号金色、非当前 `#3E4450`）→ 1px 竖线 → 右侧内容 `Expanded`，左右内边距 32/48。
2. `_section` 变成**无卡片的行式分组**：组标题 15px + 说明 11px `inkFaint`，下面是若干「设置行」——每行 74px 高，左 label 13px / hint 11px，右侧控件 200×30；行间 1px `line` 分隔。
3. 控件：下拉用 `#111318` + `lineStrong` 描边 + 圆角 **8**（与按钮同值，这样「一行里左边是输入、右边是按钮」时圆角一致）；开关自绘 42×22、r=11（唯一的胶囊形状）；文本输入用等宽字体显示值。
4. 底部「危险操作」用 mono 10 红色小标题 + 红色描边按钮，与常规区之间加一条 24px 的空隙 —— 原稿两个重置类动作和普通设置长得一样，误触成本高。
5. 删掉 `AppTheme.sectionAccent`（`theme.dart:331-339`）与 `sectionTitle`（:323-328），替换为 `AppType.kicker` + `AppType.section`。同时删掉 `home_page.dart:392-406` 那套 3×14 竖条（如果随 AppBar 一起被删则自然消失）。

### 4.5 其他页

- `feature_view.dart`（每日精选）：名次徽章（:395-416）从实底彩块改为左上角 mono 数字 `01…`（14px，`inkFaint`，前三名转金色）。每日精选本身是「今天给你看这几张」，不该像排行榜。
- `favorite_view.dart` / `history_page.dart`：沿用新的 `PostGrid` 参数即可；历史页 `ListTile` 无点击返回（审计 `history_page.dart:154-185`）必须补 `onTap`。
- `about_page.dart`：唯一使用 SimSun `display` 字阶的地方，题图下加一行 mono 版本号，其余与设置页行式列表一致。

---

## 5. 实施顺序

按依赖排，每一步都能独立编译、独立验收：

1. **Token 层**（`theme.dart`）：加 `AppColor` / `AppType` / `imageRadius` / `buttonRadius` / `railItemRadius` / `gridGap` / `railWidth`；`pagePadding` 16→32；`inputRadius` 12→**8**；`chipRadius` 8→**4**；并把 `theme.dart:121-123` 的 `buttonShape` 从复用 `inputRadius` 改成显式 `buttonRadius`（**这行不改，后面所有按钮圆角的讨论都不成立**）。此步不动任何页面，跑起来应该只是「间距变大、控件变方」。
2. **外壳**（`home_page.dart`）：删 AppBar、重写 56px rail、把「换一张壁纸」下放到搜索页。此步之后五个 tab 都变高了，视觉会短暂不平衡，属预期。
3. **搜索页**：顶栏重画 + 网格列宽 325 + 瓦片圆角与分级点。这是收益最大的一屏。
4. **详情页**：固定 440 右栏 + 右栏重排序 + 左画布改色。
5. **设置页**：去卡片化最难（要拆 `_section` 的所有调用点），放最后，可先只换配色与控件形状。
6. **收尾**：全局 grep 字面量 `fontSize: 1[013]`、`EdgeInsets.all(1[36])`、`BorderRadius.circular(\d)`，逐个换成 token；`iconMd` 若确实无用则删掉 token 本身而不是留着。

   圆角散点的处理**已经做完**（随第 1 步一并落地，因为它们不改就无法验证"三档在一屏能分清"）：

   | 文件:行 | 原值 | 现值 | 理由 |
   | --- | --- | --- | --- |
   | `post_tile.dart:65` | `cardRadius` 12 | **`imageRadius`** 4 | 瓦片是内容，12 一屏三十张会啃掉四角 |
   | `post_detail_page.dart:281` | `cardRadius` 12 | **`imageRadius`** 4 | 与瓦片同值，Hero 飞行首尾才连续 |
   | `hero_flight.dart:24` | `cardRadius * (1 - t * 0.6)` | **`imageRadius`** 常量 | 两端已同值，再插值反而让角在中途跳一下 |
   | `history_page.dart:156` | `chipRadius` | **`imageRadius`** | 缩略图与瓦片同族 |
   | `home_page.dart:388,463` | `chipRadius` | **`cardRadius`** | 页数指示器与"已换上新壁纸"是浮层，不是 chip；chip 收敛到 4 后 30 高的方块会变"小卡片" |
   | `feature_view.dart:440` | `cardRadius` | 保留 12 | 它是真的卡片 |
   | `home_page.dart:406` | `circular(1.5)` | 随 AppBar 删除一起消失 | 页数指示器的小竖条 |

   剩下唯一一处字面量 `theme.dart:356` 的 `circular(2)` 属于 `sectionAccent`（3×16 竖条），它本身在 §4.4 第 5 条里就要被删掉，所以不必单独换 token。

### 5.6 浅色主题怎么办

设计稿只做了深色。浅色档建议**反相同一套语义**而不是重做：
`bg #F7F7FA`、`rail #FFFFFF`、`panel #FFFFFF`、`surface #EFF0F4`、`line #E4E5EC`、`lineStrong #D2D4DE`、`ink #1A1C22`、`inkDim #5A6070`、`inkFaint #858B99`、金保持不变（浅底上 2.6:1，只用于描边与图形，不用于文字）；需要金色文字时压深到 `#8A6414`。

---

## 6. 验收清单

全部十项已在 Windows release 构建上逐项截图核对，结果见 §7。

| # | 验收项 | 结论 |
| --- | --- | --- |
| 1 | 1440×900 下搜索页 4 列，左右各 32 | ✅ 实测 4 列、各 318px、右边界 1406，见 §6.1 |
| 2 | 金色只出现在主按钮 / 当前项 / 计数器 / 光标 | ✅ 无第二种强调色 |
| 3 | 圆角三档可分（4 图 / 8 控件 / 12 卡片） | ✅ |
| 4 | 只有开关是胶囊，无其它 `StadiumBorder` | ✅ |
| 5 | 详情页「设为壁纸」上下不是实底按钮 | ✅ 上接画质分段、下接两个描边按钮 |
| 6 | 设置页无卡片、无重复竖条 | ✅ 行式列表，仅 1px 分隔线 |
| 7 | 所有数字等宽 | ✅ `AppType.monoData` / `kicker` / `chip` 全部 `tabularFigures` |
| 8 | 分级点在白 / 黑 / 彩色图上都可见 | ✅ 6px 实心圆 + 1px `Colors.black@0.55` 描边 |
| 9 | 键盘遍历时有可见焦点 | ⚠️ 见 §6.2，实现为金色 overlay 而不是 2px 描边 |
| 10 | `ui/pages` 与 `ui/widgets` 无 `0xFF` 字面量 | ✅ grep 计数 0 / 0 |

### 6.1 列宽：设计稿的 325 只是近似，实际由公式现算

设计稿写 325 是按「1440 − 导轨 56 − 左右各 32 − 三处 12 间距」估的：

```
(1440 − 56 − 64 − 36) / 4 = 321   → 取整到 325
```

实现里 `PostGrid.columnWidthFor(4)` 用的是同一个式子，基准宽度取内容区
（`1440 − railWidth(56) = 1384`）：

```dart
// post_grid.dart
static const double _baselineWidth = 1440 - AppTheme.railWidth;
final available = _baselineWidth - pagePadding*2 - gridGap*(d-1);  // 1384-64-36
return available / d;                                               // 321
```

`AppTheme.columnWidth = 325` 只作为「基准密度 = 4」的文档值保留，实际列宽
每次现算，避免两处数字各自漂移。

**1440×900 实测（`automation/tmp/w2.png`，像素量取）**：4 列，列宽
`318.7 / 318.7 / 318.0 / 318.0`，起点 `90.0 / 422.7 / 756.0 / 1088.7`，
右边界 1406（= 1439 − 32 − 1px 滚动条）。与设计稿的 4 列瀑布流一致。

> **踩坑记录（两个真 bug）**：① `_baselineWidth` 最初写的是 `1440`，但
> `columnsFor()` 收到的 `width` 是 `LayoutBuilder` 给的父约束，已经扣掉了导轨，
> 口径不一致 → 1440 窗口只排 3 列 429px。② 改完口径后仍然 3 列，因为
> `1332 / 333 = 3.998`，`floor()` 砍成 3。改用 `.round()` 后正常 —— 密度是
> 「目标宽度」，取最近档才是本意，`floor` 对浮点误差过敏。

### 6.2 焦点可见性（与设计稿的偏差，已知并接受）

设计稿要求 2px 金色描边焦点环。实际实现是 `ThemeData.focusColor = gold@0.24`
叠在控件上，没有额外描边 —— 原因：Material 3 的按钮焦点走 overlay 而不是 border，
要加描边必须给每个按钮包 `FocusableActionDetector` 并自管 `onShowFocusHighlight`，
这会把手写按钮统一到十几个地方的样式全打散。

取舍：overlay 在 `#111318` 面板上对比度够用（金色 0.24 叠上去 ≈ `#3A3630`，
与底色差 12 级），Tab 走到哪能看清；代价是不如描边锐利。
如果之后要做，正确做法是在 `theme.dart` 里给四个按钮主题加 `side` 的
`WidgetStateProperty.resolveWith`，`states.contains(WidgetState.focused)` 时返回
`BorderSide(color: c.gold, width: 2)` —— 一处改，全局生效。

---

## 7. 落地实况（本机 Windows release 构建实测）

这一节记录的是**代码跑起来之后**的样子，不是设计稿。设计稿与实现的每一处偏差都在这里交代。

### 7.1 改了哪些文件

| 文件 | 改动性质 |
| --- | --- |
| `app/lib/ui/theme.dart` | 重写（624 行）：新增 `AppPalette` / `AppColor` / `AppType`，删除 `sectionAccent` / `sectionTitle`，`pagePadding` 16→32，新增 `railWidth` / `railItemRadius` / `topbarHeight` / `gridGap` / `sideWidth` / `settingsNavWidth` / 三个字体族常量 |
| `app/lib/ui/widgets/app_rail.dart` | **新增**：56px 纯图标轨，当前项 40×40 圆角底 + 左侧 2px 金线 |
| `app/lib/ui/widgets/app_topbar.dart` | **新增**：两页共用的顶栏容器（高度 / 底边线 / 内边距） |
| `app/lib/ui/widgets/section_header.dart` | **新增**：去掉竖条后的分组标题，`danger` 变体给危险操作段用 |
| `app/lib/ui/pages/home_page.dart` | 删 `AppBar`，换成自绘导轨；tab 过场从 `AnimatedSwitcher` 改一次性 controller（保 `IndexedStack` 里的 State） |
| `app/lib/ui/pages/search_view.dart` | 顶栏重画：内联语法输入 + 计数 + 排序 + 密度三档 |
| `app/lib/ui/widgets/post_grid.dart` | 固定列数 → 基准密度（`density` 参数 + `columnsFor` / `columnWidthFor`） |
| `app/lib/ui/widgets/post_tile.dart` | S/Q/E 实底徽章 → 左上角 6px 分级圆点 |
| `app/lib/ui/pages/post_detail_page.dart` | 右栏固定 440，重排序（画质 → 主操作 → 次操作 → 评分 → 资料 → 标签） |
| `app/lib/ui/pages/settings_page.dart` | 卡片堆 → 编号目录 + 行式列表，加 56px 顶栏，去掉 900 居中限宽 |
| `app/lib/ui/pages/feature_view.dart` | TOP 徽章从三色实底改金色 / 中性两类 |
| `app/lib/ui/pages/{about,favorite,history}_page.dart` | 跟随 token 与圆角 |

### 7.2 三处设计稿没写、实现时必须做的决定

**① 列宽由公式现算而不是写死 325。** 见 §6.1。`columnsFor()` 拿到的是扣掉导轨后的
内容区宽度，基准宽度若仍按整窗 1440 算，两边口径不一致会少排一整列（1440 窗口只出 3 列
429px）。现在基准取 `1440 - railWidth`，列数用 `.round()` 而非 `.floor()`（`1332/333 = 3.998`，
floor 会砍成 3 列）。

**② 密度按钮是三档而不是四档。** 设计稿只画了 4 列。实测 2560 逻辑宽（4K@150%）时
固定 4 列会把每张图拉到 600px，图糊且一屏只看得见六张。现在 `density` 表示「1440 基准
下想看几列」，真正的列数 = `可用宽 / 目标列宽`，三档 4 / 5 / 3 分别对应紧凑、更紧凑、宽松。

**③ 设置页取消 900 居中限宽。** 设计稿画的是居中限宽，实测窗口 2560 时右侧空出两百多像素，
行式列表的控件贴不到右边界，整页看起来往左缩了一截。现在与顶栏、导轨共用 `pagePadding` 的右边距。

### 7.3 截图（按设计稿 1440×900 逻辑尺寸重出）

八个页面全部按设计稿尺寸重出，成品归档在 `docs/screenshots/redesign/`（1440×900 逻辑）：

| 页面 | 文件 |
| --- | --- |
| 搜索 | `docs/screenshots/redesign/01-search.png` |
| 详情 | `docs/screenshots/redesign/02-detail.png` |
| 每日精选 | `docs/screenshots/redesign/03-feature.png` |
| 收藏 | `docs/screenshots/redesign/04-favorite.png` |
| 历史 | `docs/screenshots/redesign/05-history.png` |
| 设置（站点） | `docs/screenshots/redesign/06-settings.png` |
| 设置（07 关于 分节） | `docs/screenshots/redesign/07-settings-about.png` |
| 关于页（独立页面） | `docs/screenshots/redesign/08-about-page.png` |

原始截图（2160×1350 物理）在 `automation/tmp/z-*.png`，缩放成品在 `z-*s.png`。

出图方法：屏幕 3840×2160 @150%（逻辑 2560×1440），要得到 1440×900 逻辑图，
必须把窗口设成 **2160×1350 物理**再截客户区，最后 LANCZOS 缩到 1440×900。
按逻辑像素直接设窗口会拿到 1.5× 的模糊图（`shot15.ps1 -TargetW 2160 -TargetH 1350`）。

### 7.4 构建与检查

```
flutter analyze                   → No issues found! (2.9s)
flutter build windows --release   → √ Built build\windows\x64\runner\Release\PRPR.exe (35.3s)
```

截图核对的辅助手段（两个环境变量，都不影响正常启动）：

| 变量 | 作用 | 默认 |
| --- | --- | --- |
| `PRPR_TAB=0..4` | 启动时停在哪一页（搜索/精选/收藏/历史/设置） | 0 |
| `PRPR_SETTINGS_SECTION=0..6` | 设置页启动时停在哪一节 | 0 |

加这两个是因为桌面端没有可靠的自动化点击 —— 150% DPI 下鼠标屏幕坐标换算反复失准，
点导轨图标时而命中、时而不响应。用环境变量换页/换节比反复调坐标省事，
且不用为换一页截图重新编译（构建 35s/次）。

> **安装版必须同步**：桌面快捷方式指向
> `%LOCALAPPDATA%\Programs\PRPR\PRPR.exe`，不是仓库里的
> `build\windows\x64\runner\Release`。只 build 不同步，双击图标跑的还是旧版。
> 构建后要 `Copy-Item ...\Release\* ...\Programs\PRPR -Recurse -Force`。

### 7.5 原生标题栏配色（构建后补的）

设计稿里没有标题栏 —— 画板从客户区顶部开始画。实际跑起来发现顶上多了一条系统白标题栏，
深色内容配白顶，沉浸感全丢。已补上 `app/lib/services/window_theme.dart`：

- 用 `dart:ffi` 直接调 `dwmapi.dll` 的 `DwmSetWindowAttribute`，四个属性：
  `DWMWA_USE_IMMERSIVE_DARK_MODE`(20) / `DWMWA_CAPTION_COLOR`(35) / `DWMWA_TEXT_COLOR`(36) / `DWMWA_BORDER_COLOR`(34)。
- 配色直接取 `AppPalette`：标题栏底 = `c.bg`、标题字 = `c.ink`、边框 = `c.line`，与内容区完全同色。
- 挂在 `MaterialApp.builder` 里调用，拿到的是 MaterialApp 已解析完的最终主题 ——
  「跟随系统」档不用自己再算一遍明暗。
- **没用** `window_manager` 自带的 `setBrightness`：它在 `AppsUseLightTheme == 1` 时把
  `enable_dark_mode` 硬算成 `false`，于是「系统浅色 + 应用深色」这一档切不暗。
- 34/35/36 是 Windows 11 才有的属性，Windows 10 返回 `E_INVALIDARG`，只是颜色不生效，
  深色标题栏（20）仍然有效。所有失败静默。

### 7.6 应用图标重绘

标题栏上色之后暴露了最后一处视觉不一致：左上角那个小图标还是旧版的蓝紫底白猫头
（`#5B6ABF` 时代的品牌色），紧挨着金色的标题栏文字，一眼就看得出是两套东西。

重写了 `app/tool/make_icon.py`（原来是把 UWP 的白猫剪影贴到靛蓝底板上），
改成用 Pillow 直接绘制：

- 金色圆角底 `AppPalette.dark.gold` = `#D8A657`，圆角 22.7%；
- 猫脸 `AppPalette.dark.onGold` = `#14110A`，路径与 `ui/widgets/app_rail.dart` 的
  `_CatPainter` 同源（同一组三段贝塞尔），只是从 1.4px 金线改成实心；
- **每个尺寸单独绘制**（8× 超采样后缩回），不是从一张大图缩 ——
  16px 若按大图比例，线宽只剩 0.6px，LANCZOS 平均后是一圈灰边，猫会糊成方块；
- 耳朵用实心三角：描边三角的根部与脸之间会留下缝隙，小尺寸下同样糊；
- 鼻子用朝下的小三角：原设计是 3 单位横线，笔宽补偿后线长只略大于线宽，画出来是圆角方块。

产出 9 档（16/20/24/32/40/48/64/128/256）写进
`app/windows/runner/resources/app_icon.ico`，512 版写进 `app/assets/app_logo.png`（关于页用）。
实测：构建后标题栏小图标为金色底深色猫，与导轨顶部的矢量猫头是同一只猫。

> 构建时若 `PRPR.exe` 正在运行，链接会报
> `LNK1104: 无法打开文件 "…\Release\PRPR.exe"` —— 先 `Stop-Process -Name PRPR -Force` 再构建。

### 7.7 一个反复出现的误判：装的是旧版

排查过程中有三轮被「这界面不是新做的啊」打断，原因不在代码，在**部署链路**：

桌面快捷方式 `%USERPROFILE%\Desktop\PRPR.lnk` 与开始菜单的同名项，
TargetPath 都是 `%LOCALAPPDATA%\Programs\PRPR\PRPR.exe`，
而 `flutter build windows` 只写仓库里的 `app\build\windows\x64\runner\Release`。
只构建不同步，双击图标跑的一直是上一次安装时的那份 —— 实测那份是 10-18 的构建
（`app.so` 8143752 字节），标题栏采样 `(67,46,29)`，与新设计的 `(11,12,14)` 完全不同。

判据（下次先查这个，别先怀疑 DWM 代码）：

| 文件 | 旧版（10-18） | 新版（10-24） |
| --- | --- | --- |
| `PRPR.exe` | 83456 字节 | 94720 字节 |
| `data\app.so` | 8143752 | 8045448 |
| `assets\app_logo.png` | 13537（蓝紫底） | 34642（金色底） |
| 标题栏像素 | `(67,46,29)` | `(11,12,14)` |

已备份旧目录到 `%LOCALAPPDATA%\Programs\PRPR.bak-20261024`。
以后构建完必须补一步同步：

```powershell
Stop-Process -Name PRPR -Force -ErrorAction SilentlyContinue
cd app
flutter build windows --release
Copy-Item "build\windows\x64\runner\Release\*" `
  "$env:LOCALAPPDATA\Programs\PRPR" -Recurse -Force
```

### 7.8 截图工具踩过的坑（留作下次少走弯路）

- `shot14.ps1` 把参数写成 `$W/$H`，而 PowerShell **变量名不区分大小写**，
  后面的 `$h = $p.MainWindowHandle` 直接把 `$H` 覆盖成窗口句柄，
  于是 `SetWindowPos` 收到一个几十万的宽度，窗口被拉到屏幕外。
  修法：`shot15.ps1` 参数改名 `$TargetW / $TargetH`，句柄统一叫 `$hwnd`。
- 不做 `SetProcessDPIAware()` 的话，`GetWindowRect` 返回逻辑像素、
  `CopyFromScreen` 抓的却是缩放后的模糊区，两边坐标还对不上。
- `PrintWindow` + `PW_RENDERFULLCONTENT` 对 Flutter 窗口无效，抓到的是错尺寸的图。
- 截图前要把其它窗口 `ShowWindow(hwnd, 6)` 最小化，否则微信/PixPin 之类会盖上来被一起抓进去。
- 鼠标点击（`click2.ps1`，屏幕物理坐标）在 150% DPI 下命中率不稳定，
  `fg match=False` 时经常点空。换页换节一律走环境变量，别指望点击。


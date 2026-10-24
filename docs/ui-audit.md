# PRPR UI 审计报告

> 审计对象：本仓库的 Flutter Windows 桌面版（`app/lib`，33 个 dart 文件，其中 UI 层 19 个）
> 审计方式：只读源码，全部行号由 `grep -n` / 逐行读取定位，未运行应用、未修改任何 `app/lib` 下的文件。
> 本文档是唯一产出：`docs/ui-audit.md`。

## 0. 审计范围

| 层 | 文件 | 行数 |
| --- | --- | --- |
| 入口 | `app/lib/main.dart` | 80 |
| 常量 | `app/lib/core/constants.dart` | 43 |
| 主题 | `app/lib/ui/theme.dart` | 346 |
| 状态 | `app/lib/ui/app_state.dart` | 339 |
| 页面 | `app/lib/ui/pages/about_page.dart` | 138 |
| 页面 | `app/lib/ui/pages/favorite_view.dart` | 193 |
| 页面 | `app/lib/ui/pages/feature_view.dart` | 488 |
| 页面 | `app/lib/ui/pages/history_page.dart` | 189 |
| 页面 | `app/lib/ui/pages/home_page.dart` | 487 |
| 页面 | `app/lib/ui/pages/post_detail_page.dart` | 625 |
| 页面 | `app/lib/ui/pages/search_view.dart` | 398 |
| 页面 | `app/lib/ui/pages/settings_page.dart` | 734 |
| 组件 | `app/lib/ui/widgets/app_route.dart` | 33 |
| 组件 | `app/lib/ui/widgets/app_text_field.dart` | 122 |
| 组件 | `app/lib/ui/widgets/app_toast.dart` | 39 |
| 组件 | `app/lib/ui/widgets/hero_flight.dart` | 30 |
| 组件 | `app/lib/ui/widgets/post_grid.dart` | 233 |
| 组件 | `app/lib/ui/widgets/post_tile.dart` | 295 |
| 组件 | `app/lib/ui/widgets/state_message.dart` | 324 |

窗口约束（`app/lib/main.dart:24-30`）：初始 `1360 × 900`，最小 `900 × 600`，`TitleBarStyle.normal`。
主题入口（`app/lib/main.dart:65-76`）：`theme: AppTheme.light()`、`darkTheme: AppTheme.dark()`、`themeMode` 由 `settings.themeModeIndex` 决定（0/1/2 = 跟随系统/浅色/深色），`themeAnimationDuration: AppTheme.durMed`（220ms）、`themeAnimationCurve: AppTheme.curveEmph`。

---

## 1. 页面清单

| # | 文件 | 一句话职责 |
| --- | --- | --- |
| 0 | `app/lib/ui/pages/home_page.dart` | 应用外壳：AppBar（折叠钮 + PRPR 小标 + 页面名标题 + 任务胶囊/成功提示/换壁纸按钮）+ NavigationRail + IndexedStack 五个 tab，并注册 Ctrl+1..5 / Ctrl+Enter / F5 / Ctrl+R / Ctrl+K 快捷键。 |
| 1 | `app/lib/ui/pages/search_view.dart` | 搜索页（tab 0）：顶部固定搜索框 + 快捷键说明行 + 最近搜索 chip 区，下方瀑布流结果、底部分页进度、空态/错误态。 |
| 2 | `app/lib/ui/pages/feature_view.dart` | 每日精选页（tab 1）：拉 `rating:s` 最多 5 页、按 24 小时窗口筛出今日帖子，展示「今日高分」横排前三与「值得一看的标签」卡片墙。 |
| 3 | `app/lib/ui/pages/favorite_view.dart` | 收藏页（tab 2）：未登录时给出引导态；已登录时以共享 `PostGrid` 展示收藏，头部带 5 档排序下拉与刷新按钮，重载时列表压暗 + 顶部 2px 进度线。 |
| 4 | `app/lib/ui/pages/history_page.dart` | 换壁纸历史页（tab 3）：`ListTile` 列表（48px 缩略图 + 标签 + 时间 + 成败图标），头部显示条数与「清空」（带确认对话框）。 |
| 5 | `app/lib/ui/pages/settings_page.dart` | 设置页（tab 4）：单页 7 个段（站点 / 账号 / 换壁纸 / 自动换壁纸 / 内容筛选 / 外观 / 关于），内容列限宽 880 居中，附带「已保存」提示。 |
| 6 | `app/lib/ui/pages/post_detail_page.dart` | 图片详情页（路由压栈，不在 tab 里）：左 7 右 4 两栏，左侧大图（Hero + InteractiveViewer + 预览图铺底），右侧五段（画质 / 操作 / 评分 / 资料 / 标签），Esc 返回。 |
| 7 | `app/lib/ui/pages/about_page.dart` | 关于页（从设置页压栈）：Logo + 版本、项目说明、致谢列表、运行时信息（站点/登录状态/历史条数）、开源许可入口。 |

---

## 2. 每个页面的布局骨架

### 2.1 应用外壳 `home_page.dart`

```text
Shortcuts / Actions (Ctrl+1..5, Ctrl+Enter, F5, Ctrl+R, Ctrl+K)
└─ Scaffold
   ├─ AppBar  (theme.dart:139-152：bg dark 0xFF1A1A20 / light white, elevation 0, centerTitle false, title 18px w600)
   │  ├─ leadingWidth: 132                                  (home_page.dart:194)
   │  │  └─ Padding(left: gapS=8) > Row                     (home_page.dart:195-228)
   │  │     ├─ IconButton(AnimatedRotation, icon keyboard_double_arrow_left, size iconSm=20)  (199-214)
   │  │     ├─ SizedBox(width: gapXs=4)                     (215)
   │  │     └─ Flexible > Text('PRPR', labelLarge, w600, onSurfaceVariant, letterSpacing 0.5)  (216-226)
   │  ├─ titleSpacing: 0                                    (230)
   │  ├─ title: AnimatedSwitcher(durFast=140, slide Offset(0,-0.25) + fade)
   │  │  └─ Text(_destinations[_index].label)               (233-250)
   │  └─ actions: Padding(right: gapM=12) > Row(min)         (251-277)
   │     ├─ AnimatedSize(durMed=220, alignment centerRight) > _trailingStatus   (258-263)
   │     │  └─ 三选一：_TaskPill / _SuccessChip / SizedBox.shrink               (335-344)
   │     ├─ SizedBox(width: gapM=12)                        (264)
   │     └─ FilledButton.icon('换一张壁纸', icon wallpaper_outlined, size iconSm=20)  (265-273)
   └─ body: Row
      ├─ AnimatedContainer(width: railExtended ? 236 : 80, durMed=220, curveEmph)   (281-284, 常量 21-22)
      │  └─ ClipRect > OverflowBox(min/maxWidth = 236, alignment centerLeft)
      │     └─ NavigationRail(extended: true, 5 destinations)                       (288-306)
      ├─ VerticalDivider(width: 1, thickness: 1)             (308)
      └─ Expanded
         └─ FadeTransition(_tabOpacity) > SlideTransition(Offset(0, 0.006))          (310-314)
            └─ IndexedStack(index: _index)                                          (314-323)
               ├─ SearchView / FeatureView / FavoriteView / HistoryPage / SettingsPage
```

内部组件：

```text
_TaskPill (home_page.dart:367-434)            换壁纸进度胶囊，优先级最高的顶部状态
└─ Container(padding h gapM=12 / v gapS=8, bg surfaceContainerHigh, radius chipRadius=8)
   └─ Row(min)
      ├─ for ChangeStage.values(7 段)
      │  ├─ SizedBox(width: 3)                             (392)   ← 字面量
      │  └─ AnimatedContainer(width: 3, height: 14, radius 1.5, durFast=140)  (393-406)  ← 三条字面量
      ├─ SizedBox(width: gapM=12)                          (408)
      └─ AnimatedSwitcher(durFast=140) > Text(stage.label, bodySmall, onSurfaceVariant)  (409-429)

_SuccessChip (home_page.dart:440-480)
└─ TweenAnimationBuilder(0.9→1.0, 320ms, easeOutBack)      (448-453)  ← 字面量时长/曲线
   └─ Container(padding h gapM / v gapS, bg _green@0.14, radius chipRadius=8)
      └─ Row(min): Icon(check_circle, iconXs=16, _green) + gapXs=4 + Text('已换上新壁纸', bodySmall, w600, _green)
```

### 2.2 搜索页 `search_view.dart`

```text
Shortcuts(_FocusSearchIntent: Ctrl+K) / Actions
└─ Column                                  (163-189)
   ├─ Padding(fromLTRB pagePadding=16, pagePadding=16, pagePadding=16, gapM=12)   (166-171)
   │  └─ _searchControls = Column(crossAxisAlignment.start)                       (238-347)
   │     ├─ Row
   │     │  ├─ Expanded > AppTextField                                                (243-271)
   │     │  │   · hint '输入标签搜索，最多 6 个（如 landscape sky）'
   │     │  │   · prefixIcon = loading ? Padding(all: 13) + 16×16 CircularProgressIndicator(strokeWidth 2)   (253-260, 字面量 13)
   │     │  │                 : Icon(search, size iconSm=20)
   │     │  │   · suffixIcon = 文本非空时 IconButton(close, size iconSm=20)
   │     │  ├─ SizedBox(width: gapM=12)                                              (272)
   │     │  └─ FilledButton.icon(loading ? '搜索中' : '搜索')                         (273-277)
   │     ├─ SizedBox(height: gapS=8)                                                  (280)
   │     ├─ Row: Expanded(说明文字 bodySmall onSurfaceVariant, maxLines 1) + _CountLabel   (281-295)
   │     ├─ if(_recent.isNotEmpty) SizedBox(height: gapM=12)                          (296-297)
   │     ├─ Row: Icon(history, iconXs=16) + gapS=8 + Text('最近搜索', labelLarge) + Spacer + TextButton('清空')  (298-318)
   │     ├─ SizedBox(height: gapXs=4)                                                  (319)
   │     └─ AnimatedSize(durBase=180) > Wrap(spacing gapS=8, runSpacing gapS=8)        (326-345)
   │        └─ InputChip(label, onPressed 复用, onDeleted 移除, deleteIcon close iconXs=16)
   └─ Expanded > PostGrid                                                             (174-187)
      · posts / heroPrefix 'search-' / hasMore / isLoadingMore / initialLoading / emptyText / emptyBuilder / onOpen / onLoadMore

_PCountLabel (search_view.dart:357-398)
└─ TweenAnimationBuilder(0→total, durTask=400ms) > Text('共 N 张', bodySmall.copyWith(fontSize 13, w600, onSurfaceVariant, tabularFigures))
```

### 2.3 每日精选页 `feature_view.dart`

```text
三态其一（StateMessageSwitcher 包裹）：error / _loading&&isEmpty(SkeletonGrid tileCount 12) / isEmpty
否则：
RefreshIndicator(onRefresh: _load)
└─ ListView(padding: all pagePadding=16)                                    (177-221)
   ├─ Row: sectionAccent(3×16) + Expanded(Text('今日高分', sectionTitle)) + TextButton.icon('刷新')   (180-192)
   ├─ SizedBox(height: gapS=8)                                              (193)
   ├─ _TopStrip(height _topStripHeight=280, cardWidth _topCardWidth=200)     (194-199, 常量 37-38)
   │  └─ SizedBox(height 280) > Stack
   │     ├─ ScrollConfiguration(dragDevices: touch/mouse/trackpad/stylus)
   │     │  └─ ListView.separated(horizontal, separator gapM=12)
   │     │     └─ SizedBox(width 200) > Stack
   │     │        ├─ Positioned.fill > PostTile(heroPrefix 'feature-')
   │     │        └─ Positioned(left gapS=8, top gapS=8) > _rankBadge(index+1)
   │     ├─ _arrow(centerLeft, chevron_left, 可见时 opacity 1)   → IconButton.filledTonal(size iconSm=20)  (349-354)
   │     └─ _arrow(centerRight, chevron_right)                               (355-360)
   ├─ SizedBox(height: gapXl=24)                                             (200)
   ├─ Row: sectionAccent + Text('值得一看的标签', sectionTitle)               (201-206)
   ├─ SizedBox(height: gapM=12)                                              (207)
   └─ 空则 Text(hint) / 否则 Wrap(spacing gapM=12, runSpacing gapM=12)        (208-218)
      └─ _TagCard (feature_view.dart:425-488)
         └─ SizedBox(width: 180) > Card(radius cardRadius=12)
            └─ InkWell > Column(stretch)
               ├─ AspectRatio(1) > CachedNetworkImage(preview, cover, placeholder surfaceContainerHighest)
               └─ Padding(all gapM=12) > Column(start)
                  ├─ Text(tag.name, maxLines 1, w600)
                  ├─ SizedBox(height: gapXs=4)
                  └─ Text('${tag.posts.length} 张', hint + tabularFigures)

_rankBadge: Container(padding h gapS=8 / v gapXs=4, radius chipRadius=8, bg 三色)  (393-418)
  颜色：1 → 0xFFD4A017，2 → 0xFF9AA0A6，默认 → 0xFFB08D57     （395-397）
  Text('TOP $rank', white, fontSize 11, w700, height 1.2)        （408-416）
```

### 2.4 收藏页 `favorite_view.dart`

```text
未登录（settings.isLoggedIn == false）:
Center > Padding(all gapXxl=32) > Column(min)                    (89-116)
├─ Icon(lock_outline, size iconXl=40, onSurfaceVariant)
├─ SizedBox(height: gapM=12)
├─ Text('登录后才能看到自己的收藏', bodyMedium)
├─ SizedBox(height: gapS=8)
└─ Text('在「设置 → 账号」里填入站点用户名和密码。', bodySmall, onSurfaceVariant, center)

首次加载（isLoadingFavorites && favoritePosts.isEmpty）: const SkeletonGrid()   (121-122, 默认 tileCount 18)

否则:
Stack                                                             (124-191)
├─ AnimatedOpacity(opacity: 重载时 0.55, durFast=140)
│  └─ PostGrid(postGrid)
│     └─ header: Row                                               (135-167)
│        ├─ Expanded > Text('${n} 张收藏', sectionTitle)
│        ├─ SizedBox(width: gapM=12)
│        ├─ DropdownButton<int>(5 档排序)
│        ├─ SizedBox(width: gapS=8)
│        └─ IconButton(refresh, size iconSm=20)
└─ Positioned(left/right 0, top 0) > IgnorePointer > AnimatedOpacity
   └─ TickerMode > LinearProgressIndicator(minHeight: 2)           (172-189)
```

### 2.5 历史页 `history_page.dart`

```text
Column                                                             (56-116)
├─ Padding(fromLTRB pagePadding=16, pagePadding=16, pagePadding=16, gapS=8)
│  └─ Row                                                          (65-79)
│     ├─ Expanded > Text('共 N 条记录（最多保留 500 条）', titleSmall)
│     └─ TextButton.icon('清空', icon delete_outline, size iconSm=20)
├─ Divider(height: 1)                                              (81)   ← 与 dividerTheme(space 1) 重复声明
└─ Expanded
   └─ 空 ? StateMessage(icon history, title '还没有换过壁纸', hint …)
        : ListView.separated(padding: vertical gapS=8)              (89-113)
          ├─ separatorBuilder: Divider(height 1, indent pagePadding+_thumbSize+gapS = 16+48+8 = 72)   (93-96)
          └─ _HistoryRow → ListTile                                 (154-185)
             ├─ leading: ClipRRect(radius chipRadius=8) > SizedBox(48×48,_thumbSize) > Image.file(cover)
             ├─ title: Text(tags 或 '#postId', maxLines 1)
             ├─ subtitle: Text('yyyy-MM-dd HH:mm', bodySmall onSurfaceVariant + tabularFigures)
             └─ trailing: Icon(check_circle_outline / error_outline, size iconSm=20, 失败红)
   新行入场：TweenAnimationBuilder(-12→0, durSlow=260, curveIn, fade+translate)   (129-145)
```

### 2.6 设置页 `settings_page.dart`

```text
ListView(padding: fromLTRB pagePadding=16, pagePadding=16, pagePadding=16, 48)    (146-155)
└─ Center > ConstrainedBox(maxWidth: 880)                                        (156-158)
   └─ Column(min, stretch)
      ├─ _SavedHint (SizedBox(height: 28) + AnimatedSwitcher durFast=140)         (163, 649-735)
      ├─ _section('站点')        → 站点地址(AppTextField + trailing FilledButton '应用') / 密码哈希盐
      ├─ _section('账号')        → 已登录: ListTile + TextButton '退出登录'
      │                            未登录: 说明 Text(AppTheme.hint) + SizedBox(12) + 用户名 + 密码 + Align(FilledButton '登录')
      ├─ _section('换壁纸')      → 裁剪方式下拉 / 画质下拉 / 契合度下拉 / 随机范围滑块 / 默认标签
      ├─ _section('自动换壁纸')  → SwitchListTile '启用' / 间隔滑块 / 条件提示 Text(hint)
      ├─ _section('内容筛选')    → _SubHeader('分级') + 3 个 CheckboxListTile
      │                            _SubHeader('方向') + 2 个
      │                            _SubHeader('其他') + 2 个 + SizedBox(12) + 标签黑名单(minLines 3, maxLines 6)
      ├─ _section('外观')        → 主题下拉（跟随系统 / 浅色 / 深色）
      └─ _section('关于')        → ListTile(关于 PRPR, chevron_right) → AboutPage

_section (settings_page.dart:443-474)
└─ Padding(bottom: gapXl=24)
   └─ Container(padding: all gapL=16, bg surfaceContainerLow,
                radius cardRadius=12,
                border Border.all(dark 0xFF26262F / light 0xFFE8E8EF))    ← 454 行硬编码色
      └─ Column(start)
         ├─ Row: sectionAccent + Text(title, sectionTitle)
         ├─ SizedBox(height: gapM=12)
         └─ …children

_textField (476-526)
└─ Padding(bottom: 16) > Row(start)
   ├─ Padding(top: labelTopInset=14) > _label(width labelColumnSettings=112)    (492, 498-501)
   ├─ Expanded > AppTextField(prefixIcon Icon(size 20 字面量))                  (502-515, 508)
   └─ if trailing: SizedBox(width: 12) + Padding(top 14) > trailing             (516-522, 517)

_dropdown (528-560)  → Padding(bottom: 16) > Row [ _label(112) + Expanded > DropdownButtonFormField(isExpanded true) ]
_slider   (562-596)  → Padding(bottom: 12) > Row [ _label(112) + Expanded > Slider + SizedBox(width: 84, Text right-aligned) ]
_check    (598-611)  → CheckboxListTile(contentPadding: zero, dense: true)
_SubHeader(629-639)  → Padding(top: 8, bottom: 4) > Text(AppTheme.hint)
```

### 2.7 详情页 `post_detail_page.dart`

```text
Shortcuts(Esc → _DismissIntent) / Actions
└─ Scaffold
   ├─ AppBar(title: Text('#${post.id}'))                                        (219-223)
   └─ body: Row(stretch)                                                        (224-231)
      ├─ Expanded(flex: 7) > _buildImage()                                      (227)
      │  └─ ColoredBox(surfaceContainerLowest) > Padding(all gapL=16) > Center
      │     └─ AspectRatio(ratio = preferredRatio.clamp(0.2, 5.0))              (254, 261)
      │        └─ Hero(tag '${heroPrefix}${post.id}', flightShuttleBuilder heroFlightShuttle)
      │           └─ ClipRRect(radius cardRadius=12) > InteractiveViewer(min 0.5, max 6)
      │              └─ Stack(expand)                                           (285-320)
      │                 ├─ if preview != url: CachedNetworkImage(preview, cover, fadeIn durFast=140)
      │                 └─ AnimatedSwitcher(durSlow=260 / curveOut) > CachedNetworkImage(source, cover,
      │                       fadeInDuration durMed=220, placeholder SizedBox.shrink())
      ├─ VerticalDivider(width: 1)                                              (228)
      └─ Expanded(flex: 4) > _buildSidebar()                                    (229, 330-345)
         └─ ListView(padding: all pagePadding=16)
            ├─ ① _versionPicker  : Row(sectionAccent + '画质', sectionTitle) + gapS=8 + Wrap(spacing gapS=8, ChoiceChip ×4)
            ├─ SizedBox(height: gapL=16)
            ├─ ② _actionRow      : Row(sectionAccent + '操作') + gapS=8
            │                      + FilledButton.icon('设为壁纸') + gapS=8
            │                      + Wrap(spacing gapS=8, runSpacing gapS=8)[ OutlinedButton '收藏' / '复制图片地址' ]
            ├─ SizedBox(height: gapL=16)
            ├─ ③ _voteRow        : Row(sectionAccent + '评分') + gapS=8 + Wrap(spacing gapS=8, ChoiceChip ×4 带赞/踩 iconXs=16)
            ├─ Divider(height: 32)                                             (339)
            ├─ ④ _infoSection    : Row(sectionAccent + '资料') + gapS=8 + 8 行 (label 宽 labelColumnDetail=64 + SelectableText)
            │                     每行 Padding(vertical: 6)                     (528)
            ├─ Divider(height: 32)                                             (341)
            └─ ⑤ _tagSection     : Row(sectionAccent + '标签') + gapS=8 + Wrap(spacing 6, runSpacing 6, ActionChip ×n)
                                   + gapM=12 + TextButton.icon('复制站点详情页地址')
```

### 2.8 关于页 `about_page.dart`

```text
Scaffold
├─ AppBar(title: '关于')
└─ ListView(padding: all pagePadding=16)                                  (25-27)
   ├─ Row: ClipRRect(radius cardRadius=12) > Image.asset(64×64)            (28-53)
   │        + SizedBox(width: 16)                                          (43)
   │        + Column(start): Text('PRPR', headlineSmall) + SizedBox(4) + Text('版本 3.0.0', hint)
   ├─ SizedBox(height: 24)                                                  (54)
   ├─ Text(项目说明, bodyMedium)
   ├─ Divider(height: 40)                                                   (61)
   ├─ Row: sectionAccent + Text('致谢', sectionTitle) + SizedBox(8)          (62-68)
   ├─ _Bullet ×5  (Padding vertical 4, Row['· ', Expanded(Text)])            (69-73, 122-138)
   ├─ Divider(height: 40)                                                   (74)
   ├─ Row: sectionAccent + Text('运行时信息', sectionTitle) + SizedBox(8)     (75-81)
   ├─ _kv ×3  (SizedBox(width: 80) label hint + Expanded SelectableText)     (107-119, width 80 在 113)
   ├─ Divider(height: 40)                                                   (85)
   └─ ListTile('开源许可', chevron? 无, onTap showLicensePage)                (86-101)
```

### 2.9 共享网格 `post_grid.dart`（搜索 / 收藏 / 骨架共用）

```text
AnimatedSwitcher(durMed=220)                                              (99-110)
├─ 空且 initialLoading → SkeletonGrid(key 'skeleton')
└─ KeyedSubtree('content') > _content
   └─ LayoutBuilder → columns = columnsFor(maxWidth)                      (121-123, 90-95)
      ├─ 可用宽 = maxWidth - pagePadding*2；列数 = floor(可用/_targetColumnWidth=260)，clamp(2,8)   (92-94)
      └─ Stack
         ├─ Scrollbar(thumbVisibility: true) > ScrollConfiguration(dragDevices 四种)
         │  └─ CustomScrollView(scrollCacheExtent: 600px)                   (193)
         │     ├─ 可选 SliverPadding(fromLTRB 16,16,16,0) > SliverToBoxAdapter(header)
         │     ├─ 空 → SliverFillRemaining > _empty（自定义 emptyBuilder 或 StateMessage）
         │     └─ SliverPadding(fromLTRB 16, header==null?16:gapM=12, 16, gapXxl=32)   (141-147)
         │        └─ SliverMasonryGrid.count(crossAxisCount: columns,
         │              mainAxisSpacing gapL=16, crossAxisSpacing gapL=16,         (152-153)
         │              childCount = posts.length + (hasMore ? 1 : 0))
         │           └─ PostTile | 尾部 SizedBox(height: gapXxl*2 = 64)            (160)
         └─ Positioned(bottom: 0) > IgnorePointer > AnimatedOpacity(opacity: loadingMore?1:0)
            └─ TickerMode > LinearProgressIndicator(minHeight: 2)                 (204-218)
   触底判定：pixels >= maxScrollExtent - 800                                (85)
```

---

## 3. 现状 token 表（真实取值）

来源：`app/lib/ui/theme.dart`（尺寸/颜色/动效）、`app/lib/core/constants.dart`（业务常量）。

### 3.1 间距（六档，全部 4 的倍数）

| token | 值 | 行号 | 声明用途 |
| --- | --- | --- | --- |
| `AppTheme.gapXs` | 4 | theme.dart:22 | 旧代码 3 → 4 |
| `AppTheme.gapS` | 8 | theme.dart:23 | 旧代码 6 → 8 |
| `AppTheme.gapM` | 12 | theme.dart:24 | 旧代码 10 → 12 |
| `AppTheme.gapL` | 16 | theme.dart:25 | 旧代码 14 → 16 |
| `AppTheme.gapXl` | 24 | theme.dart:26 | 旧代码 28 → 24 |
| `AppTheme.gapXxl` | 32 | theme.dart:27 | 大留白 |
| `AppTheme.pagePadding` | 16 | theme.dart:42 | 页面外边距（与 gapL 同值但独立命名） |

### 3.2 圆角（三档）

| token | 值 | 行号 | 用途 |
| --- | --- | --- | --- |
| `AppTheme.cardRadius` | 12 | theme.dart:34 | 卡片 / 图片 / 页面级容器 / NavigationRail 指示器 |
| `AppTheme.inputRadius` | 12 | theme.dart:37 | 输入框 / 四种按钮 / SnackBar（与 cardRadius 同值） |
| `AppTheme.chipRadius` | 8 | theme.dart:40 | chip / 徽章 / tooltip |

### 3.3 图标（四档）

| token | 值 | 行号 |
| --- | --- | --- |
| `AppTheme.iconXs` | 16 | theme.dart:46 |
| `AppTheme.iconSm` | 20 | theme.dart:47 |
| `AppTheme.iconMd` | 24 | theme.dart:48 |
| `AppTheme.iconXl` | 40 | theme.dart:49 |

### 3.4 动效（六档 Duration + 三条曲线）

> 说明：`theme.dart` 实际声明的 Duration 是 **6 档**（`durMicro`…`durTask`，第 74–89 行），另有 3 条曲线（第 92–98 行）；注意：`theme.dart:66-71` 的注释声称整套值已收敛到 90–260ms，但第 5 节 G1 会列出 7 处绕过这 6 档的 Duration 字面量（200 / 320 / 900 / 1200×2 / 3000 / 260）。

| token | 值 | 行号 | 声明用途 |
| --- | --- | --- | --- |
| `AppTheme.durMicro` | 90ms | theme.dart:74 | 按下 / 抬起 |
| `AppTheme.durFast` | 140ms | theme.dart:77 | 图标、遮罩、chip、小范围淡入 |
| `AppTheme.durBase` | 180ms | theme.dart:80 | tab 内容、标题、透明度 |
| `AppTheme.durMed` | 220ms | theme.dart:83 | 图片渐显、侧栏展开、状态切换、SnackBar |
| `AppTheme.durSlow` | 260ms | theme.dart:86 | 页面转场、详情页换画质、列表新行 |
| `AppTheme.durTask` | 400ms | theme.dart:89 | 长任务分段进度爬行 |
| `AppTheme.curveIn` | `Curves.easeOutCubic` | theme.dart:92 | 出现 |
| `AppTheme.curveOut` | `Curves.easeInCubic` | theme.dart:95 | 消失 |
| `AppTheme.curveEmph` | `Curves.easeInOutCubic` | theme.dart:98 | 整体状态变幻 |

设计意图（theme.dart:66-72）：整套值压在 90–260ms，只有长任务 400ms 例外，理由是「桌面鼠标节奏比触屏快，超过 240ms 的 micro-interaction 会被读成迟钝」。

### 3.5 颜色

| 语义 | 深色 | 浅色 | 行号 |
| --- | --- | --- | --- |
| 种子色 seed | `0xFF5B6ABF` | 同 | theme.dart:15 |
| 页面背景 scaffoldBackgroundColor | `0xFF121216` | `0xFFF7F7FA` | theme.dart:128-129 |
| AppBar 背景 | `0xFF1A1A20` | `Colors.white` | theme.dart:140 |
| AppBar 标题文字 | `Colors.white` | `0xFF1A1A20` | theme.dart:150 |
| 输入框填充 | `0xFF1E1E26` | `Colors.white` | theme.dart:240 |
| 输入框描边（字段边框/未聚焦） | `0xFF32323C` | `0xFFDCDCE6` | theme.dart:110-111 |
| hint / placeholder | `0xFF9EA0AA` | `0xFF6B6D75` | theme.dart:116-117 |
| Divider | `0xFF26262F` | `0xFFE8E8EF` | theme.dart:304 |
| Tooltip 底色 | `0xFF2A2A33` | 同 | theme.dart:230 |
| 焦点描边 / 错误描边 | `scheme.primary` / `scheme.error`，宽 1.8 | 同 | theme.dart:259-273 |
| 滚动条拇指 | `onSurfaceVariant` @ 0.35（悬停 0.7） | 同 | theme.dart:195-201 |
| NavigationRail 指示器 | `scheme.primary` @ 0.14 | 同 | theme.dart:219 |

色值选择理由（theme.dart:113-115）：placeholder 不用 `onSurfaceVariant + alpha 0.6`，因为白底只有 2.6:1、深色底 4.15:1，低于 WCAG AA 4.5:1。

### 3.6 排版（部分，theme 中硬编码）

| 项 | 值 | 行号 |
| --- | --- | --- |
| AppBar 标题 | 18px / w600 | theme.dart:147-151 |
| chip 标签 | 13px | theme.dart:210 |
| chip 内边距 | h 4 / v 2 | theme.dart:211 |
| tooltip 文字 | 12px / white | theme.dart:233 |
| helper / error | 12px / height 1.35（error 另 w500） | theme.dart:280-292 |
| 输入框 contentPadding | h 14 / v 14 | theme.dart:242-243 |
| 段标题 `sectionTitle` | titleSmall + w700 + onSurface + letterSpacing 0.5 | theme.dart:323-328 |
| 段标题竖条 `sectionAccent` | 3 × 16，右边距 gapS=8，圆角 2 | theme.dart:331-339 |
| 说明小字 `hint(context)` | bodySmall + onSurfaceVariant | theme.dart:342-345 |

### 3.7 组件级几何（theme 内）

| 项 | 值 | 行号 |
| --- | --- | --- |
| 按钮内边距 | Filled 20/14、Outlined 16/12、Text 12/10、Elevated 20/14 | theme.dart:161-184 |
| 滚动条 | 常态 6 / 悬停拖动 10，圆角 4 | theme.dart:188-194 |
| 滑块 | track 4、thumb 半径 8、overlay 半径 16 | theme.dart:222-226 |
| 输入框前缀图标约束 | minWidth 44 / minHeight 44 | theme.dart:296-297 |
| 输入框后缀图标约束 | minWidth 40 / minHeight 40 | theme.dart:298-299 |
| ListTile contentPadding | h 16 / v 4 | theme.dart:307 |
| 标签列宽 | `labelColumnSettings` 112 / `labelColumnDetail` 64 | theme.dart:54 / 57 |

### 3.8 业务常量（`app/lib/core/constants.dart`）

| 常量 | 值 | 行号 |
| --- | --- | --- |
| `defaultHost` | `https://yande.re` | 6 |
| `defaultPasswordHashSalt` | `choujin-steiner--your-password--` | 10 |
| `postsPageLimit` | 100 | 13 |
| `faceDetectScaleFactor` | 1.05 | 16 |
| `faceDetectMinNeighbors` | 5 | 19 |
| `faceDetectMinSize` | 30 | 22 |
| `faceDetectMaxDimension` | 1024 | 29 |
| `cascadeAsset` | `assets/lbqcascade_animeface.xml` | 32 |
| `userAgent` | Chrome/120 UA 串 | 35-36 |
| `defaultTagBlacklist` | `bikini buruma ass pantsu bra torn_clothes no_pan` | 39 |
| `maxShuffleWindow` | 200 | 42 |

注意：`constants.dart` 里**没有任何间距/圆角/颜色/动效值**，所有尺寸 token 都在 `theme.dart`，业务常量与设计 token 分居两个文件。

### 3.9 UI 层自定义常量（不在 theme 里，散落在页面/组件内）

| 常量 | 值 | 位置 |
| --- | --- | --- |
| `_kRailExtendedWidth` | 236 | home_page.dart:21 |
| `_kRailCollapsedWidth` | 80 | home_page.dart:22 |
| `_topCardWidth` | 200 | feature_view.dart:37 |
| `_topStripHeight` | 280 | feature_view.dart:38 |
| `_maxPages` | 5 | feature_view.dart:33 |
| `_TagCard` 宽度 | 180 | feature_view.dart:435 |
| `_thumbSize` | 48 | history_page.dart:24 |
| `_targetColumnWidth` | 260 | post_grid.dart:64 |
| 骨架列宽魔数 | 260（重复定义） | state_message.dart:322 |
| 骨架比例序列 | 8 个值 0.72…0.95 | state_message.dart:229-238 |
| 骨架动画周期 | 900ms | state_message.dart:224 |
| `StateMessage.maxWidth` | 480（默认参数） | state_message.dart:26 |
| 设置内容列 | 880 | settings_page.dart:158 |
| 设置标签列 | 112（引用 token） | settings_page.dart:431 |
| 设置滑块数值列 | 84 | settings_page.dart:590 |
| 关于页标签列 | 80（第三套） | about_page.dart:113 |
| Toast 宽度 | 360 | app_toast.dart:24 |
| 详情页左右 flex | 7 : 4 | post_detail_page.dart:227/229 |
| 详情页大图比例钳制 | 0.2 – 5.0 | post_detail_page.dart:254 |
| 瀑布流瓦片比例钳制 | 0.5 – 2.0 | post_tile.dart:70 |
| 骨架/瓦片圆角 | cardRadius | post_tile.dart:65 |
| 详情页右栏五段分隔 | Divider(height: 32) | post_detail_page.dart:339/341 |
| 关于页分隔 | Divider(height: 40) | about_page.dart:61/74/85 |
| 路由反向时长 | 200ms | app_route.dart:33 |

---

## 4. 组件契约（`app/lib/ui/widgets/`）

### 4.1 `AppTextField`（app_text_field.dart:10-69）

```dart
const AppTextField({
  Key? key,
  TextEditingController? controller,
  FocusNode? focusNode,
  String? label,            // 浮动标签
  String? hint,             // 空值占位
  String? helper,           // 下方说明小字
  String? errorText,        // 非空即错误态
  Widget? prefixIcon,
  Widget? suffixIcon,       // 额外后缀，密码可见性按钮排在它后面
  bool obscureText = false, // 密码框（自带可见性切换）
  int? minLines,
  int maxLines = 1,         // >1 时多行排版，标签对齐首行
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  TextInputType? keyboardType,
  TextInputAction? textInputAction,
  bool enabled = true,
  bool autofocus = false,
})
```

职责边界（app_text_field.dart:3-9）：样式（填充、圆角、聚焦描边、helper/error 排版）全部来自 `inputDecorationTheme`，组件本身只负责四段文案摆位、前缀图标统一尺寸、后缀与密码按钮并排、多行限高。内部隐藏状态 `_hidden`（71-72, 101-121）。

### 4.2 `PostGrid`（post_grid.dart:19-58）

```dart
const PostGrid({
  Key? key,
  required List<Post> posts,
  required void Function(Post post) onOpen,
  VoidCallback? onLoadMore,
  bool hasMore = false,
  bool isLoadingMore = false,
  bool initialLoading = false,   // 仅首次（无任何结果）显示骨架
  String heroPrefix = '',
  Widget? header,                // 顶部附加内容，null 时列表占满高度
  String emptyText = '没有内容',
  WidgetBuilder? emptyBuilder,   // 给了就不用 emptyText
})
```

职责：瀑布流网格（`SliverMasonryGrid`）、列数自适应（260 目标宽、clamp 2–8）、触底 800px 预加载、桌面鼠标拖动滚动、常驻滚动条、底部 2px 翻页进度、骨架/空态切换、header 与列表同滚。静态方法 `columnsFor(width)`（90-95）暴露给外部。

### 4.3 `PostTile`（post_tile.dart:23-39）

```dart
const PostTile({
  Key? key,
  required Post post,
  VoidCallback? onTap,
  String heroPrefix = '',
})
```

职责：单张缩略图。三态交互——悬停（描边 `primary@0.55` 1.5px + 阴影 `0x47000000` blur 18 offset (0,6)）、按下（`AnimatedScale` 0.985，按下 90ms / 松开 140ms）、键盘焦点（`primary` 2px + `primary@0.35` spread 3 外发光）；焦点时 `Scrollable.ensureVisible`（durBase=180）。悬停/聚焦浮层：底部 56px 黑色渐变 @0.62 + 尺寸文字 11px w600 + 右上角评级徽章 10px w700。比例钳制 0.5–2.0。Hero shuttle 由 `hero_flight.dart` 统一。

### 4.4 `StateMessage` / `StateMessageSwitcher` / `SkeletonGrid`（state_message.dart）

```dart
const StateMessage({
  Key? key,
  required IconData icon,
  required String title,          // titleMedium + w600 + onSurface，全块唯一强调
  String? detail,                 // 具体原因，bodySmall onSurfaceVariant，maxLines 4
  String? hint,                   // 通用建议，onSurfaceVariant@0.85
  Color? iconColor,
  String? actionLabel,
  IconData? actionIcon,
  VoidCallback? onAction,
  bool busy = false,              // 按钮原位换 16px 环，整块 opacity 0.6 并吃点击
  List<String> suggestions = const <String>[],
  ValueChanged<String>? onSuggestion,
  double maxWidth = 480,
})

const StateMessageSwitcher({ required Object stateKey, required Widget child })
const SkeletonGrid({ Key? key, int tileCount = 18 })
```

职责：统一「无内容」三态（加载 / 失败 / 空）的排版语言与过渡；`stateKey` 用于让 `AnimatedSwitcher` 认出状态变化。`SkeletonGrid` 用固定比例序列 + 单一 ticker（900ms，`repeat(reverse: true)`）模拟瀑布流形状。

### 4.5 `AppToast`（app_toast.dart:14-38）

```dart
abstract final class AppToast {
  static void error(BuildContext context, String message);          // 固定宽 360、floating、durTask*10
  static void resultIfFailed(BuildContext context, {required bool success, required String message});
}
```

职责与原则（app_toast.dart:5-13）：成功不弹（形态变化即反馈），失败只弹一条，用 `hideCurrentSnackBar` 而非 `clearSnackBars`。

### 4.6 `heroFlightShuttle`（hero_flight.dart:14-31）

```dart
Widget heroFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromContext,
  BuildContext toContext,
  String imageUrl,
)
```

职责：瓦片 ↔ 详情页飞行期的统一外观——一律 `BoxFit.cover`，圆角从 12 收到 `cardRadius * (1 - t*0.6)` = 12 → 4.8，曲线 `curveEmph`。

### 4.7 `appPageRoute`（app_route.dart:14-31）

```dart
Route<T> appPageRoute<T>({ required WidgetBuilder builder, RouteSettings? settings })
```

职责：详情页转场——正向 `durSlow=260ms`，`Interval(0.25, 1, Curves.easeOut)` 只做淡入；反向 `_kReverseDuration = 200ms`（33 行）。理由：避开 `MaterialPageRoute` 的 Zoom 转场与 Hero 叠动。

---

## 5. 视觉一致性问题清单

> 格式：**现象 → 位置（文件:行号）→ 为什么是问题**。
> 行号全部来自 `grep -n` 实测。共 31 条（A 5 / B 6 / C 6 / D 4 / E 4 / F 4 / G 2），按主题分组；标 🔴 的是可直接观察到的缺陷，🟡 的是体系性隐患。

### A. 主题 token 被字面量绕过

**A1 🟡 设置页卡片边框复制了一份 dividerTheme 的色值**
- 现象：`_section` 里 `border: Border.all(color: isDark ? const Color(0xFF26262F) : const Color(0xFFE8E8EF))`。
- 位置：`app/lib/ui/pages/settings_page.dart:453-455`；同一对色值在 `app/lib/ui/theme.dart:304`（`dividerTheme`）已定义一次。
- 为什么是问题：同一个视觉语义（深色/浅色的「弱分隔线」）在两处各自写死。改主题时两处必然漂移，而 `theme.dart` 的注释本身就在反对这件事（theme.dart:9-10「尺寸类 token 全部收在这里，页面里不要再写字面量」）。该段注释还说「卡片圆角/描边/底色也只在这里定义一次，避免各段自己写一套看起来差 1px 的边框」（settings_page.dart:441-442）—— 定义只有一次，但色值仍是字面量。

**A2 🟡 间距 token 六档齐备，但页面里仍有 13 处字面量**
- 现象与位置：
  - `settings_page.dart:494` `EdgeInsets.only(bottom: 16)` → 应为 `gapL`
  - `settings_page.dart:537` `EdgeInsets.only(bottom: 16)` → `gapL`
  - `settings_page.dart:573` `EdgeInsets.only(bottom: 12)` → `gapM`
  - `settings_page.dart:517` `SizedBox(width: 12)` → `gapM`
  - `settings_page.dart:218`、`settings_page.dart:383` `SizedBox(height: 12)` → `gapM`
  - `settings_page.dart:636` `EdgeInsets.only(top: 8, bottom: 4)` → `gapS` / `gapXs`
  - `about_page.dart:43` `SizedBox(width: 16)` → `gapL`
  - `about_page.dart:48` `SizedBox(height: 4)` → `gapXs`
  - `about_page.dart:54` `SizedBox(height: 24)` → `gapXl`
  - `about_page.dart:68`、`about_page.dart:81` `SizedBox(height: 8)` → `gapS`
  - `home_page.dart:392` `SizedBox(width: 3)`
- 为什么是问题：这些数值「恰好等于」某个 token，所以肉眼现在看不出差异；但它们不受 token 保护。theme.dart:19-21 的注释明确记录了上一轮被治理的碎片值（3/6/10/14/28），说明这类漂移在本项目里已经发生过一次。其中 `width: 3`（home_page.dart:392）不属于任何档位，是真正的孤立值。

**A3 🟡 「两档圆角」的注释与实现不符**
- 现象：theme.dart:31-32 声明「只留两档：12 给卡片/输入框/按钮/图片，8 给 chip/徽章/tooltip」。实际代码里还有 4 个额外的圆角值：`Radius.circular(4)`（theme.dart:194，滚动条）、`BorderRadius.circular(2)`（theme.dart:337，段标题竖条）、`BorderRadius.circular(1.5)`（home_page.dart:404，进度分段条）、`AppTheme.cardRadius * (1 - t * 0.6)` 插值到 4.8（hero_flight.dart:24）。
- 为什么是问题：文档断言与代码不符，后续维护者会按注释去查「为什么这里有个 4」。前三个属于「小于 8 的装饰性圆角」，应显式登记为第三档（例如 `microRadius = 2`），否则每次评审都要重新判断哪些是合法例外。

**A4 🟡 三套「标签列 → 值」的对齐线**
- 现象：设置页用 `AppTheme.labelColumnSettings = 112`（theme.dart:54，settings_page.dart:431）；详情页用 `AppTheme.labelColumnDetail = 64`（theme.dart:57，post_detail_page.dart:533）；关于页运行时信息硬编码 `SizedBox(width: 80)`（about_page.dart:113）。
- 为什么是问题：三处是同一类布局（左标签、右值），却有三条不同的对齐线。关于页的 80 既不是 token 也不在主题注释的说明里，属于漏网。跨页面切换时，「站点」「登录状态」这类同名 key 的缩进会左右跳。

**A5 🟡 图标尺寸：最常用的 24 没有落点，另有两处写成 20 字面量**
- 现象：`AppTheme.iconMd = 24`（theme.dart:48）在整个 `app/lib` 里**零引用**（`grep -rn 'iconMd'` 在 theme.dart 之外无命中）；反过来，settings_page.dart:508 与 app_text_field.dart:110 写 `size: 20` 而未用 `AppTheme.iconSm`。
- 为什么是问题：24 是 Material IconButton 的默认值，所以「24」到处都在用但没人显式写 —— token 定义了一个没人调用的档位，等于四档里只有三档有效。同时 20 两处硬编码，说明「前缀图标必须 20」这条规则没有载体。

### B. 同一语义、两种视觉语言

**B1 🔴 「成功」语义有四个颜色**
- 现象：
  - 换壁纸成功胶囊：硬编码 `static const Color _green = Color(0xFF2E7D32)`（home_page.dart:443），底色 `_green.withValues(alpha: 0.14)`、文字 `_green`（home_page.dart:460、472）。
  - 设置页「已保存」：`theme.colorScheme.primary`（settings_page.dart:719、726）。
  - 详情页收藏成功：图标换成 `Icons.check`（post_detail_page.dart:430、442），颜色走默认 `onSurface`。
  - 瓦片评级 S：`const Color(0xFF2E7D32)`（post_tile.dart:255）—— 与换壁纸成功同一个绿，但语义是「安全内容」，不是「成功」。
- 为什么是问题：同一个 app 里「操作成功」有两套配色（绿 vs 品牌紫），而「绿」同时被借用给「Safe 分级」。三种语义（成功 / 安全 / S 评级）撞在同一色号上，用户在详情页看到绿色对勾时会不确定这是「已收藏」还是「安全内容」。
- 附带量化：`_SuccessChip` 的文字色 0xFF2E7D32 叠在 AppBar 底色 0xFF1A1A20 上，对比度约 **3.38:1**；文字是 `bodySmall`（12px），低于 WCAG AA 对正文的 4.5:1。

**B2 🔴 今日高分的名次徽章白字对比度全部不达标**
- 现象：`_rankBadge` 三色 + 白字 11px w700（feature_view.dart:395-416）：第 1 名 `0xFFD4A017`、第 2 名 `0xFF9AA0A6`、第 3 名 `0xFFB08D57`，文字 `color: Colors.white, fontSize: 11`（feature_view.dart:410-414）。
- 测算对比度（WCAG 相对亮度公式）：金 `D4A017` → **2.38:1**；灰 `9AA0A6` → **2.64:1**；棕 `B08D57` → **3.09:1**。
- 为什么是问题：三档全部低于 WCAG AA 的 4.5:1（11px 不适用大字豁免）。「TOP 1/2/3」是该页唯一的排序信息，却在最差的对比度上。同一份代码里的评级徽章反而做得更好（`2E7D32` 白字 5.13:1、`C62828` 5.62:1、`546E7A` 5.40:1），只有 `EF6C00`（Q）是 **3.08:1** 不达标（post_tile.dart:255-258）。

**B3 🟡 三种「卡片」三种实现**
- 现象：
  - 主题已定义 `cardTheme`（theme.dart:153-160：elevation 0、margin zero、cardRadius、antiAlias）。
  - `PostTile` 仍显式传 `Card(clipBehavior: Clip.antiAlias, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: radius))`（post_tile.dart:136-139），外层再套一个带 border + boxShadow 的 `AnimatedContainer`（post_tile.dart:108-135）—— 双层圆角。
  - `_TagCard` 同样手写 `Card` + `shape`（feature_view.dart:436-441）。
  - 设置页 `_section` 完全不用 `Card`，用裸 `Container` + `BoxDecoration` + `Border.all`（settings_page.dart:448-456）。
- 为什么是问题：主题层定义了卡片语言，但四类卡片里两类绕过 shape、一类完全不用 Card。结果是「卡片」这个最基本的一层没有单一真源：改 cardTheme 时只有原本就没覆盖的地方才跟着变，已经覆盖的地方纹丝不动。

**B4 🟡 「3px 竖条」有两个规格**
- 现象：`AppTheme.sectionAccent` 是 `width: 3, height: 16, margin right gapS=8, radius 2`（theme.dart:331-339）；`_TaskPill` 的分段条是 `width: 3, height: 14, radius 1.5`，段间 `SizedBox(width: 3)`（home_page.dart:392-406）。
- 为什么是问题：两条竖条并排出现在同一屏（AppBar 的胶囊 vs 内容区段标题）时，高度差 2px、圆角差 0.5px、间隙规则不同（一个靠 margin、一个靠 SizedBox）。theme.dart:32 的教训正是「差 2px 看不出两种圆角，只看出对不齐」—— 这里原样复现了。

**B5 🟡 「没有内容」的排版有两套**
- 现象：统一组件 `StateMessage` 是「iconXl=40 → gapL=16 → titleMedium w600 → gapS → detail → gapS → hint」，宽度上限 480、外层 padding gapXxl=32（state_message.dart:69-99）。但 `FavoriteView` 的未登录态另写了一套：`Center > Padding(all gapXxl) > Column`，icon 40 → `gapM=12` → `bodyMedium`（无 w600）→ `gapS` → `bodySmall`（favorite_view.dart:89-116）。
- 为什么是问题：同类内容（「这里本来该有东西但没有」）的间距节奏差 4px、标题字重差一整档。收藏页的未登录态恰恰是全应用最需要「引导」的一屏，视觉权重却比搜索页的普通空态更弱。

**B6 🟡 空态的能力参差**
- 现象：`SearchView` 空态给了 suggestions chip（search_view.dart:221-229）；`FeatureView` 空态给了「刷新」按钮（feature_view.dart:160-173）；`FavoriteView` 空态只有 `emptyText: '还没有收藏任何图片'`（favorite_view.dart:133），无按钮；`HistoryPage` 空态 `StateMessage` 无动作（history_page.dart:84-88）。
- 为什么是问题：四个空态里有动作的只有两个，而且新增动作的方式是各页各写。用户碰到「收藏为空」时没有任何下一步（连「去搜索」都没有），而「精选为空」却能刷新。

### C. 排版与字号

**C1 🟡 13px 出现两次，且都不是 token**
- 现象：`search_view.dart:372` `bodySmall.copyWith(fontSize: 13, fontWeight: w600, …)` 覆盖主题；`theme.dart:210` `chipTheme.labelStyle: TextStyle(fontSize: 13)`。
- 为什么是问题：M3 的 `bodySmall` 是 12、`bodyMedium` 是 14，13 是夹在中间的第三个数。它现在承担了两个语义（结果总数、chip 标签），但没有任何命名，后续很难判断「13 是刻意的还是抄来的」。

**C2 🟡 10/11px 的小字共 3 处，其中 10px 不可读**
- 现象：`post_tile.dart:234` `fontSize: 11`（尺寸叠字）、`post_tile.dart:269` `fontSize: 10`（评级徽章字母）、`feature_view.dart:412` `fontSize: 11`（TOP 名次）。
- 为什么是问题：10px 在下限 900×600 的窗口和 150% 缩放的 4K 上都处于「能看见但不该存在」的区间；而且这三处是全应用仅有的「图片上的浮字」，恰恰是最需要可读性的位置。theme 里最小的登记字号是 12（helper/error），10 与 11 都属于游离值。

**C3 🟡 同一行两个不同尺寸的搜索图标**
- 现象：`SearchView` 的输入框 `prefixIcon: const Icon(Icons.search, size: AppTheme.iconSm)` 即 20（search_view.dart:261）；同一 Row 右侧的 `FilledButton.icon(icon: const Icon(Icons.search))` 没给 size（search_view.dart:275），走 Material 默认 24。
- 为什么是问题：并排的两个「搜索」图标一个 20 一个 24，中间只隔了 gapM=12 —— 这是同层级「两种图标尺寸」最直接的证据，也是最容易被一眼看出来的不齐。

**C4 🟡 唯一的非 4 倍数内边距**
- 现象：`search_view.dart:254` `padding: EdgeInsets.all(13)`（为了把 16×16 的 `CircularProgressIndicator` 对齐到 inputDecorationTheme 的 `contentPadding: 14/14` + 1px 边框内）。
- 为什么是问题：13 没进 token 表，也没有注释解释它是怎么算出来的（按 14+1 应为 15，写 13 实际会让进度圈比搜索图标偏上/偏左约 2px）。加载态与静态态的图标位置会跳一下。

**C5 🟡 分隔线的三种节奏**
- 现象：关于页 `Divider(height: 40)` 三处（about_page.dart:61、74、85）；详情页 `Divider(height: 32)` 两处（post_detail_page.dart:339、341）；历史页 `Divider(height: 1)`（history_page.dart:81）+ `separatorBuilder` 里再 `Divider(height: 1, indent: 72)`（history_page.dart:93-96）。而 `dividerTheme` 已声明 `space: 1, thickness: 1`（theme.dart:301-305）。
- 为什么是问题：`height` 在 Flutter 里同时决定「线高」和「上下留白」，页面传 40/32 就是在覆盖主题的 space:1。三套节奏意味着「段落分隔」这件事没有全局语法；而历史页的 1px 与 72 缩进又是第四种。

**C6 🟡 详情页标签区的间距与上方两段不一致**
- 现象：`_tagSection` 的 `Wrap(spacing: 6, runSpacing: 6)`（post_detail_page.dart:568-569）；同一栏里 `_versionPicker` 与 `_voteRow` 的 `Wrap(spacing: AppTheme.gapS)` 即 8（post_detail_page.dart:365、464）。
- 为什么是问题：三个 Wrap 都是「chip 群」，两个 8、一个 6。标签段 chip 更多、更密，视觉上会显得比上下两段「挤」，破坏右栏的纵向节奏。

### D. 交互与可点区域

**D1 🔴 历史记录行看起来可点，实际不可点**
- 现象：`_HistoryRow` 返回 `ListTile(leading: 48×48 缩略图, title: 标签, subtitle: 时间, trailing: 成败图标)`，**没有 `onTap`**（history_page.dart:154-185）。
- 为什么是问题：有 leading 图、有 title/subtitle 层级、有 trailing 图标 —— 这是标准的「可点列表项」外观，但点击无响应。而该页的初衷（history_page.dart:13-14「刚才那张挺好看的，想找回来」）恰恰要求能点回去。用户点一次没反应就会认定「这页是死的」。

**D2 🟡 chip 的删除按钮可点区约 24×24**
- 现象：`InputChip(... deleteIcon: const Icon(Icons.close, size: AppTheme.iconXs))`（search_view.dart:335-341），deleteIcon 被压到 16px。
- 为什么是问题：桌面端的可点目标建议 ≥32×32（Material 触屏 48，桌面可放宽到 32）。16px 图标 + 默认内边距大约只有 24×24，且它紧邻 chip 主体（点错就变成「复用这个搜索词」），是高误触区。

**D3 🟡 任务胶囊出现/消失会推动主按钮**
- 现象：AppBar `actions` 里 `AnimatedSize(alignment: Alignment.centerRight, child: _trailingStatus(stage))`（home_page.dart:258-263），后面紧跟 `SizedBox(width: gapM)` + `FilledButton.icon('换一张壁纸')`（home_page.dart:264-273）。胶囊宽度从 idle 的 0 → 成功的约 150 → 进行中的约 200。
- 为什么是问题：「换一张壁纸」是高频按钮，却会随着左侧状态胶囊的宽度变化左右移动。桌面用户第二次点击时鼠标位置已经不一样了。`_SuccessChip` 甚至还有 0.9→1.0 的 `easeOutBack` 缩放（home_page.dart:448-453），会额外带来 320ms 的位移。

**D4 🟡 按钮尺寸三档并存且都由主题、而非语义决定**
- 现象：`filledButtonTheme` 内边距 20/14、`outlinedButtonTheme` 16/12、`textButtonTheme` 12/10（theme.dart:161-184）。
- 为什么是问题：「收藏」（Outlined）与「设为壁纸」（Filled）在详情页是同一组动作（post_detail_page.dart:395-445），但高度不同（Filled 约 48、Outlined 约 44）。三个按钮并排时基线不齐；而 theme.dart:119-123 的注释本意只是「统一圆角」，顺手把内边距也分了三档，造成「按钮越高越重要」的意外语义。

### E. 视觉焦点与信息优先级

**E1 🔴 设置页 7 个段完全等权，没有焦点**
- 现象：`_section` 对全部 7 个段套用同一套样式：`surfaceContainerLow` 底 + 1px 边框 + `gapL=16` 内边距 + `sectionTitle`（w700）+ `bottom: gapXl=24`（settings_page.dart:443-474）。段顺序：站点 / 账号 / 换壁纸 / 自动换壁纸 / 内容筛选 / 外观 / 关于，实际调用 7 次（`grep -c '_section(context'` = 7），而 441 行注释写的是「8 个段都走这里」—— 注释本身也已经漂移。
- 为什么是问题：「站点地址写错了」和「想看看致谢」在同一屏里拥有同样的视觉权重、同样的面积。深色下 `surfaceContainerLow` 与 `0xFF121216` 的背景差极小，7 张卡片实际只靠同色（0xFF26262F）的 1px 边框区分，读起来像「一长串分割线」而不是「7 个可独立操作的区块」。用户找不到入口，也没有「当前最该改哪一项」的暗示。

**E2 🔴 详情页右栏五段同构，主操作被夹在 chip 群之间**
- 现象：五段的头部都是 `Row[AppTheme.sectionAccent(context), Text(标题, sectionTitle)]`，随后统一 `SizedBox(height: gapS)`（post_detail_page.dart:357-362、386-391、456-461、519-524、560-566）。`_voteRow` 的 4 个 `ChoiceChip` 与 `_versionPicker` 的 4 个 `ChoiceChip` 外观完全相同（同名 `chipTheme`，post_detail_page.dart:369、472）。
- 为什么是问题：整栏从上到下的视觉密度几乎恒定 —— 画质 chip 群、操作按钮群、评分 chip 群三块紧挨着，只有 `FilledButton` 一处颜色稍重（post_detail_page.dart:395）。但「设为壁纸」是这个页面存在的理由，「评分」是低频且需登录的操作（post_detail_page.dart:162-168）。二者之间没有任何层级差，用户的视线落点由「哪块更宽」决定，而不是由重要性决定。

**E3 🟡 搜索页的三层「提示」抢同一块注意力**
- 现象：搜索框下方固定一行说明「快捷键 Ctrl+K 聚焦搜索框。加 rating:s 只搜安全内容。」（search_view.dart:283-292），右侧同行是结果总数 `_CountLabel`（search_view.dart:293），再下面是「最近搜索」标题行（search_view.dart:298-318），再下面是 chip 区。
- 为什么是问题：进入页面后，搜索框正下方 4 行全是「辅助信息」，谁都不是正文。结果总数（用户最关心的反馈）被塞在说明文字的右端，字号 13 + `bodySmall`，是全屏最弱的一档 —— 而它应该是「这次搜索回来了多少」的唯一强信号。

**E4 🟡 三个 tab 的 AppBar 完全同构，页面身份只剩标题文字**
- 现象：搜索 / 精选 / 收藏三个 tab 的 AppBar `actions` 都由 `HomePage` 统一提供（home_page.dart:251-277），内容区顶部又都是「一排控件 + 网格」（search_view.dart:163-189、feature_view.dart:177-221、favorite_view.dart:124-191）。
- 为什么是问题：三个 tab 的差异只体现在标题的两个字，切换时既没有颜色也没有结构上的身份差异。用户「切走了」和「刷新了」在视觉上分不清 —— 而这正是 `home_page.dart:37-39` 注释里担心的「像被刷新了」。

### F. 尺寸体系

**F1 🟡 三套硬宽度与一套自适应策略并存**
- 现象：`PostGrid` 自适应（`_targetColumnWidth = 260`，clamp 2–8，post_grid.dart:64、90-95）；`_TopStrip` 固定 `cardWidth = 200` / `height = 280`（feature_view.dart:37-38）；`_TagCard` 固定 `width: 180`（feature_view.dart:435）；设置列固定 `maxWidth: 880`（settings_page.dart:158）。
- 为什么是问题：窗口从最小 900 拉到 1360 时，网格列数从 3 变 5，但精选页的卡片、标签卡、设置列纹丝不动。同一屏里「会变的」和「不会变的」混排，缩放窗口时精选页会出现大片右侧留白。另外 1360 宽下 `_TopStrip` 恰好放 5 张卡（5×200+4×12=1048），可见区约 1100 宽 —— 视觉上像是「本来就排满了」，箭头提示反而多余。

**F2 🟡 详情页 7:4 分栏在最小窗口下会把资料挤成两行**
- 现象：`Expanded(flex: 7, child: _buildImage())` / `Expanded(flex: 4, child: _buildSidebar())`（post_detail_page.dart:227、229），无断点。
- 为什么是问题：900 最小宽时右栏约 (900-1)×4/11 ≈ 327，减 `pagePadding`×2 = 295；资料行 label 占 `labelColumnDetail = 64`，值只剩 231px —— 32 字符的 MD5 用 Consolas 13px 约 250px，必然折行。`Wrap` 里的三个按钮也会折到第二行。没有「窄于此就上下堆叠」的兜底。

**F3 🟡 滚动到底部的留白两套**
- 现象：`PostGrid` 底部 `padding.bottom = gapXxl = 32`（post_grid.dart:113-118）；`FeatureView` 的 ListView 用 `EdgeInsets.all(AppTheme.pagePadding)` 即四边 16（feature_view.dart:178）。
- 为什么是问题：两个都是「图片内容页」，滚到底时下方留白差一倍。精选页的最后一行标签卡几乎贴着窗口下沿。

**F4 🟡 骨架网格的列宽算法是复制粘贴**
- 现象：`SkeletonGrid._columnsFor` 里写 `(available / 260).floor().clamp(2, 8)`（state_message.dart:320-323），注释自认「与 PostGrid 同一套列宽算法」；`PostGrid._targetColumnWidth = 260`（post_grid.dart:64）。
- 为什么是问题：260 这个魔数在两处独立存在。改列宽目标时若只改 `PostGrid`，骨架与真实内容会错列 —— 而这正是该注释想防的事。同类问题还有骨架的 `tileCount`：搜索用默认 18、精选传 12（feature_view.dart:156）、收藏用默认 18（favorite_view.dart:122）。

### G. 动效

**G1 🟡 7 个 Duration 字面量绕过 6 档 token**
- 现象：`home_page.dart:450`（320ms）、`home_page.dart:124`（3s）、`post_detail_page.dart:422`（260ms）、`post_detail_page.dart:108`（1200ms）、`settings_page.dart:657`（1200ms）、`app_route.dart:33`（200ms）、`state_message.dart:224`（900ms）。
- 为什么是问题：theme.dart:66-71 的注释明确说「以前 90/150/200/300 混着用……连起来就没有节奏」并声称已收敛到 90–260ms。但 200（路由反向）、320（成功回弹）、900（骨架脉动）、1200×2（提示停留）仍在外，其中 320 与 260 只差 60ms 且都是「出现」，却一个是 token、一个是字面量。

**G2 🟡 两条曲线绕过 3 条 token**
- 现象：`Curves.easeOutBack`（home_page.dart:451、post_detail_page.dart:419）、`Curves.easeOut`（app_route.dart:26）。theme 只声明 `curveIn` / `curveOut` / `curveEmph`（theme.dart:92-98）。
- 为什么是问题：`easeOutBack` 在 home_page.dart:438-439 有正当理由（「回弹分量和成了这件事匹配」），但这条理由没有进 theme；详情页收藏回弹（post_detail_page.dart:417-422）复用了同一个曲线和相近的时长（260 vs 320），两处「回弹」其实是同一设计意图的两次独立实现。

### 5.1 Top 5（按修复收益排序）

1. **B2 + B1 的对比度**：名次徽章三色白字 2.38 / 2.64 / 3.09:1、Q 评级 3.08:1、成功胶囊文字 3.38:1 —— 全部低于 WCAG AA。这是唯一有客观判据的缺陷，且都在「用户必须读到」的位置。
2. **E1 + E2 的视觉焦点**：设置页 7 段等权、详情页 5 段同构，整个应用找不到「现在最该看哪」。这是其余问题的根因：一旦有了层级，间距/圆角的不一致才会被容忍或暴露。
3. **B3 + B4 + A1 的「卡片/竖条」多实现**：`cardTheme` 存在但不被遵守，主题的价值失效。
4. **D1 + D2 的可点性**：历史行不可点（功能缺口伪装成视觉缺口）、chip 删除区 24×24。
5. **C3 + C4 + C1/C2 的字号与图标游离值**：13 / 11 / 10 / 20 / 13(padding) 五个未登记值，是下一轮碎片化的种子。

---

## 6. 信息架构现状

### 6.1 五个 tab 各自承载什么

导航结构由 `_HomePageState._destinations` 定义（home_page.dart:79-85），顺序即 tab 顺序，`IndexedStack` 全部保活（home_page.dart:314-323）。

| tab | 标签 | 图标 | 内容 | 数据来源 | 首次进入是否联网 | 空态能力 |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 搜索 | `Icons.search` | 搜索框 + 快捷键说明 + 最近搜索（最多 8 条，仅存活于本次运行，search_view.dart:50、104-107）+ 瀑布流结果 + 翻页进度 | `state.search()`，首帧自动执行 `_submit('')` 拉最新（search_view.dart:55-61） | 是 | suggestions chip / 错误态有重试 |
| 1 | 每日精选 | `Icons.today_outlined` | 「今日高分」横排 TOP3（`_top(kept, 3)`）+ 「值得一看的标签」卡片墙（出现 ≥2 次的标签） | `/post.xml?tags=rating%3As&` 最多 5 页，按 24 小时窗口筛（feature_view.dart:33、84-97；daily_feature.dart:22、55-56） | 是（连翻最多 5 页） | 有「刷新」按钮 |
| 2 | 收藏 | `Icons.favorite_border` | 未登录：引导态；已登录：`N 张收藏` + 5 档排序下拉 + 瀑布流 | `state.loadFavorites()`，排序档位 `favoriteSortLabels`（app_state.dart:189-195） | 否（未登录直接返回引导态） | 仅有文字，无动作 |
| 3 | 历史 | `Icons.history` | `共 N 条记录（最多保留 500 条）` + 清空 + `ListTile` 列表（48px 缩略图 / 标签 / 时间 / 成败） | 本机 `HistoryStore`，`maxEntries = 500`（history_store.dart:21） | 否 | 仅有文字，无动作 |
| 4 | 设置 | `Icons.settings_outlined` | 7 个段：站点 / 账号 / 换壁纸 / 自动换壁纸 / 内容筛选 / 外观 / 关于 | 本机 `AppSettings` | 否 | — |

跨 tab 能力：

- 快捷键集中在 `HomePage`：`Ctrl+1..5` 切页、`Ctrl+Enter` 换壁纸、`F5` / `Ctrl+R` 刷新当前页、`Ctrl+K` 聚焦搜索（home_page.dart:136-183）。刷新信号是 `refreshTick`，各页在监听里自行判断 `state.currentTab` 是否指向自己（feature_view.dart:70、favorite_view.dart:50、search_view.dart:96）。
- AppBar 右侧：任务胶囊 / 成功提示 / 「换一张壁纸」按钮，全部 tab 共用（home_page.dart:251-277）。
- 详情页从 tab 0 / 1 / 2 压栈进入（search_view.dart:135-141、feature_view.dart:119-125、favorite_view.dart:74-80）；tab 3 / 4 不进入详情。
- 关于页只能从 tab 4 的「关于」段进入（settings_page.dart:413-417）。

信息架构的三个现状特征：

1. **五个 tab 里三个是网格、两个是列表/表单**，但三个网格之间只有数据源不同（站内检索 / 站内推荐 / 个人收藏），控件与交互完全一致。
2. **导航深度只有两层**：tab → 详情 / 关于。没有面包屑、没有二次侧栏。1360×900 下 NavigationRail 收起后（80px）内容区约 1280px 可用，第二层导航的位置是空白。
3. **tab 4（设置）承载了原 UWP 四个页面**（settings_page.dart:19-23：SettingPage + SettingWallpaperPage + SettingLockscreenPage + AccountView），信息密度最高，但视觉层级最平（见 E1）。

### 6.2 详情页右侧五段（自上而下）

定义在 `_buildSidebar`（post_detail_page.dart:330-345），容器是 `ListView(padding: all pagePadding=16)`，顺序如下：

| # | 段名 | 内容 | 控件结构 | 交互 | 行号 |
| --- | --- | --- | --- | --- | --- |
| ① | **画质** | 原图 / JPEG / 大图 / 预览 四档，无地址的版本 `onSelected: null` 变禁用 | `Row[sectionAccent + sectionTitle('画质')]` + `gapS` + `Wrap(spacing gapS=8)` × 4 `ChoiceChip` | 切换 `_version`，左图 `AnimatedSwitcher(durSlow=260)` 淡入 | 347-380 |
| ② | **操作** | 主按钮「设为壁纸」+ 次按钮「收藏」「复制图片地址」 | `Row[sectionAccent + sectionTitle('操作')]` + `gapS` + `FilledButton.icon` + `gapS` + `Wrap(spacing/runSpacing gapS=8)` × 2 `OutlinedButton.icon` | 壁纸：`_applying` 时图标换 12px 环；收藏：`TweenAnimationBuilder(0.7→1.0, 260ms, easeOutBack)` 回弹 + 图标临时换对勾 1200ms；复制：图标换对勾 1200ms | 382-449 |
| ③ | **评分** | great / good / none / bad 四档 | `Row[sectionAccent + sectionTitle('评分')]` + `gapS` + `Wrap(spacing gapS=8)` × 4 `ChoiceChip(label: Row[iconXs=16 + gapXs + Text])` | 需登录（否则 `AppToast.error`），成功后图标临时换对勾 | 451-500 |
| ④ | **资料** | 8 行：作者 / 分级 / 分数 / 尺寸 / 体积 / 上传 /（来源，可选）/ MD5 | `Row[sectionAccent + sectionTitle('资料')]` + `gapS` + 8 × `Padding(vertical: 6) > Row[label 宽 labelColumnDetail=64 + SelectableText]` | 值可选中复制；尺寸/体积/MD5 用 `Consolas 13 + tabularFigures` | 505-553 |
| ⑤ | **标签** | `post.tagList` 全部标签 + 「复制站点详情页地址」 | `Row[sectionAccent + sectionTitle('标签')]` + `gapS` + `Wrap(spacing 6, runSpacing 6)` × `ActionChip` + `gapM=12` + `TextButton.icon` | 点标签**复制该标签**（不是跳转搜索），图标临时换对勾 | 555-598 |

段与段之间的分隔：①②③ 之间是 `SizedBox(height: gapL=16)`，③④ 与 ④⑤ 之间是 `Divider(height: 32)`（post_detail_page.dart:334-342）。

现状问题（与第 5 节 E2 呼应）：

- **阅读顺序 ≠ 心智顺序**：画质在最上（实际是低频、在「设为壁纸」之前选一次即可），主操作第二，评分第三（低频 + 需登录），资料第四（8 行，最长），标签第五。而「这张图是什么」恰恰由 ④ ⑤ 回答，却被压在最下面。
- **五段头部完全同构**，唯一差异是内容控件。视觉上是一条平铺的清单，没有「主区 / 次区」。
- **AppBar 只显示 `#${post.id}`**（post_detail_page.dart:220），作者、分级、尺寸这些「身份信息」全部在右栏第 ④ 段，正文区（左侧大图）没有任何标题层。

---

## 附录：审计方法与边界

- 全部结论来自静态阅读 `app/lib` 下的 dart 源码；未运行 `flutter run`，未截图。所有「对比度」数值是按 WCAG 相对亮度公式对源码色值的计算，不是屏幕取样。
- 行号均由 `grep -n` 或逐行读取确认；文中每一处数值都可按「文件:行号」直接定位复核。
- 未审计：`app/lib/services/`（业务逻辑）、`app/lib/models/`、资源 `assets/`（Logo、级联模型）、Windows 原生壳层。`_zigtest` 与 `Imaging` 目录不在本次范围。
- 与既有文档 `docs/nanoui-feasibility.md` 无重叠；本文只描述现状，不提出改版方案。


# PRPR Flutter 版重构评审：架构、性能与 UI

> 评审对象：`app/lib`（37 个 Dart 文件，约 324KB）+ `app/test`。
> 方式：三路并行只读源码分析（架构 / 性能 / UI），关键结论已逐条抽查行号核实；未运行应用、未修改任何 `app/lib` 代码。
> 参考：`MIGRATION.md`（历史取舍）、`docs/ui-redesign.md`（现行设计语言）、`docs/nanoui-feasibility.md`（已否决换框架）。
> 注意：`docs/ui-audit.md` 描述的是改版前旧 UI，已过时，本报告以现行代码为准。

## 总体判断

**基础面良好，不需要推倒重来。** 分层清晰（models/services/ui）、裁剪与精选已是纯函数、关键处留了注入缝（YandeClient 可注入 http.Client、WallpaperEngine 可注入检测器）、人脸检测与设壁纸已走 `Isolate.run`、http.Client 复用、瀑布流懒加载 + 预取、设计 token 体系贯彻度高。

问题集中在四处：
1. **图像管线**：两处全分辨率解码（历史页缩略图、详情页默认原图）+ 壁纸管线两次全量解码与 PNG 重编码；
2. **重建与写入粒度**：全局 notifyListeners + Consumer 包 MaterialApp + 设置每键写盘；
3. **假交互**：排序菜单只弹 Toast、面包屑点击行为违背契约；
4. **可达性**：全 UI 层零 Semantics、弱对比度、小点击目标。

---

## P0：正确性与致命体验（先修这五件）

### 1. 投票/收藏成功判定不可靠（正确性 bug）
`services/yande_client.dart:285-287`：
```dart
return body.contains('<success>true</success>') ||
    body.contains('true') ||
    !body.contains('error');
```
任何不含 "error" 的 200 响应都算成功——登录过期返回的 HTML 页也会被判定为投票成功。
**改法**：只认明确的 success 字段/新分值，其余一律 false；为 vote/fetchVote 解析补单测。

### 2. 历史页用 40px 显示却解码全分辨率壁纸
`ui/pages/history_page.dart:186-195`：`Image.file` 无 `cacheWidth/cacheHeight`，而 filePath 指向屏幕分辨率的裁剪 PNG（`wallpaper_engine.dart:202,211`）。一张 4K RGBA ≈ 33MB，十行可见即远超默认 imageCache 100MB → 逐出抖动 + 反复解码 + 滚动卡顿。
**改法**：`Image.file(cacheWidth: (40 * devicePixelRatio).round())`，一行修复。

### 3. 详情页默认原图、全尺寸解码入缓存
`ui/pages/post_detail_page.dart:72-82` 优先 `source`；`:358-374` 的 CachedNetworkImage 无 `memCacheWidth/Height`。4000×6000 原图解码 ≈ 96MB，几乎吃满默认 imageCache，把瀑布流缩略图批量逐出；退页也不 evict。
**改法**：默认 sample/jpeg、按需切原图；`memCacheWidth = 画布物理宽`（LayoutBuilder × devicePixelRatio）；缩放超阈值再加载原图（两级加载）；显式配置 `PaintingBinding.instance.imageCache` 上限，退页 evict 大图。

### 4. 排序菜单是假控件
`ui/pages/search_view.dart:268-276`：`onPick` 只弹 `AppToast.info('排序：$v')`，标签恒为「评分 ↓」，没接任何排序。假下拉比没有更伤信任。
**改法**：接 `order:` 标签重查（收藏页已有先例 `app_state.dart:181-187`），或先移除入口。

### 5. 键盘/读屏不可达
全 `ui/` 无任何 `Semantics/semanticLabel`。导航轨 `_RailItem` 用 GestureDetector（`app_rail.dart:107-109`），不可聚焦、无 button 语义；`_WallpaperButton` 同（`home_page.dart:286`）。键盘用户只能靠 Ctrl+1..5。
**改法**：包 `FocusableActionDetector` + `Semantics(button: true, label: ...)`，焦点态复用 post_tile 已有的 2px 金环模式。

---

## P1：性能瓶颈（按影响排序）

### 6. 壁纸管线：两次全量解码 + PNG 重编码 + 整字节下载
- `wallpaper_engine.dart:323-324`：`_decodeSize` 实为 getNextFrame 全解码（与注释不符）；`:388-389` 裁剪再解一次全图；`:409-411` PNG 编码（无损但慢且大）。
- 缩略图走「PNG 编码 → cv.imdecode」往返（`:373` → `face_detector.dart:129`）。
- `yande_client.dart:339-344`：http.get 整包缓冲下载，12s 超时覆盖整个下载（`:75,91`）→ 慢代理下大图必失败；且 `.timeout` 不取消底层请求。
**改法**：解码→裁剪→编码合并进一次 `Isolate.run`，复用已编译的 opencv imgcodecs/imgproc（cv.imdecode / cv.imwrite JPEG）；下载改 `HttpClient.getUrl + IOSink` 流式落盘；拆分连接/读取超时。

### 7. 重建粒度粗：换一次壁纸全页重建约 7 次
每阶段 `notifyListeners`（`app_state.dart:260,264-267,273`），而 home/search/favorite/history 均 `watch<AppState>`，IndexedStack 五页常驻。搜索框每键 `setState` 整页含 PostGrid 重建（`search_view.dart:230`）。
**改法**：`currentStage` 改 `ValueNotifier`（项目已有 `wallpaperAppliedTick` 范式，`app_state.dart:232`）；页面用 `context.select<AppState, T>`；输入行用 ValueListenableBuilder 局部化。

### 8. 设置写放大 × 全应用主题重建
黑名单输入每键 jsonEncode + 写盘 + notify（`settings_page.dart:686-687` → `app_settings.dart:135-138`）；`Consumer<AppSettings>` 包整个 MaterialApp（`main.dart:59`），每次重建完整 ThemeData（`theme.dart:163-176`）并触发全树主题过渡；设置页每 build 读 `s.filter` 7 次、每次 jsonDecode（`app_settings.dart:123-133`）。
**改法**：ThemeData 用 static final 缓存；文本类设置 debounce 300-500ms 或失焦提交；PostFilter 内存缓存；主题只 `context.select` themeModeIndex。

### 9. 启动串行 await + 首帧网络风暴
`main.dart:24-40` 串行 await windowManager → AppState.create（settings + history 在主 isolate readAsString + jsonDecode）才 runApp。IndexedStack 同时构建五页，搜索/精选/收藏都在 postFrameCallback 发请求；精选串行最多 5 页（`feature_view.dart:35,86-99`），最坏 5×12s。
**改法**：先 runApp 占位骨架，`Future.wait` 并行初始化后注入；非当前页懒构建；精选页并行拉页（保留停止条件）。

### 10. 搜索并发竞态
`app_state.dart:114-165`：search/loadMore 共享单一 isLoading/error，无请求序号、无取消——快速换词时旧请求返回会覆盖新结果。
**改法**：每个 query 记 generation 序号，返回时比对再写缓存，过期请求丢弃。

---

## P1：架构与 UI 其余重点

| # | 问题 | 证据 | 改法 |
|---|---|---|---|
| 11 | 精选页把网络翻页写在 UI 里，与搜索/收藏分页放置不一致 | `feature_view.dart:76-119` | 抽 FeatureLoader 到 services，UI 只持结果，顺带可测 |
| 12 | 测试只覆盖纯逻辑，网络解析层零测试 | `app/test/prpr_test.dart`（260 行）；parsePostsXml/hashPassword/vote 解析均为静态纯函数 | 构造函数已支持注入 httpClient（`yande_client.dart:56`），用 MockClient 补解析与错误翻译测试 |
| 13 | inkFaint 对比度不达标 | `#666D7C` on `#0B0C0E` = **3.77:1**（< 4.5:1）；搜索占位符 inkFaint@0.55 ≈ 1.9:1（`search_view.dart:251`） | 提亮至 `#7E8697`（≈5.3:1）；占位符至少用实色。金色主对比 8.86:1 优秀，不动 |
| 14 | 历史行不可点，「找回来」核心价值缺失 | `history_page.dart:165-241` 只有 hover 无 onTap；ui-redesign §4.5 已要求补 | 点击进详情或一键重设壁纸 |
| 15 | 破坏性操作不一致 | 退出登录无确认（`settings_page.dart:433-444`）；清空历史确认键是金色 FilledButton（`history_page.dart:52-55`） | 统一「确认对话框 + danger 描边确认键」 |
| 16 | 面包屑点击=复制而非回跳，违背组件契约 | `post_detail_page.dart:260-265` vs `app_topbar.dart:81`；标签 chip 复制无提示（`:743-745`） | 改为回跳搜索，或加「点击复制」tooltip |
| 17 | TOP 徽章压住分级点 | `feature_view.dart:353-357` 与 `post_tile.dart:179-183` 同在 left8/top8 | 徽章移右上 |

---

## P2：打磨项

**架构**
- AppState 轻度上帝对象（339 行，集缓存/编排/UI 信号/定时器）：拆 PostRepository（缓存+分页）与 WallpaperController（stage/tick/定时器），AppState 只做组合根；导航信号归 HomePage。
- `_pages` 按搜索串缓存无上限（`app_state.dart:59`）→ LRU 限约 10 个 query。
- 服务反向依赖 UI：`window_theme.dart:7` import `../ui/theme.dart`；`main.dart:81-84` 在 builder 里调 WindowTheme.apply（build 内副作用）→ WindowTheme 只收 Color/bool，apply 挪出 build。
- 引擎注入缝不全：`wallpaper_engine.dart:172,451` 硬调 ScreenInfo 静态、`:91-98` 硬编码 path_provider、`:85` Random 不可注入 → 作构造参数。
- `face_detector.dart:49-55` 用 50ms×100 轮询等级联落盘 → 改 Completer。级联每次检测重新解析 253KB XML（注释自认几十 ms，刻意取舍）→ 自动换壁纸频繁时可上常驻 worker isolate。
- `history_store.dart:44-46` 损坏静默重置、`:85-87` 写盘失败静默吞 → 记日志、损坏留 .bak。500 条封顶 + 全量 JSON 写符合规模，**不必上 SQLite**。

**UI**
- 大文件拆分：`settings_page.dart` 958 行（`_sectionBody` 一个 switch 装 7 节约 390 行，`_signIn` 混 UI 与登录流程）→ 按节拆独立 widget + AuthService；`post_detail_page.dart` 790 行 → 抽侧栏组件与 PostActions。
- Token 渗漏：fontSize 8/11.5/12.5/16 裸值（`app_rail.dart:171`、`app_topbar.dart:173`、`search_view.dart:236,375`）、`Color(0x47000000)`（`post_tile.dart:133`）、设置顶栏手写 Container 左边距 16 与其他页 32 不齐（`settings_page.dart:219-221`）→ 并入 AppTopBar。
- 焦点环弱（`theme.dart:376` 仅 gold@0.24 overlay）→ 四个按钮主题加 WidgetStateProperty focused → 2px gold side，一处全局生效。
- 点击目标过小：_ChipTap 26h、密度钮 26×26、最近搜索 chip 24h、设置目录行 36h → 视觉可小，命中区扩到 ≥32-40。
- Toast 无关闭按钮、成功消息走 error 红条通道（`settings_page.dart:152,437`）→ 补中性变体与关闭 action。
- 窄窗降级：最小 900×600 下详情固定 440px 右栏使图区仅约 395px → <1100 时右栏收 360；补 ←/→ 翻页与缩放比例指示。
- Slider/Switch 无关联标签（`settings_page.dart:790,828`）→ MergeSemantics 包行；动效未接 `MediaQuery.disableAnimations`。

### 组件提取建议

| 提取 | 来源（现状重复处） |
|---|---|
| `SettingRow` / `LabelValueRow` | settings `_row`:733、detail `_infoTable`:679、about `_kv`:158 三套 label+value |
| `AppChip`（统一高度/焦点/语义） | `_ChipTap`、`_RecentBar` chip、`_tagChip`、StateMessage ActionChip |
| `RailAction` 基座 | `_RailItem` 与 `_WallpaperButton` 共享 40×40 命中块 + tooltip |
| `AppConfirmDialog`（danger 变体） | history_page.dart:36-57 内联对话框，退出登录复用 |
| `PageTopBar`（页名+计数+动作槽） | 五页顶栏 Row 模式；settings 手写 Container 并入 |
| 登录空态并入 StateMessage | favorite_view.dart:89-123 手写图标+文案，加「去登录」动作 |
| `HScrollStrip` | feature `_TopStrip`:247 的箭头+边缘淡出横滚 |

### 建议的目标结构

```
lib/
  models/            # 不动
  domain/            # crop、daily_feature 等纯函数
  data/              # yande_client、history_store、app_settings、post_repository(新)、feature_loader(新)
  platform/          # wallpaper_service、face_detector、system_proxy、window_theme、screen_info（禁 import ui）
  ui/
    app_state.dart   # 瘦身为组合根
    theme.dart       # ThemeData 缓存
    widgets/         # + 上表提取的通用组件
    pages/           # settings 按节拆、detail 抽侧栏
```

---

## 建议实施顺序

| 阶段 | 内容 | 预期收益 |
|---|---|---|
| 一 | P0-1 投票判定 + P0-2/3 图像解码 + imageCache 配置 | 正确性 + 内存立减（历史页/详情页数量级下降） |
| 二 | 排序接线、Semantics/焦点环、inkFaint 提亮、历史行可点、破坏性操作统一 | 交互真实性 + 可达性 |
| 三 | currentStage ValueNotifier、context.select、ThemeData 缓存、设置 debounce、搜索竞态序号 | 重建与写放大消除 |
| 四 | 壁纸管线单次解码 + 流式下载、启动并行化、精选并行拉页 | 换壁纸耗时与启动首帧 |
| 五 | PostRepository/WallpaperController 拆分、settings/detail 拆文件、组件提取、网络层补测 | 可维护性，为后续功能铺路 |

每阶段独立可交付、可回滚；阶段一/二改动小、收益大，建议先做。

## 不建议做的事（尊重已有决策）

- 不恢复磁贴/锁屏/撤销任务框架（MIGRATION.md 已定）；
- 不换 nanoui 或其他 UI 框架（docs/nanoui-feasibility.md 已实测否决）；
- 不为 500 条历史上 SQLite；不换 Riverpod/Bloc（provider + select 够用）；
- 不引 image 包做裁剪（dart:ui 路径已验证）；不恢复 rating: 拦截弹窗；
- 不做整体 Rust 重写——性能敏感路径已在原生/GPU/isolate 层，Dart 只承担业务与 UI。

## 量化验证方法（profile 模式，修复前后对照）

1. **重建**：DevTools Inspector 开 Track widget builds，触发一次换壁纸与黑名单输入 10 字符，记录 SearchView/PostGrid/MaterialApp 重建次数。
2. **帧**：Performance 页 UI/Raster 帧图，滚动历史页与瀑布流找 >16.6ms 帧；开 ImageDecode 跟踪确认全尺寸解码事件。
3. **内存**：Memory 页开详情/滚历史前后快照，看 external/native（ui.Image）增量；debugPrint imageCache.liveImageCount/sizeBytes 验证逐出抖动。
4. **CPU**：换壁纸全程录火焰图，核对 instantiateImageCodec/toByteData 与 Isolate.run 检测占比。
5. **网络**：Network 时间线确认精选 5 页串行间隔与大图 12s 超时截断。
6. **启动**：进程启动到首帧时间线，对比 Future.wait 并行化前后。

> 本报告所有行号基于评审时的工作区代码；未预置任何实测性能数字，收益以 profile 对照为准。

---

## 实施记录（2026-11-24）

用户批准后按阶段一至五（选做）实施，三路并行、不相交写范围。

**改动规模**：17 个文件修改（+1215 / −573），新增 `app/test/yande_client_test.dart`。

**验证结果**：
- `flutter analyze --no-pub`：**No issues found**（9.3s）。
- `flutter test --no-pub`：**38 个测试全部通过**，含 P0 回归（含 3 的 HTML 不误判收藏；vote 成功 XML→true、登录页 HTML→false）。
- OpenCV 4.13.0 native assets 以 VS18 generator 重新编译成功。

**已完成**：P0 全部 5 项；P1 性能 6 项（管线单解码+JPEG、流式下载、重建粒度、写放大 debounce、启动并行、搜索竞态）；P1 架构/UI（精选并行、网络层测试、inkFaint 双色档达标、历史行可点、破坏性操作统一、面包屑回跳、TOP 徽章）；P2（LRU、Completer、存储容错、filter 缓存、ThemeData 缓存、焦点环、Semantics、Toast 中性变体、命中区、占位符对比度等）。

**环境修复（非代码问题）**：本机 VS 从 2022 升级到 18 BuildTools 后，dartcv4 的 CMake 缓存锁死旧 generator 且 GitHub 直连下载 OpenCV 在 10% 中断。验证时以进程级环境变量解决：`CMAKE_GENERATOR='Visual Studio 18 2026'` + `HTTP(S)_PROXY=http://127.0.0.1:7890`，并删除失效缓存目录 `.dart_tool/hooks_runner/shared/dartcv4/build/2824ffff81`。**永久修复建议**（任选其一，未擅自改系统设置）：
1. 用户级环境变量设 `CMAKE_GENERATOR=Visual Studio 18 2026`（本机只有 VS18）；
2. 或在 `app/pubspec.yaml` 的 `hooks.user_defines.dartcv4` 下加 `windows: { generator: 'Visual Studio 18 2026' }`（会影响其他 VS2022 机器，权衡后决定）。
代理环境变量同理：CMake 下载不读 WinINET 系统代理，只读 `HTTP(S)_PROXY`。

**已知取舍**：
- 壁纸管线合并 isolate 后，人脸检测走 `AnimeFaceDetector.detectOnDecodedMat`（静态、在已解码 Mat 上检测）；注入的 detector 实例仍负责级联落盘与 dispose，但其 `detectFromBytes` 不再影响壁纸人脸路径——单解码目标的必然代价，检测参数与结果一致。
- 裁剪输出 PNG→JPEG(90)，历史 filePath 扩展名随之变为 .jpg；旧 .png 记录仍可显示与重设（SystemParametersInfo 认内容）。
- 详情页放大 >2.5× 且非 source 时仅 Toast 提示切原图，不自动切（保守）。

**未做（阶段五结构重构，留待后续）**：AppState 拆 PostRepository/WallpaperController；settings_page/detail_page 大文件按节拆分；7 个通用组件提取（SettingRow/AppChip/RailAction/AppConfirmDialog/PageTopBar/HScrollStrip/登录空态）；window_theme 反向依赖解除；引擎 ScreenInfo/workDir/Random 注入缝；详情页窄窗降级与 ←/→ 翻页。这些改动面大、回归风险高，建议单独批次做。

---

## 实施记录·第二轮（2026-11-24 深夜）

用户报告：内容筛选不起作用；缺后台常驻/托盘/开机自启；要求排查同类功能问题与设置页空壳。

### 修复与新增

**内容筛选 bug（根因）**：`PostFilter.apply` 此前只接在壁纸引擎挑图处，搜索/收藏列表完全不过滤。修复：`AppState.postsFor` 缓存存原始结果、读取时实时 `filter.apply`；收藏页同样实时过滤；`_onSettingsChanged` 增加 notifyListeners 传播筛选变更；搜索计数改为筛选后条数；缓存命中判断改看原始数据。改分级/黑名单即时生效，放宽筛选无需重新联网。

**新功能（此前完全缺失）**：
- 托盘图标（tray_manager 0.8.3 新 nativeapi）：白猫 ico，右键菜单「显示主窗口 / 立即换一张壁纸 / 退出」，左键唤回；句柄字段持有防 GC；失败降级无托盘。
- 后台常驻：`setPreventClose(true)` + onWindowClose 按设置隐藏到托盘（进程存活、自动换壁纸继续）；托盘不可用时关窗强制真退出，避免唤不回。
- 开机自启：`HKCU\...\Run` 的 PRPR 值（reg.exe，无需管理员），设置页「05 系统」段两个开关（开机自启 / 关闭时最小化到托盘）。

**审计修复 8 项**：收藏排序 score/score_asc 文案对调；标签墙点击改按标签跳搜索（新增 externalSearchRequest 信号）；标签库接进精选（tagLookup 不再恒 null）；引擎兜底保留黑名单；精选页传完整 filter；关于页补「打开数据目录」入口；面包屑 index>0 按标签回跳搜索；语法提示 typo 修正；盐变更清空 passwordHash 提示重登。

### 验证
- analyze：No issues found；test：38 全过。
- 运行时实测：关窗 → 窗口隐藏、进程存活（常驻 ✓）；托盘溢出区 UIA 读到 'PRPR' 按钮 ✓；右键菜单截图确认三项 ✓。「显示主窗口」的桌面自动化点击因菜单焦点敏感未跑通，代码已审查（restore+show+focus），留用户一键确认。
- 构建环境：pubspec 变更使 native hook 哈希落到旧缓存目录（锁死 VS2022），删除旧哈希缓存后以 CMAKE_GENERATOR=VS18 重建成功（486s，OpenCV 重编译）。已重新安装到本地。

### 仍未做
阶段五结构重构（拆 AppState/大文件/组件提取）；死代码清理（锁屏相关是 MIGRATION 刻意保留，不动）。



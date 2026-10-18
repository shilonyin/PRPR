# 从 UWP 迁移到 Flutter：记录与理由

这份文档解释 **为什么** 现在的代码长这样。原版是 laplamgor 的 `PRPR.UWP`（C# / WinRT）
+ `Imaging.vcxproj`（C++ / OpenCV），最后一次提交在 2020 年 12 月，应用也已被微软下架。重写目标只有一个：
**保住原版真正被人使用的功能（浏览 booru + 自动挑图裁剪成壁纸），并让它在现在的机器上能编译、能运行。**

技术栈换成了 Flutter（Windows 桌面）。这不是为了追新：
原版依赖 Windows 10.0.17763 的 UWP 工具链，本机所有 VS 实例都装不出 `Microsoft.Windows.UI.Xaml.CSharp.targets`，
NuGet 还原直接以 `MSB4226` 失败——也就是说这个项目在今天的机器上**根本编译不起来**。
Flutter 桌面 + `win32` 包能直接调 `SystemParametersInfo` 设置壁纸，反而比 UWP 少一层沙箱限制。

## 文件对照

原码在 `PRPR/BooruViewer/` 与 `PRPR/`，新码在 `app/lib/`。

| 原文件 | 新文件 | 备注 |
| --- | --- | --- |
| `Models/Post.cs` | `models/post.dart` | 字段一一对应；`score` 原样保留为字符串（站点会给 `-1`） |
| `Models/PostFilter.cs` | `models/post_filter.dart` | 原版把字段编译成 `Func<Post,bool>`，这里改成值对象 + `apply`，便于纯 Dart 测试 |
| `Models/Posts.cs` | `models/posts_page.dart` | 分页结果 + 本地记录 `PostRecord` |
| `Models/Tag.cs`、`Services/TagDataBase.cs` | `models/tag.dart` | 标签类型、别名、相似度算法全部逐行保留 |
| `Services/YandeClient.cs` | `services/yande_client.dart` | 含 SHA1 密码哈希、登录、投票、收藏 |
| `Services/CropBitmap.cs` | `services/crop.dart` | 裁剪几何算法逐行复刻（含除零保护） |
| `Services/AnimePersonalization.cs` + `Imaging/`（C++/OpenCV） | `services/wallpaper_engine.dart` + `services/face_detector.dart` | 换壁纸全流程 + 人脸检测 |
| `Services/PersonalizationHelper.cs` | `services/wallpaper_service.dart` | 改用 `win32` 直接调 Win32 API |
| `Models/PersonalizationRecord.cs` + `Migrations/` | `services/history_store.dart` | SQLite → JSON 文件 |
| `Models/Global/YandeSettings.cs` | `services/app_settings.dart` | `ApplicationData` → `shared_preferences` |
| `ViewModels/HomeViewModel.cs` | `ui/app_state.dart` + `ui/pages/search_view.dart` | |
| `ViewModels/FeatureViewModel.cs` | `services/daily_feature.dart` + `ui/pages/feature_view.dart` | 纯计算部分抽成了可测的 `DailyFeature` |
| `ViewModels/ImageViewModel.cs` | `ui/pages/post_detail_page.dart` | |
| `Views/HomePage.xaml` | `ui/pages/home_page.dart` | Pivot → `NavigationRail` + `IndexedStack` |
| `Views/SettingPage` / `SettingWallpaperPage` / `SettingLockscreenPage` / `AccountView` | `ui/pages/settings_page.dart` | 四页合成一页分区，桌面端不需要四级导航 |
| `Views/AboutPage.xaml` | `ui/pages/about_page.dart` | |
| `Converters/*` | — | Flutter 侧直接内联判断，不需要转换器类型 |
| `Views/ConceptPage`、`SettingTilePage`、`LockScreenPreviewPage` | — | 见下面「砍掉的功能」 |
| `ExReader/` | — | 原 README 自己都划掉了 |

## 砍掉的功能，以及为什么

- **开始菜单磁贴**（`Services/AnimePersonalization.SetTileAsync`、`Tasks/TileUpdateTask.cs`、`Views/SettingTilePage.xaml`）
  Windows 11 已移除磁贴。留着等于给一个不存在的 UI 写代码。
- **锁屏壁纸**（`Tasks/LockscreenUpdateTask.cs`、`LockscreenUndoTask.cs`、`Views/LockScreenPreviewPage.xaml`）
  UWP 用的 `UserProfilePersonalizationSettings.TrySetLockScreenImageAsync` 只在 AppContainer 内可用；
  普通 Win32 进程没有对等接口（注册表里也没有对应项）。
  `WallpaperService.setLockScreen` 因此**显式返回「尚未实现」**——
  刻意不让它静默成功，否则用户会以为设置生效了。
- **撤销上一次换壁纸**（`WallpaperUndoTask.cs`）
  原版靠任务的持久化状态实现。新版的换图是同步完成的，"撤销" 变成了「在历史里点上一张」，
  不需要单独的任务框架。
- **AppContainer / Application Insights 遥测**
  前者随 UWP 一起消失；后者在应用已下架的项目里没有意义。

## 刻意改掉的行为

这些地方新代码**不等于**原代码，理由都写在对应的代码注释里：

1. **人脸检测在缩略图上做，再映射回原图**（`wallpaper_engine.dart` 的 `_detectFaces`）。
   与原版思路一致（原版在 preview 图上检测后 `ScaleFaces`），但触发条件不同：
   原版总是用 preview；这里在下载图长边超过 1024 时先缩到 1024 再检测。
   理由：级联参数（`minSize=30`）是在这一档尺寸下调出来的。
   直接对 4000px 原图跑 `detectMultiScale` 要几十秒，而且会把大量细小图案误判成人脸，
   反而让裁剪框偏离。**这是移植过程中最容易出错、也最难用肉眼发现的一处。**
2. **精选标签的封面**取「该标签下分数最高」的帖子；
   原版取 `score / 标签数` **最小**者。那个公式倾向于把冷门图当封面，
   实测效果不如直接取高分图。
3. **精选标签顺序**按标签名的 `hashCode` 稳定排序；原版每次 `Guid.NewGuid()` 随机，
   导致每次刷新整块内容都在跳。
4. **搜索不再拦截 `rating:` 标签**。原版检测到 `rating:` 就弹窗并把
   `IsRatingFilterUnlocked` 置真；桌面端用户明确输入 `rating:` 就是想按分级搜，
   弹窗打断更烦。标签数超过 6 的校验仍然保留。
5. **每日精选最多翻 5 页**。原版会一直翻到「帖子时间早于 24 小时前」为止，
   首屏等待时间不可控；这里收满 5 页（500 条）就停。
6. **历史记录用 JSON 文件**而不是 EF Core + SQLite。
   数据量是几百条级别，为它背一个平台插件（`sqlite3_flutter_libs`）和迁移维护成本不划算。
   写入用「先写 .tmp 再 rename」，避免断电留下半个文件。
7. **不裁剪时不重新编码**：直接把下载到的原图交给系统。
   裁剪过的那张输出 PNG（`dart:ui` 只能编码 PNG），Windows 认内容不认扩展名。

## 其余技术决策

- **裁剪**用 `dart:ui` 的 `Canvas.drawImageRect` + `Picture.toImage`，
  等价于原版的 `BitmapTransform.CroppedBitmap`，因此不需要引入 `image` 包。
- **裁剪算法**（居中 / 顶部居中 / 最大人脸 / 尽可能多人脸）在 `services/crop.dart` 里逐行复刻，
  包括原版「总空间为 0 时 ratio 取 0」的除零保护。这部分有单元测试兜底（`test/prpr_test.dart`），
  因为裁剪一旦偏掉，出来的壁纸就是切在脸上，肉眼很难发现是算法问题还是图片问题。
- **OpenCV 模块裁剪**：`dartcv4` 默认只编 `core + imgcodecs + imgproc`，
  而 `CascadeClassifier` 属于 `objdetect`。`app/pubspec.yaml` 的 `hooks.user_defines` 里
  显式声明了 `include_modules`——**`include_modules` 是整体替换而不是追加**，
  所以三个模块必须都写全。漏掉 `objdetect` 的症状是编译能过、运行时才炸。

## 环境要求

见 `app/README.md`。要点：Flutter 3.47+、**CMake 必须在 PATH 里**、VS 的 C++ 桌面工作负载。
`app/tool/build.ps1` 会自动把 CMake 找出来加进 PATH 再跑分析/测试/构建。
`app/tool/screenshot.ps1` 可以把窗口置顶后只截这个应用的窗口矩形（截图前会让进程 DPI 感知，
否则 125% 缩放下 `GetWindowRect` 给逻辑坐标、`CopyFromScreen` 按物理坐标拷，图会偏移并被裁掉一截）。

## 桌面版新增的两块基础设施

原版跑在 UWP 沙箱里，有两件事是系统白送的，搬到 Win32 桌面就得自己做：

**1. 系统代理（`app/lib/services/system_proxy.dart`）**

Dart 的 `HttpClient` 只读 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量，**完全不看**
Windows 的 WinINET 代理配置（注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`
下的 `ProxyEnable` / `ProxyServer`）。开发时从终端启动、环境变量还在，看不出问题；
一旦从桌面快捷方式双击，环境变量是空的，所有请求静默直连 —— 在国内表现为瀑布流空白、
缩略图一直转圈，而且界面上没有任何错误提示。

处理：`main()` 第一行调 `SystemProxy.install()`，先看环境变量、再读注册表，
用 `HttpOverrides.global` 给每个新建的 `HttpClient` 挂上 `findProxy`。
本机地址（localhost / 127.0.0.1 / ::1）走 `DIRECT`，否则访问本地服务会被代理搅乱。
**必须在创建任何 HttpClient 之前调用**，所以放在 `main()` 最开头、`WidgetsFlutterBinding` 之前。
不支持的：PAC（`AutoConfigURL`）—— 解析 PAC 要跑一遍 JS，不划算。

**2. 本机安装（`app/tool/install.ps1`）**

UWP 由商店负责安装和卸载，桌面版没有这层。脚本把 Release 目录复制到
`%LOCALAPPDATA%\Programs\PRPR`，用 `WScript.Shell` 建开始菜单和桌面快捷方式，
并在安装目录留一份自删的 `卸载.ps1`。不申请管理员权限、不写注册表，
所以「已安装程序」列表里看不到它 —— 这是刻意的取舍，省掉一整套安装器工程。

## 已知上游 bug：Windows 无障碍桥空指针（flutter/flutter#175041）

**症状**：release 版启动几秒后无任何 Dart 异常直接消失，退出码 `0xC0000005`（ACCESS_VIOLATION），
Windows 事件日志里出错模块是 `flutter_windows.dll`（release 下 Dart AOT 代码也在该模块内）。

**根因**（用 `dbghelp.dll` 离线符号化本机 PDB 得到的确切位置）：

```
flutter::AccessibilityBridge::CreateRemoveReparentedNodesUpdate + 0xba
  engine/src/flutter/shell/platform/common/accessibility_bridge.cc:229
229:  if (child->parent()->id() == node_update.second.id) {
226:  assert(child->parent());   // release 下 assert 被编掉 → 229 行直接解引用空指针
```

**触发链**：机器上存在 UIA/MSAA 客户端（屏幕阅读器、PowerToys 的 PowerOCR / QuickAccess、
自动化或截图工具）→ 引擎收到 `WM_GETOBJECT` 后打开无障碍桥（`flutter_window.cc` 的
`OnGetObject` → `OnUpdateSemanticsEnabled(true)`）→ 页面语义树在「一次涌入上百个节点」时发生
子节点重挂 → 命中上述空指针。

**对照实验**（都是本机实测，可复现）：
- 极简 `runApp(MaterialApp(home: Text(...)))` 版存活 → 引擎与构建链路没问题，崩的是我们的调用路径。
- `enable-impeller=false` 照样崩 → 与渲染后端无关。
- 把代理指向死端口（图片加载不到、语义树不抖动）：旧 UI 0/3 崩；正常联网：旧 UI 3/3 崩。
- 上游 issue 的符号化栈与本机完全一致；3.24.5 / 3.35.2 / 3.47.2 / 3.47.4 都能复现；
  本机比对 3.47.4 / 3.47.7 / master 三份 `accessibility_bridge.cc`，**该函数一字未改**
  → 升级 Flutter 解决不了。

**已修掉**（`app/windows/runner/flutter_window.cpp`）：在 Flutter 自己创建的
`FLUTTERVIEW` 子窗口上挂子类过程，把 `WM_GETOBJECT` 一律回 0（等于「本窗口没有可访问内容」），
引擎因此不会建无障碍树，那条崩溃路径也就不会被走到。

关键是**拦对窗口**：UIA 把 `WM_GETOBJECT` 发给 `FLUTTERVIEW` 子窗口，而不是 runner 的顶层窗口
`FLUTTER_RUNNER_WIN32_WINDOW` —— 早先只在顶层窗口过程里拦，实测完全无效（语义树照样启用、
AXTree 报错照样 7~13 条），原因是消息根本没经过那条路径。另外子类化必须**在
`SetChildContent` 之前**装上（用 `flutter_controller_->view()->GetNativeWindow()` 直接拿 HWND），
否则窗口可见后 UIA 客户端可能已经抢先问过一轮。

**A/B 实测**（Debug 版，每轮 30 秒，同一份二进制，用临时环境变量开关切换放行/拦截）：
- 放行 `WM_GETOBJECT`（等价旧行为）：4 轮里 1 轮在 18.3 秒崩（`0xC0000005`），
  stderr 的 `AXTree` 报错 9~117 条。
- 拦截 `WM_GETOBJECT`：4 轮全部存活，`AXTree` 报错**恒为 0 条**。
- 诊断日志（`ax_trace.log`）证实子窗口在启动约 30 毫秒内就收到了 4 次 `WM_GETOBJECT`
  （lparam 分别是 `0xfffffffc` OBJID_CLIENT 与 `0xfffffff4` OBJID_WINDOW），全部被拦下。

**代价**：屏幕阅读器等辅助技术读不到本应用的内容。对一个以图片为主的壁纸工具是可接受的取舍。
上游修好后（`flutter/flutter#175041` 关闭、或 `accessibility_bridge.cc:229` 出现空指针判断），
删掉这段子类化即可恢复无障碍支持。

# nanoui 能否替换 PRPR 的 Flutter UI —— 实测结论

探针工程：`F:\nanoui`（nanoui 仓库本地克隆）+ `examples/prpr_probe`。
探针截图：`docs/screenshots/zig-probe.png`（中文、JPEG、网络三件事在同一窗口里验证）。

## 结论：技术可行，但不建议接

图片显示这条路已经打通（见下），真正的问题不在「能不能画」，而在**要自己重写的东西太多**：

| 项目 | nanoui 提供 | PRPR 需要 | 缺口 |
| --- | --- | --- | --- |
| 文本输入 | `ui.textField`（textfield.zig） | 搜索框、站点地址、账号密码、标签 / 黑名单多行 | 只有单行文本缓冲，多行与富文本没有 |
| 下拉选择 | 无 | 画质、裁剪方式、排序、主题、契合度共 5 个 | 得自己写浮层 + 键盘导航 |
| 对话框 | 无 | 清空历史确认 | 得自己写模态层 |
| 提示条 / Toast | 无 | 错误提示、已保存 | 得自己写 |
| 虚拟列表 + 瀑布流 | `ui.list`（定高行） | 每列高度不等的瀑布流、列数随窗口宽度变化 | 得自己写布局 + 回收 |
| 图片网络缓存 | 无（要自己给 bytes） | 缩略图、预览图、原图三级 + 磁盘缓存 | 得自己写 |
| XML 解析 | 无（Zig std 也没有） | post.xml | 得手写或引第三方 |
| 设置持久化 | 无 | SharedPreferences 那套 | 得自己写 JSON/INI |
| 历史记录 | 无 | 换壁纸历史 + 缩略图 | 得自己写 |
| 国际化 / 本地化 | 无 | 全中文界面 | 文本自己管即可，问题不大 |

PRPR 现在的 UI 层是 123 个 Dart 文件、15,380 行 C# 级代码量（Dart 15K 行 + 26 个 XAML 折算），
其中真正「nanoui 能省掉」的只有布局与绘制；上面表里那些「缺口」全都得从零写，
而且没有热重载、没有 DevTools、没有 package 生态。

## 已经验证通过的部分

1. **中文渲染**：`ui.text` / `ui.label` 的中文正常显示。nanoui 的 `fallbacks` 列表里没有中文字体，
   但 `findFallback`（`src/ui/tt/fontdb.zig:180`）最后会退到「任意含该字形的 face」，扫到了本机的 `msyh.ttc`。
2. **JPEG 解码**：Windows 侧 nanoui 原生只带了 PNG 解码器（`src/ui/images.zig:11` 的 `portable` 分支）。
   本次把 stb_image 接进去（`src/ui/stb_shim.c` + `build.zig` 的 `addCSourceFile`），
   `decode()` 里先按魔数判断、不是 PNG 就走 stb。实测 1920x1200 与 3840x2160 都能正确解码并画进图集。
3. **HTTPS 拉取**：`std.http.Client` + `initDefaultProxies` 直连 yande.re 的 post.xml 返回 200。
   注意 std.http **不会**自动读 `HTTP_PROXY`，必须显式 `client.initDefaultProxies(a, init.environ_map)`。
4. **HTTP 代理访问 HTTPS 站点会失败**（实测两次，稳定复现）：设了 `HTTPS_PROXY=http://127.0.0.1:7897`
   之后请求返回 `HTTP 400`，响应体是 `400 The plain HTTP request was sent to HTTPS port` ——
   即 zig 把本来是 TLS 的连接当成明文发给了代理端口，`CONNECT` 隧道没建起来。
   这在国内是硬伤：yande.re 需要代理才能访问，而 zig std.http 目前走不通。

## 探针改造记录（nanoui 仓库内）

- `src/ui/images.zig`：`decode()` 增加 stb 分支；新增 `const stb = struct { extern fn stbi_load_from_memory… }`。
  Zig 0.17 已移除 `@cImport`，所以 C 侧走 `stb_shim.c`，Zig 侧只 `extern` 声明三个符号。
- `src/ui/stb_shim.c`（新增）：`#define STB_IMAGE_IMPLEMENTATION` + `STBI_NO_STDIO` + `STBI_ONLY_JPEG`。
- `src/ui/stb_image.h`（新增，283,010 字节，来自 nothings/stb master）。
- `build.zig`：非 macOS 目标 `addCSourceFile(.{ .file = b.path("src/ui/stb_shim.c") })` + `addIncludePath(b.path("src/ui"))`。
- `examples/prpr_probe/main.zig`：同时展示本地 JPEG 与站点缩略图，附带网络状态与错误体片段。

## 如果将来真要换

不是「换一个 UI 框架」，而是「用 Zig 重写整个 PRPR」。按现在的功能面，工作量约为现有 Dart 代码的 1.5～2 倍，
并且会失去热重载与 Flutter 生态（`cached_network_image`、`provider`、`shared_preferences`、
`flutter_svg`、`window_manager` 全部要换掉或手写）。

值得考虑的前提是：PRPR 要长期演进到比现在复杂得多的形态，且愿意承担 Zig 的学习与调试成本。
否则把 Flutter 版维护好、把 UI 打磨到位的收益远高于换栈。

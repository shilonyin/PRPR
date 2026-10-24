import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/post_filter.dart';
import '../../services/app_settings.dart';
import '../../services/crop.dart';
import '../../services/wallpaper_service.dart';
import '../../services/yande_client.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/app_route.dart';
import '../widgets/app_text_field.dart';
import '../widgets/app_toast.dart';
import '../widgets/section_header.dart';
import 'about_page.dart';

/// 设置页。对应原 UWP 的 `SettingPage` + `SettingWallpaperPage` +
/// `SettingLockscreenPage` + `AccountView` 四个页面。
///
/// 版式从「一页到底的卡片堆」改成了「左侧编号目录 + 右侧只显示一节」：
/// 八段全铺开时，用户要滚三屏才能找到某个开关，而且每张卡片都自带一圈
/// 描边，页面看起来像八块互不相干的补丁。现在一屏之内看得完，
/// 目录本身就是页面结构。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _saltController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _blacklistController = TextEditingController();

  bool _signingIn = false;

  /// 当前选中的目录项。
  ///
  /// 可用环境变量 PRPR_SETTINGS_SECTION=0..6 指定起始分节，与 home_page 的
  /// PRPR_TAB 同一套理由：桌面端没法可靠地模拟点击（150% DPI 下坐标换算
  /// 反复失准），要截某一节的图只能靠环境变量，不然每截一页都要改代码重编。
  int _index = _initialSection();

  static int _initialSection() {
    final raw = Platform.environment['PRPR_SETTINGS_SECTION'];
    final fromEnv = int.tryParse(raw ?? '');
    return (fromEnv ?? 0).clamp(0, _sections.length - 1);
  }

  /// 目录：编号 + 名称。编号走等宽字体，是这个页面的骨架。
  static const List<(String, String)> _sections = [
    ('01', '站点'),
    ('02', '账号'),
    ('03', '换壁纸'),
    ('04', '自动换壁纸'),
    ('05', '内容筛选'),
    ('06', '外观'),
    ('07', '关于'),
  ];

  /// 每一节顶部的说明。只写「这一节在决定什么」，不复述控件文案。
  static const List<String> _descriptions = [
    '连接哪个图站，以及登录表单里的隐藏字段。',
    '收藏、投票、看自己的收藏夹都需要登录。',
    '每次换壁纸时挑哪张、怎么裁、贴成什么比例。',
    '程序开着的时候，按间隔自动换。',
    '命中的图片不会出现在任何列表里。',
    '主题与显示偏好。',
    '版本、开源许可与致谢。',
  ];

  /// 滑块拖动中的临时值。拖动时只改这两个数，松手才写回设置：
  /// 以前每次 onChanged 都写一次 shared_preferences 并 notifyListeners 一次，
  /// 拖一次「随机范围」会触发三十来次全树重建和三十来次写盘。
  double? _shufflePreview;
  double? _autoMinutesPreview;

  /// 校验失败时的错误文案，直接显示在对应输入框下方（errorText）。
  String? _hostError;
  String? _userError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppSettings>();
    _hostController.text = s.host;
    _saltController.text = s.passwordHashSalt;
    _userController.text = s.userName ?? '';
    _tagsController.text = s.defaultTags;
    _blacklistController.text = s.filter.tagBlacklist;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _saltController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _tagsController.dispose();
    _blacklistController.dispose();
    super.dispose();
  }

  /// 只有失败才弹提示。成功会体现在界面状态上（登录后账号段变成已登录样式），
  /// 再弹一条「登录成功」等于让用户读一遍他刚看到的东西。
  void _toast(String message) {
    if (!mounted) return;
    AppToast.error(context, message);
  }

  void _clearHostError() {
    if (_hostError != null) setState(() => _hostError = null);
  }

  void _clearUserError() {
    if (_userError != null) setState(() => _userError = null);
  }

  void _clearPasswordError() {
    if (_passwordError != null) setState(() => _passwordError = null);
  }

  /// 读改存 [PostFilter]：设置页里每个开关都走这里。
  ///
  /// 用不可变 copyWith 而不是直接改字段，是刻意的 —— 过滤器会被
  /// `AppState` 按引用比较来跳过重复的列表重建。
  void _patchFilter(PostFilter Function(PostFilter) update) {
    final settings = context.read<AppSettings>();
    settings.filter = update(settings.filter);
    setState(() {});
  }

  void _applyHost() {
    final settings = context.read<AppSettings>();
    final value = _hostController.text.trim();
    if (value.isEmpty) {
      setState(() => _hostError = '站点地址不能为空');
      _toast('站点地址不能为空');
      return;
    }
    setState(() => _hostError = null);
    settings.host = value.replaceAll(RegExp(r'/+$'), '');
    _toast('已切换到 ${settings.host}');
  }

  Future<void> _signIn() async {
    final user = _userController.text.trim();
    final password = _passwordController.text;
    if (user.isEmpty || password.isEmpty) {
      setState(() {
        _userError = user.isEmpty ? '请输入用户名' : null;
        _passwordError = password.isEmpty ? '请输入密码' : null;
      });
      _toast('请填写用户名和密码');
      return;
    }
    setState(() {
      _signingIn = true;
      _userError = null;
      _passwordError = null;
    });
    final state = context.read<AppState>();
    try {
      final result = await state.client.signIn(user, password);
      if (!result.success) {
        setState(() => _passwordError = result.message ?? '登录失败');
        _toast(result.message ?? '登录失败');
        return;
      }
      final settings = state.settings;
      settings.userName = user;
      settings.userId = result.userId;
      settings.passwordHash =
          YandeClient.hashPassword(password, settings.passwordHashSalt);
      _passwordController.clear();
      // 登录成功不弹提示：账号段会立刻变成「已登录：xxx」的样子。
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final c = AppColor.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBar(c),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildNav(c),
              VerticalDivider(width: 1, thickness: 1, color: c.line),
              Expanded(child: _buildBody(context, c, settings)),
            ],
          ),
        ),
      ],
    );
  }

  /// 顶栏：页面名 + 一句话交代这一页的性质，右边挂版本号。
  ///
  /// 高度与浏览页顶栏一致（AppTheme.topbarHeight），切换 tab 时水平线不跳。
  Widget _buildTopBar(AppPalette c) {
    return Container(
      height: AppTheme.topbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapL),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('设置', style: AppType.section.copyWith(color: c.ink)),
          const SizedBox(width: AppTheme.gapM),
          Text(
            '偏好保存在本地 · 改动即时生效',
            style: AppType.caption.copyWith(color: c.inkFaint),
          ),
          const Spacer(),
          Text(
            'v${AboutPage.version}',
            style: AppType.monoData.copyWith(color: c.inkFaint),
          ),
        ],
      ),
    );
  }

  /// 左侧编号目录。
  ///
  /// 不再自带「设置 / PREFERENCES」标题块 —— 页面名已经在顶栏上写了一次，
  /// 目录里再写一遍只会把七个条目往下压 80px，第一屏反而看不到第三个以后。
  Widget _buildNav(AppPalette c) {
    return SizedBox(
      width: AppTheme.settingsNavWidth,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.gapL),
        children: [
          for (var i = 0; i < _sections.length; i++) _navItem(c, i),
        ],
      ),
    );
  }

  Widget _navItem(AppPalette c, int i) {
    final selected = i == _index;
    final (number, label) = _sections[i];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Material(
        color: selected ? c.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.railItemRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.railItemRadius),
          onTap: () => setState(() => _index = i),
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      number,
                      style: AppType.kicker.copyWith(
                        color: selected ? c.gold : c.inkFaint,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      label,
                      style: AppType.body.copyWith(
                        color: selected ? c.ink : c.inkDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppPalette c, AppSettings s) {
    final (number, label) = _sections[_index];
    // 不再居中限宽 900：窗口 2560 时右侧会空出两百多像素，行式列表的
    // 控件贴不到右边界，看起来像整体往左缩了一截。顶栏、导轨和这一列
    // 共用同一条右边距（pagePadding），宽屏才不会出现参差的右边缘。
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.gapXxl + 8,
        AppTheme.gapXl,
        AppTheme.pagePadding,
        AppTheme.gapXxl,
      ),
      children: [
        const _SavedHint(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              number,
              style: AppType.monoData.copyWith(color: c.gold),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: AppType.section.copyWith(color: c.ink),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _descriptions[_index],
          style: AppType.caption.copyWith(color: c.inkFaint),
        ),
        const SizedBox(height: 18),
        ..._sectionBody(context, c, s, _index),
      ],
    );
  }

  List<Widget> _sectionBody(
    BuildContext context,
    AppPalette c,
    AppSettings s,
    int index,
  ) {
    switch (index) {
      case 0:
        return [
          _row(
            c,
            label: '站点地址',
            hint: '支持 yande.re、konachan.com 等同构站点。改完点右侧应用。',
            controlWidth: 380,
            control: Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _hostController,
                    hint: AppConstants.defaultHost,
                    errorText: _hostError,
                    onChanged: (_) => _clearHostError(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _applyHost,
                  child: const Text('应用'),
                ),
              ],
            ),
          ),
          _row(
            c,
            last: true,
            label: '密码哈希盐',
            hint: '站点登录表单里的隐藏字段。yande 系站点默认值已填好，不用改。',
            controlWidth: 380,
            control: AppTextField(
              controller: _saltController,
              hint: 'password_salt',
              onChanged: (v) => s.passwordHashSalt = v.trim(),
            ),
          ),
        ];
      case 1:
        if (s.isLoggedIn) {
          return [
            _row(
              c,
              label: '当前账号',
              hint: '用户 ID ${s.userId ?? '-'}',
              controlWidth: 380,
              control: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  s.userName ?? '',
                  style: AppType.monoData.copyWith(color: c.ink),
                ),
              ),
            ),
            _row(
              c,
              last: true,
              label: '本地凭据',
              hint: '密码不会被保存，本地只留 SHA1 哈希。',
              controlWidth: 380,
              control: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '已登录',
                  style: AppType.monoData.copyWith(color: c.safe),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.gapXl),
            AppSectionHeader(
              '危险操作',
              danger: true,
              hint: '退出后收藏、投票都会失效，需要重新登录。',
            ),
            const SizedBox(height: AppTheme.gapS),
            _row(
              c,
              last: true,
              label: '退出登录',
              hint: '清除本机保存的用户名与密码哈希。',
              controlWidth: 380,
              control: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () {
                    s.signOut();
                    setState(() {});
                    _toast('已退出登录');
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.danger,
                    side: BorderSide(color: c.danger.withValues(alpha: 0.5)),
                  ),
                  child: const Text('退出登录'),
                ),
              ),
            ),
          ];
        }
        return [
          _row(
            c,
            label: '用户名',
            hint: '站点账号，不是邮箱。',
            controlWidth: 320,
            control: AppTextField(
              controller: _userController,
              hint: 'username',
              errorText: _userError,
              onChanged: (_) => _clearUserError(),
            ),
          ),
          _row(
            c,
            label: '密码',
            hint: '只在登录时用一次，不会留在本地。',
            controlWidth: 320,
            control: AppTextField(
              controller: _passwordController,
              hint: 'password',
              obscureText: true,
              errorText: _passwordError,
              onChanged: (_) => _clearPasswordError(),
              onSubmitted: (_) => _signIn(),
            ),
          ),
          _row(
            c,
            last: true,
            label: '登录',
            hint: '登录成功后账号段会变成已登录样式。',
            controlWidth: 320,
            control: Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _signingIn ? null : _signIn,
                child: Text(_signingIn ? '登录中…' : '登录'),
              ),
            ),
          ),
        ];
      case 2:
        return [
          _row(
            c,
            label: '裁剪方式',
            hint: '竖图贴到横屏上时怎么取舍。',
            control: _dropdown<int>(
              label: 'crop',
              value: s.cropMethodIndex,
              items: <int, String>{
                for (final m in CropMethod.values) m.value: _cropLabel(m),
              },
              onChanged: (v) => s.cropMethodIndex = v,
            ),
          ),
          _row(
            c,
            label: '画质',
            hint: '越高越清晰，也越费流量和带宽。',
            control: _dropdown<int>(
              label: 'quality',
              value: s.qualityLevel,
              items: const <int, String>{
                0: '预览图（快，省流量）',
                1: 'JPEG 大图（平衡）',
                2: '原图（最清晰）',
              },
              onChanged: (v) => s.qualityLevel = v,
            ),
          ),
          _row(
            c,
            label: '壁纸契合度',
            hint: '图片比例和屏幕不一致时怎么填。',
            control: _dropdown<int>(
              label: 'fit',
              value: s.fitMode,
              items: WallpaperService.fitModeLabels,
              onChanged: (v) => s.fitMode = v,
            ),
          ),
          _row(
            c,
            label: '随机范围',
            hint: '只在最新的这么多张里随机，越小越新鲜。',
            control: _slider(
              value: _shufflePreview ?? s.shuffleWindow.toDouble(),
              min: 1,
              max: AppConstants.maxShuffleWindow.toDouble(),
              divisions: AppConstants.maxShuffleWindow - 1,
              display:
                  '${(_shufflePreview ?? s.shuffleWindow.toDouble()).round()} 张',
              onChanged: (v) => setState(() => _shufflePreview = v),
              onChangeEnd: (v) {
                s.shuffleWindow = v.round();
                setState(() => _shufflePreview = null);
              },
            ),
          ),
          _row(
            c,
            last: true,
            label: '默认标签',
            hint: '没指定标签时用这串搜索。留空则从全站随机。',
            controlWidth: 340,
            control: AppTextField(
              controller: _tagsController,
              hint: 'landscape sky',
              onChanged: (v) => s.defaultTags = v.trim(),
            ),
          ),
        ];
      case 3:
        return [
          _row(
            c,
            label: '启用',
            hint: '程序开着的时候按下面的间隔自动换。',
            controlWidth: 320,
            control: Align(
              alignment: Alignment.centerRight,
              child: Switch(
                value: s.autoChangeEnabled,
                onChanged: (v) {
                  s.autoChangeEnabled = v;
                  setState(() {});
                },
              ),
            ),
          ),
          _row(
            c,
            last: true,
            label: '间隔',
            hint: '关闭「启用」后这一项不可调。',
            control: _slider(
              value:
                  (_autoMinutesPreview ?? s.autoChangeMinutes.toDouble())
                      .clamp(1, 1440),
              min: 1,
              max: 1440,
              divisions: 1439,
              display: _minutesLabel(
                (_autoMinutesPreview ?? s.autoChangeMinutes.toDouble())
                    .round(),
              ),
              onChanged: s.autoChangeEnabled
                  ? (v) => setState(() => _autoMinutesPreview = v)
                  : null,
              onChangeEnd: s.autoChangeEnabled
                  ? (v) {
                      s.autoChangeMinutes = v.round();
                      setState(() => _autoMinutesPreview = null);
                    }
                  : null,
            ),
          ),
          const SizedBox(height: AppTheme.gapL),
          Text(
            '只在程序运行时生效。关闭程序后不会再换；真正的后台定时属于另一个功能。',
            style: AppType.caption.copyWith(color: c.inkFaint),
          ),
        ];
      case 4:
        return [
          AppSectionHeader('分级'),
          _switchRow(
            c,
            label: 'Safe',
            hint: '全年龄。',
            value: s.filter.isFilterSafe,
            onChanged: (v) => _patchFilter((f) => f.copyWith(isFilterSafe: v)),
          ),
          _switchRow(
            c,
            label: 'Questionable',
            hint: '轻微擦边。',
            value: s.filter.isFilterQuestionable,
            onChanged: (v) =>
                _patchFilter((f) => f.copyWith(isFilterQuestionable: v)),
          ),
          _switchRow(
            c,
            label: 'Explicit',
            hint: '成人向。',
            value: s.filter.isFilterExplicit,
            onChanged: (v) =>
                _patchFilter((f) => f.copyWith(isFilterExplicit: v)),
          ),
          const SizedBox(height: AppTheme.gapXl),
          const AppSectionHeader('方向'),
          _switchRow(
            c,
            label: '横图',
            value: s.filter.isFilterHorizontal,
            onChanged: (v) =>
                _patchFilter((f) => f.copyWith(isFilterHorizontal: v)),
          ),
          _switchRow(
            c,
            label: '竖图',
            value: s.filter.isFilterVertical,
            onChanged: (v) =>
                _patchFilter((f) => f.copyWith(isFilterVertical: v)),
          ),
          const SizedBox(height: AppTheme.gapXl),
          const AppSectionHeader('其他'),
          _switchRow(
            c,
            label: '包含被隐藏的图片',
            hint: '站点标记为 hidden 的帖子。',
            value: s.filter.isFilterAllowHidden,
            onChanged: (v) =>
                _patchFilter((f) => f.copyWith(isFilterAllowHidden: v)),
          ),
          _switchRow(
            c,
            label: '包含被挂起的图片',
            hint: '审核中的帖子（held）。',
            value: s.filter.isFilterAllowHeld,
            onChanged: (v) =>
                _patchFilter((f) => f.copyWith(isFilterAllowHeld: v)),
          ),
          const SizedBox(height: AppTheme.gapM),
          _row(
            c,
            last: true,
            label: '标签黑名单',
            hint: '空格分隔。命中任一标签的图片不会出现在任何列表里。',
            controlWidth: 420,
            control: AppTextField(
              controller: _blacklistController,
              hint: '',
              minLines: 3,
              maxLines: 6,
              onChanged: (v) =>
                  _patchFilter((f) => f.copyWith(tagBlacklist: v.trim())),
            ),
          ),
        ];
      case 5:
        return [
          _row(
            c,
            last: true,
            label: '主题',
            hint: '跟随系统会随 Windows 的浅色/深色切换。',
            control: _dropdown<int>(
              label: 'theme',
              value: s.themeModeIndex,
              items: const <int, String>{0: '跟随系统', 1: '浅色', 2: '深色'},
              onChanged: (v) => s.themeModeIndex = v,
            ),
          ),
        ];
      default:
        return [
          _row(
            c,
            last: true,
            // 不再写「关于 PRPR / 版本 x.y.z，开源许可与致谢」——目录项已经叫
            // 「07 关于」，节说明也已经是「版本、开源许可与致谢」，行里再复述
            // 一遍，同一屏上「关于」出现三次、版本号出现两次。
            label: '开源许可与致谢',
            hint: '列出全部第三方依赖及其许可证全文。',
            controlWidth: 320,
            control: Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  appPageRoute<void>(builder: (_) => const AboutPage()),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ];
    }
  }

  /// 一行设置：左边标签 + 说明，右边控件。行与行之间只有一条 1px 分隔线，
  /// 不再套卡片 —— 八张卡片叠在一起时，页面看起来像被切成了八块。
  Widget _row(
    AppPalette c, {
    required String label,
    String? hint,
    required Widget control,
    double controlWidth = 320,
    bool last = false,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: c.line, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: AppType.body.copyWith(color: c.ink)),
                if (hint != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    hint,
                    style: AppType.caption.copyWith(color: c.inkFaint),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTheme.gapXl),
          SizedBox(
            width: controlWidth,
            child: Align(alignment: Alignment.centerRight, child: control),
          ),
        ],
      ),
    );
  }

  Widget _switchRow(
    AppPalette c, {
    required String label,
    String? hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      _row(
        c,
        label: label,
        hint: hint,
        control: Align(
          alignment: Alignment.centerRight,
          child: Switch(value: value, onChanged: onChanged),
        ),
      );

  Widget _dropdown<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    // 值可能因为历史数据落在合法集合之外，回退到第一项，避免 Dropdown 崩。
    final safeValue = items.containsKey(value) ? value : items.keys.first;
    return DropdownButtonFormField<T>(
      key: ValueKey<String>(label),
      initialValue: safeValue,
      isExpanded: true,
      items: [
        for (final entry in items.entries)
          DropdownMenuItem<T>(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _slider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double>? onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd ?? onChanged,
          ),
        ),
        const SizedBox(width: AppTheme.gapS),
        SizedBox(
          width: 72,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: AppType.monoData.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
        ),
      ],
    );
  }

  static String _cropLabel(CropMethod m) => switch (m) {
        CropMethod.none => '不裁剪',
        CropMethod.topMiddle => '顶部居中',
        CropMethod.center => '居中',
        CropMethod.biggestFace => '以最大的人脸为中心',
        CropMethod.mostFaces => '尽可能多的人脸',
      };

  static String _minutesLabel(int minutes) {
    if (minutes < 60) return '$minutes 分钟';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分';
  }
}

/// 设置项落盘后短暂出现的「已保存」。
///
/// 以前写盘是「同步改内存 + 异步落盘」，界面上完全看不出改了到底存没存，
/// 只能靠 SnackBar 念一句「保存成功」。这里把状态放回界面：一行小字亮一下，
/// 1.2 秒后自己走。
class _SavedHint extends StatefulWidget {
  const _SavedHint();

  @override
  State<_SavedHint> createState() => _SavedHintState();
}

class _SavedHintState extends State<_SavedHint> {
  static const Duration _hold = Duration(milliseconds: 1200);

  bool _visible = false;
  Timer? _timer;
  ValueNotifier<int>? _tick;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // saveTick 实例在应用生命周期内不变，这里天然只注册一次。
    final tick = context.read<AppSettings>().saveTick;
    if (identical(_tick, tick)) return;
    _tick?.removeListener(_onSaved);
    _tick = tick..addListener(_onSaved);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tick?.removeListener(_onSaved);
    super.dispose();
  }

  void _onSaved() {
    if (!mounted) return;
    setState(() => _visible = true);
    _timer?.cancel();
    _timer = Timer(_hold, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    // 固定高度：出现和消失都不推动下面的表单。
    return SizedBox(
      height: 28,
      child: AnimatedSwitcher(
        duration: AppTheme.durFast,
        switchInCurve: AppTheme.curveIn,
        switchOutCurve: AppTheme.curveOut,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: _visible
            ? Align(
                key: const ValueKey<String>('saved'),
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check,
                      size: AppTheme.iconXs,
                      color: c.safe,
                    ),
                    const SizedBox(width: AppTheme.gapXs),
                    Text(
                      '已保存',
                      style: AppType.monoData.copyWith(color: c.safe),
                    ),
                  ],
                ),
              )
            : const SizedBox(key: ValueKey<String>('idle')),
      ),
    );
  }
}

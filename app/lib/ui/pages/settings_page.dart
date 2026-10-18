import 'dart:async';

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
import 'about_page.dart';

/// 设置页。对应原 UWP 的 `SettingPage` + `SettingWallpaperPage` +
/// `SettingLockscreenPage` + `AccountView` 四个页面。
///
/// 原版拆成四页是因为手机竖屏一页放不下；桌面上横向空间足够，
/// 合到一页里用分区更省事，也避免用户在四个页面之间来回找。
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

  /// 用户一动手就把旧错误收掉，不要让它一直红着。
  void _clearHostError() {
    if (_hostError != null) setState(() => _hostError = null);
  }

  void _clearUserError() {
    if (_userError != null) setState(() => _userError = null);
  }

  void _clearPasswordError() {
    if (_passwordError != null) setState(() => _passwordError = null);
  }

  /// 读改存 [PostFilter]：设置页里每个勾选框都走这里。
  ///
  /// 用不可变 copyWith 而不是直接改字段，是刻意的 —— 过滤器会被
  /// `AppState` 按引用比较来跳过重复的列表重建。
  void _patchFilter(PostFilter Function(PostFilter) update) {
    final settings = context.read<AppSettings>();
    settings.filter = update(settings.filter);
    setState(() {});
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
      // 登录成功不弹提示：账号段会立刻变成「已登录：xxx」的样子，已经说清楚了。
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.pagePadding,
        AppTheme.pagePadding,
        AppTheme.pagePadding,
        48,
      ),
      // 内容列限宽 880 并居中：1900 宽的显示器上，输入框拉满整行会让
      // 标签和输入值离得太远，读一行要横跨半屏。
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SavedHint(),
                _section(context, '站点', [
                  _textField(
                    controller: _hostController,
                    label: '站点地址',
                    hint: AppConstants.defaultHost,
                    helper: '支持 yande.re、konachan.com 等同构站点。改完点右侧应用。',
                    icon: Icons.language,
                    errorText: _hostError,
                    onChanged: (_) => _clearHostError(),
                    trailing: FilledButton(
                      onPressed: () {
                        final value = _hostController.text.trim();
                        if (value.isEmpty) {
                          setState(() => _hostError = '站点地址不能为空');
                          _toast('站点地址不能为空');
                          return;
                        }
                        setState(() => _hostError = null);
                        settings.host = value.replaceAll(RegExp(r'/+$'), '');
                        _toast('已切换到 ${settings.host}');
                      },
                      child: const Text('应用'),
                    ),
                  ),
                  _textField(
                    controller: _saltController,
                    label: '密码哈希盐',
                    helper: '站点登录表单里的隐藏字段。yande 系站点默认值已填好，不用改。',
                    icon: Icons.vpn_key_outlined,
                    onChanged: (v) => settings.passwordHashSalt = v.trim(),
                  ),
                ]),
                _section(context, '账号', [
                  if (settings.isLoggedIn)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_circle_outlined),
                      title: Text(settings.userName ?? ''),
                      subtitle: Text('用户 ID：${settings.userId}'),
                      trailing: TextButton(
                        onPressed: () {
                          settings.signOut();
                          setState(() {});
                          _toast('已退出登录');
                        },
                        child: const Text('退出登录'),
                      ),
                    )
                  else ...[
                    Text(
                      '只有登录后才能收藏、投票、看自己的收藏夹。密码不会被保存，'
                      '登录成功后本地只留 SHA1 哈希。',
                      style: AppTheme.hint(context),
                    ),
                    const SizedBox(height: 12),
                    _textField(
                      controller: _userController,
                      label: '用户名',
                      icon: Icons.person_outline,
                      errorText: _userError,
                      onChanged: (_) => _clearUserError(),
                    ),
                    _textField(
                      controller: _passwordController,
                      label: '密码',
                      icon: Icons.lock_outline,
                      obscureText: true,
                      errorText: _passwordError,
                      onChanged: (_) => _clearPasswordError(),
                      onSubmitted: (_) => _signIn(),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _signingIn ? null : _signIn,
                        child: Text(_signingIn ? '登录中…' : '登录'),
                      ),
                    ),
                  ],
                ]),
                _section(context, '换壁纸', [
                  _dropdown<int>(
                    label: '裁剪方式',
                    value: settings.cropMethodIndex,
                    items: <int, String>{
                      for (final m in CropMethod.values) m.value: _cropLabel(m),
                    },
                    onChanged: (v) => settings.cropMethodIndex = v,
                  ),
                  _dropdown<int>(
                    label: '画质',
                    value: settings.qualityLevel,
                    items: const <int, String>{
                      0: '预览图（快，省流量）',
                      1: 'JPEG 大图（平衡）',
                      2: '原图（最清晰）',
                    },
                    onChanged: (v) => settings.qualityLevel = v,
                  ),
                  _dropdown<int>(
                    label: '壁纸契合度',
                    value: settings.fitMode,
                    items: WallpaperService.fitModeLabels,
                    onChanged: (v) => settings.fitMode = v,
                  ),
                  _slider(
                    label: '随机范围',
                    value:
                        _shufflePreview ?? settings.shuffleWindow.toDouble(),
                    min: 1,
                    max: AppConstants.maxShuffleWindow.toDouble(),
                    divisions: AppConstants.maxShuffleWindow - 1,
                    display: '${(_shufflePreview ?? settings.shuffleWindow.toDouble()).round()} 张',
                    // 拖动只更新本地预览，松手才写回设置。
                    onChanged: (v) => setState(() => _shufflePreview = v),
                    onChangeEnd: (v) {
                      settings.shuffleWindow = v.round();
                      setState(() => _shufflePreview = null);
                    },
                  ),
                  _textField(
                    controller: _tagsController,
                    label: '默认标签',
                    hint: '例如 landscape sky',
                    helper: '点「换一张壁纸」且没指定标签时用这串搜索。留空则从全站随机。',
                    icon: Icons.tag,
                    onChanged: (v) => settings.defaultTags = v.trim(),
                  ),
                ]),
                _section(context, '自动换壁纸', [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用'),
                    subtitle: const Text('程序运行期间按下面的间隔自动换'),
                    value: settings.autoChangeEnabled,
                    onChanged: (v) {
                      settings.autoChangeEnabled = v;
                      setState(() {});
                    },
                  ),
                  _slider(
                    label: '间隔',
                    value: (_autoMinutesPreview ??
                            settings.autoChangeMinutes.toDouble())
                        .clamp(1, 1440),
                    min: 1,
                    max: 1440,
                    divisions: 1439,
                    display: _minutesLabel(
                      (_autoMinutesPreview ??
                              settings.autoChangeMinutes.toDouble())
                          .round(),
                    ),
                    onChanged: settings.autoChangeEnabled
                        ? (v) => setState(() => _autoMinutesPreview = v)
                        : null,
                    onChangeEnd: settings.autoChangeEnabled
                        ? (v) {
                            settings.autoChangeMinutes = v.round();
                            setState(() => _autoMinutesPreview = null);
                          }
                        : null,
                  ),
                  if (settings.autoChangeEnabled)
                    Text(
                      '注意：只在程序开着的时候生效，关闭程序后不会再换。'
                      '想要真正的后台定时，需要本机计划任务，那是另一个功能。',
                      style: AppTheme.hint(context),
                    ),
                ]),
                _section(context, '内容筛选', [
                  const _SubHeader('分级'),
                  _check(
                    title: 'Safe',
                    value: settings.filter.isFilterSafe,
                    onChanged: (v) =>
                        _patchFilter((f) => f.copyWith(isFilterSafe: v)),
                  ),
                  _check(
                    title: 'Questionable',
                    value: settings.filter.isFilterQuestionable,
                    onChanged: (v) => _patchFilter(
                      (f) => f.copyWith(isFilterQuestionable: v),
                    ),
                  ),
                  _check(
                    title: 'Explicit',
                    value: settings.filter.isFilterExplicit,
                    onChanged: (v) =>
                        _patchFilter((f) => f.copyWith(isFilterExplicit: v)),
                  ),
                  const _SubHeader('方向'),
                  _check(
                    title: '横图',
                    value: settings.filter.isFilterHorizontal,
                    onChanged: (v) =>
                        _patchFilter((f) => f.copyWith(isFilterHorizontal: v)),
                  ),
                  _check(
                    title: '竖图',
                    value: settings.filter.isFilterVertical,
                    onChanged: (v) =>
                        _patchFilter((f) => f.copyWith(isFilterVertical: v)),
                  ),
                  const _SubHeader('其他'),
                  _check(
                    title: '包含被隐藏的图片',
                    subtitle: '站点标记为隐藏（hidden）的帖子',
                    value: settings.filter.isFilterAllowHidden,
                    onChanged: (v) =>
                        _patchFilter((f) => f.copyWith(isFilterAllowHidden: v)),
                  ),
                  _check(
                    title: '包含被挂起的图片',
                    subtitle: '审核中的帖子（held）',
                    value: settings.filter.isFilterAllowHeld,
                    onChanged: (v) =>
                        _patchFilter((f) => f.copyWith(isFilterAllowHeld: v)),
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    controller: _blacklistController,
                    label: '标签黑名单',
                    // 左标签列已经写明字段含义，框内不再重复占位文案。
                    hint: '',
                    helper: '空格分隔。命中任一标签的图片不会出现在任何列表里。',
                    icon: Icons.block,
                    // 至少 3 行好读，最多 6 行后自己滚，避免黑名单太长把页面撑爆。
                    minLines: 3,
                    maxLines: 6,
                    onChanged: (v) =>
                        _patchFilter((f) => f.copyWith(tagBlacklist: v.trim())),
                  ),
                ]),
                _section(context, '外观', [
                  _dropdown<int>(
                    label: '主题',
                    value: settings.themeModeIndex,
                    items: const <int, String>{0: '跟随系统', 1: '浅色', 2: '深色'},
                    onChanged: (v) => settings.themeModeIndex = v,
                  ),
                ]),
                _section(context, '关于', [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info_outline),
                    title: const Text('关于 PRPR'),
                    subtitle: const Text('版本、开源许可与致谢'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      appPageRoute<void>(
                        builder: (_) => const AboutPage(),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 左标签列。所有左标签表单（文本框 / 下拉 / 滑块）共用同一个宽度，
  /// 保证同一屏内标签文字起点都在 x=0，不再随控件类型左右跳。
  Widget _label(BuildContext context, String text) => SizedBox(
    width: AppTheme.labelColumnSettings,
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  /// 一个设置段：段标题 + 该段全部控件，整体装进一张浅底卡片。
  ///
  /// 8 个段都走这里，段与段之间统一 gapXl，卡片圆角/描边/底色也只在这里
  /// 定义一次，避免各段自己写一套看起来差 1px 的边框。
  Widget _section(BuildContext context, String title, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.gapXl),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.gapL),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(
            color: isDark ? const Color(0xFF26262F) : const Color(0xFFE8E8EF),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 竖条 + 标题：竖条用主题里的品牌色，段标题用 sectionTitle，
            // 页面里不再出现任何颜色字面量。
            Row(
              children: [
                AppTheme.sectionAccent(context),
                Text(title, style: AppTheme.sectionTitle(context)),
              ],
            ),
            const SizedBox(height: AppTheme.gapM),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helper,
    String? errorText,
    IconData? icon,
    Widget? trailing,
    bool obscureText = false,
    int? minLines,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    // 标签下沉到与输入框首行文字同高：输入框 contentPadding 上下各 14，
    // 加上边框 1，文字中心大约在 14 + 10 = 24 处，标签行高 20，所以补 14。
    const labelTopInset = 14.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: labelTopInset),
            child: _label(context, label),
          ),
          Expanded(
            child: AppTextField(
              controller: controller,
              hint: hint ?? label,
              helper: helper,
              errorText: errorText,
              prefixIcon: icon == null ? null : Icon(icon, size: 20),
              obscureText: obscureText,
              minLines: minLines,
              maxLines: maxLines,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: labelTopInset),
              child: trailing,
            ),
          ],
        ],
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    // 值可能因为历史数据落在合法集合之外，回退到第一项，避免 Dropdown 崩。
    final safeValue = items.containsKey(value) ? value : items.keys.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          _label(context, label),
          Expanded(
            child: DropdownButtonFormField<T>(
              initialValue: safeValue,
              isExpanded: true,
              items: [
                for (final entry in items.entries)
                  DropdownMenuItem<T>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double>? onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          _label(context, label),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              // 没给 onChangeEnd 就退回老行为（拖一下就落盘）。
              onChangeEnd: onChangeEnd ?? onChanged,
              label: display,
            ),
          ),
          SizedBox(
            width: 84,
            child: Text(display, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _check({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: value,
        onChanged: (v) => onChanged(v ?? false),
      );

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

class _SubHeader extends StatelessWidget {
  const _SubHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(text, style: AppTheme.hint(context)),
      );
}

/// 设置项落盘后短暂出现的「已保存」。
///
/// 以前写盘是「同步改内存 + 异步落盘」，界面上完全看不出改了到底存没存，
/// 只能靠 SnackBar 念一句「保存成功」。这里把状态放回界面：一行小字亮一下，
/// 1.2 秒后自己走。
///
/// 不做「每段一个」：一次动作常跨多个键（登录会同时写用户名、用户 ID、
/// 密码哈希），逐个标注归属的复杂度换不来更有用的信息。
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
    final theme = Theme.of(context);
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
                      Icons.check_circle_outline,
                      size: AppTheme.iconXs,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppTheme.gapXs),
                    Text(
                      '已保存',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox(key: ValueKey<String>('idle')),
      ),
    );
  }
}
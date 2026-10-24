import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../../services/app_settings.dart';
import '../../services/yande_client.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_topbar.dart';
import '../widgets/hero_flight.dart';
import '../widgets/section_header.dart';

/// 图片详情页。对应原 UWP 的 `ImagePage`。
///
/// 版式：56px 顶栏（返回 + 编号 + 面包屑 + 翻页）+ 左侧画布 + 右栏固定 440。
/// 左画布刻意比正文底色更暗（`AppPalette.canvas`），让图片自己浮起来 ——
/// 之前图区和侧栏同色，中间靠一条 1px 分隔线，看图的时候总觉得
/// 图片左边压着一块没用的灰。
class PostDetailPage extends StatefulWidget {
  const PostDetailPage({super.key, required this.post, this.heroPrefix = ''});

  final Post post;
  final String heroPrefix;

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  late PostImageVersion _version = _initialVersion();

  bool _busy = false;

  /// 「设为壁纸」自己是否在跑。与 [_busy] 分开：收藏 / 投票也会把
  /// [_busy] 置真，但那时候不该在「设为壁纸」按钮上转圈。
  bool _applying = false;

  VoteType? _currentVote;

  /// 哪个按钮刚刚「做成了事」，用来把图标临时换成对勾。
  String? _flashKey;
  Timer? _flashTimer;

  /// 收藏成功的回弹计数。每次收藏成功加一，让 TweenAnimationBuilder 重播。
  int _favBounce = 0;

  /// 左画布的底色。比 bg 再暗一档，把图片从页面里「托」出来。

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppSettings>();
    if (settings.isLoggedIn) {
      _refreshVote();
    }
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  Post get post => widget.post;

  /// 默认优先看原图；没有原图就退到 jpeg / sample。
  PostImageVersion _initialVersion() {
    for (final v in const [
      PostImageVersion.source,
      PostImageVersion.jpeg,
      PostImageVersion.sample,
      PostImageVersion.preview,
    ]) {
      if (post.urlFor(v).isNotEmpty) return v;
    }
    return PostImageVersion.preview;
  }

  Future<void> _refreshVote() async {
    final state = context.read<AppState>();
    final settings = state.settings;
    final userName = settings.userName;
    final hash = settings.passwordHash;
    if (userName == null || hash == null) return;
    try {
      final v = await state.client.fetchVote(
        userName: userName,
        passwordHash: hash,
        postId: post.id,
      );
      if (mounted) setState(() => _currentVote = v);
    } catch (_) {
      // 查询失败不打断浏览，保持未知状态
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    AppToast.error(context, message);
  }

  /// 复制、收藏这类动作成功后不再弹提示——按钮自己的形态变化就已经
  /// 把结果说完了，弹一条飘走的小条只会挡住图片。
  void _flash(String key) {
    _flashTimer?.cancel();
    if (mounted) setState(() => _flashKey = key);
    _flashTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _flashKey = null);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _showError(AppState.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyAsWallpaper() => _run(() async {
        final state = context.read<AppState>();
        if (mounted) setState(() => _applying = true);
        try {
          final result = await state.applyPost(post);
          // 失败要说清原因；成功时首页的任务胶囊会变成绿色对勾。
          if (!result.success) _showError(result.message);
        } finally {
          if (mounted) setState(() => _applying = false);
        }
      });

  Future<void> _toggleFavorite() async {
    final state = context.read<AppState>();
    final settings = state.settings;
    if (!settings.isLoggedIn) {
      _showError('请先在设置里登录才能收藏');
      return;
    }
    await _run(() async {
      final favorite = _currentVote != VoteType.favorite;
      final ok = await state.client.setFavorite(
        userName: settings.userName!,
        passwordHash: settings.passwordHash!,
        postId: post.id,
        favorite: favorite,
      );
      if (ok) {
        setState(() => _currentVote = favorite ? VoteType.favorite : VoteType.none);
        setState(() => _favBounce++);
        _flash('fav');
      } else {
        _showError('操作失败，请检查登录状态');
      }
    });
  }

  Future<void> _vote(VoteType v) async {
    final state = context.read<AppState>();
    final settings = state.settings;
    if (!settings.isLoggedIn) {
      _showError('请先在设置里登录才能投票');
      return;
    }
    await _run(() async {
      final ok = await state.client.vote(
        userName: settings.userName!,
        passwordHash: settings.passwordHash!,
        postId: post.id,
        vote: v,
      );
      if (ok) {
        setState(() => _currentVote = v);
        _flash('vote-${v.name}');
      } else {
        _showError('投票失败');
      }
    });
  }

  Future<void> _copyLink() async {
    final url = post.urlFor(_version);
    if (url.isEmpty) {
      _showError('该版本没有可用地址');
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    _flash('link');
  }

  @override
  Widget build(BuildContext context) {
    // Esc 返回列表。桌面用户从浏览器带来的肌肉记忆，成本只有这几行；
    // 键盘上按一下比把鼠标挪到左上角的返回箭头近得多。
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): _DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _DismissIntent: CallbackAction<_DismissIntent>(
            onInvoke: (_) {
              Navigator.of(context).maybePop();
              return null;
            },
          ),
        },
        child: _buildScaffold(),
      ),
    );
  }

  Widget _buildScaffold() {
    final c = AppColor.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopBar(c),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildImage()),
                VerticalDivider(width: 1, thickness: 1, color: c.line),
                SizedBox(width: AppTheme.sideWidth, child: _buildSidebar(c)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(AppPalette c) {
    final tags = post.tagList;
    return AppTopBar(
      child: Row(
        children: [
          AppBackButton(onPressed: () => Navigator.of(context).maybePop()),
          const SizedBox(width: AppTheme.gapS),
          Text(
            'No. ${post.id}',
            style: AppType.monoData.copyWith(color: c.ink),
          ),
          const SizedBox(width: AppTheme.gapL),
          if (tags.isNotEmpty)
            Expanded(
              child: AppBreadcrumb(
                parts: ['搜索', ...tags.take(2)],
                onTap: (index) {
                  final crumbs = ['搜索', ...tags.take(2)];
                  final part = crumbs[index];
                  Clipboard.setData(ClipboardData(text: part));
                  _flash('crumb-$part');
                },
              ),
            )
          else
            const Spacer(),
          if (_flashKey != null && _flashKey!.startsWith('crumb-'))
            Padding(
              padding: const EdgeInsets.only(right: AppTheme.gapS),
              child: Text(
                '已复制',
                style: AppType.kicker.copyWith(color: c.safe),
              ),
            ),
          IconButton(
            tooltip: '关闭（Esc）',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close, size: AppTheme.iconSm, color: c.inkDim),
          ),
        ],
      ),
    );
  }

  /// 大图区。
  ///
  /// 三件必须一起做的事：
  ///
  /// 1. **外框必须是紧约束**。Hero 的起终点矩形取自 Hero 自己的 render box，
  ///    以前 Hero 外面套着 `Center`，详情页这边拿到的是整块可用区域，两端
  ///    比例不同，飞行途中图会被拉伸。现在 Hero 只包住按原图比例算出的那个框。
  /// 2. **底层先放预览图**，用户选的画质解码要几百毫秒，让它自己淡入接住。
  /// 3. **换画质用淡入**，硬切会让整块图闪白一下，看起来像加载失败。
  Widget _buildImage() {
    final c = AppColor.of(context);
    final url = post.urlFor(_version);
    if (url.isEmpty) {
      return Center(
        child: Text(
          '该图片没有可显示的版本',
          style: AppType.caption.copyWith(color: AppColor.of(context).inkFaint),
        ),
      );
    }
    final previewUrl = post.urlFor(PostImageVersion.preview);
    // 极端长图按原比例铺开会把两侧留成大片空白，限一下。
    final ratio = post.preferredRatio.clamp(0.2, 5.0);

    return ColoredBox(
      color: c.canvas,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.gapXxl),
        child: Center(
          child: AspectRatio(
            aspectRatio: ratio,
            child: Hero(
              tag: '${widget.heroPrefix}${post.id}',
              flightShuttleBuilder: (
                flightContext,
                animation,
                direction,
                fromContext,
                toContext,
              ) =>
                  heroFlightShuttle(
                flightContext,
                animation,
                direction,
                fromContext,
                toContext,
                previewUrl.isEmpty ? url : previewUrl,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.imageRadius),
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 6,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 预览图铺底：cover 到同一个框，和瓦片看到的裁切一致。
                      if (previewUrl.isNotEmpty && previewUrl != url)
                        CachedNetworkImage(
                          imageUrl: previewUrl,
                          fit: BoxFit.cover,
                          fadeInDuration: AppTheme.durFast,
                          errorWidget: (context, _, _) =>
                              ColoredBox(color: c.surface),
                        ),
                      AnimatedSwitcher(
                        duration: AppTheme.durSlow,
                        switchInCurve: AppTheme.curveIn,
                        switchOutCurve: AppTheme.curveOut,
                        // 旧帧留在 Stack 里淡出，新帧淡入，中间不会露出底色。
                        child: CachedNetworkImage(
                          key: ValueKey<String>(url),
                          imageUrl: url,
                          fit: BoxFit.cover,
                          fadeInDuration: AppTheme.durMed,
                          fadeInCurve: AppTheme.curveIn,
                          // 底层已有预览图，这里不再转圈，否则圈会盖在图上。
                          placeholder: (context, _) => const SizedBox.shrink(),
                          errorWidget: (context, _, _) => Center(
                            child: Text(
                              '图片加载失败',
                              style: AppType.caption.copyWith(
                                color: c.inkDim,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(AppPalette c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 40),
      children: [
        Text(
          'MOEBOORU · POST',
          style: AppType.kicker.copyWith(color: c.gold),
        ),
        const SizedBox(height: AppTheme.gapS),
        // 标题用等宽字体：图站的作品名本身就是下划线连起来的一串，
        // 等宽下每个下划线位置对齐，比比例字体好扫。
        SelectableText(
          post.tagList.isEmpty ? 'No. ${post.id}' : post.tagList.first,
          style: AppType.title.copyWith(color: c.ink),
        ),
        const SizedBox(height: 6),
        Text(
          '${post.author.isEmpty ? '匿名' : post.author} · ${_formatDate(post.createdAtUtc)}',
          style: AppType.monoData.copyWith(color: c.inkFaint),
        ),
        const SizedBox(height: AppTheme.gapXl),
        _versionSegments(c),
        const SizedBox(height: AppTheme.gapL),
        _applyButton(c),
        const SizedBox(height: AppTheme.gapS),
        Row(
          children: [
            Expanded(child: _favoriteButton()),
            const SizedBox(width: AppTheme.gapS),
            Expanded(child: _copyButton()),
          ],
        ),
        const SizedBox(height: AppTheme.gapXl),
        _voteSection(c),
        const SizedBox(height: AppTheme.gapXl),
        const AppSectionHeader('资料'),
        const SizedBox(height: AppTheme.gapS),
        _infoTable(c),
        const SizedBox(height: AppTheme.gapXl),
        AppSectionHeader(
          '标签',
          trailing: Text(
            '${post.tagList.length}',
            style: AppType.monoData.copyWith(color: c.inkFaint),
          ),
        ),
        const SizedBox(height: AppTheme.gapS),
        _tagWrap(c),
        const SizedBox(height: AppTheme.gapM),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              final host = context.read<AppState>().client.host;
              final url = post.detailUrl(host);
              await Clipboard.setData(ClipboardData(text: url));
              _flash('detail-url');
            },
            icon: Icon(
              _flashKey == 'detail-url' ? Icons.check : Icons.open_in_new,
              size: AppTheme.iconXs,
            ),
            label: const Text('复制站点详情页地址'),
          ),
        ),
      ],
    );
  }

  /// 画质切换做成分段控件：四个标签等宽排开，选中的那块底色是 surface，
  /// 文字转金色。用 ChoiceChip 时每个 chip 宽度跟着字走，四个并排起来
  /// 像四个互不相干的按钮，而不是「同一件事的四个选项」。
  Widget _versionSegments(AppPalette c) {
    const versions = <(PostImageVersion, String)>[
      (PostImageVersion.source, '原图'),
      (PostImageVersion.jpeg, 'JPEG'),
      (PostImageVersion.sample, '大图'),
      (PostImageVersion.preview, '预览'),
    ];
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Row(
        children: [
          for (final (version, label) in versions)
            Expanded(
              child: _segment(
                c,
                label: label,
                selected: _version == version,
                enabled: post.urlFor(version).isNotEmpty,
                onTap: () => setState(() => _version = version),
              ),
            ),
        ],
      ),
    );
  }

  Widget _segment(
    AppPalette c, {
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final color = !enabled
        ? c.inkFaint.withValues(alpha: 0.5)
        : selected
            ? c.gold
            : c.inkDim;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppTheme.buttonRadius - 2),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius - 2),
        ),
        child: Text(
          label,
          style: AppType.chip.copyWith(color: color),
        ),
      ),
    );
  }

  /// 主操作占满整行。这是这个页面唯一的高饱和色块 ——
  /// 用户进来是想把图设成壁纸，其他动作都应该排在它后面。
  Widget _applyButton(AppPalette c) {
    return SizedBox(
      height: 42,
      child: FilledButton.icon(
        onPressed: _busy ? null : _applyAsWallpaper,
        // 只换左侧图标、不换文案：文案一变按钮就跳宽，鼠标还没来得及抬起来
        // 目标已经移走了。
        icon: _applying
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.wallpaper_outlined, size: AppTheme.iconSm),
        label: Text(
          _applying ? '正在设置…' : '设为壁纸',
          style: AppType.body.copyWith(
            color: c.onGold,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _favoriteButton() {
    return SizedBox(
      height: 38,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _toggleFavorite,
        // 收藏是用户主动、有明确结果的动作，值得被确认一次：图标先回弹
        // 一下，再落成实心或空心。easeOutBack 会过冲到 1.1 左右再回落到 1.0。
        icon: TweenAnimationBuilder<double>(
          key: ValueKey<int>(_favBounce),
          tween: Tween<double>(begin: 0.7, end: 1.0),
          curve: Curves.easeOutBack,
          duration: _favBounce == 0
              ? Duration.zero
              : const Duration(milliseconds: 260),
          builder: (context, value, child) => Transform.scale(
            scale: _favBounce == 0 ? 1 : value,
            child: child,
          ),
          child: Icon(
            _flashKey == 'fav'
                ? Icons.check
                : _currentVote == VoteType.favorite
                    ? Icons.favorite
                    : Icons.favorite_border,
            size: AppTheme.iconXs,
          ),
        ),
        label: Text(_currentVote == VoteType.favorite ? '已收藏' : '收藏'),
      ),
    );
  }

  Widget _copyButton() {
    return SizedBox(
      height: 38,
      child: OutlinedButton.icon(
        onPressed: _copyLink,
        // 复制成功把图标换成对勾：结果就落在用户点的地方。
        icon: Icon(
          _flashKey == 'link' ? Icons.check : Icons.link,
          size: AppTheme.iconXs,
        ),
        label: const Text('复制地址'),
      ),
    );
  }

  Widget _voteSection(AppPalette c) {
    // 四个评分等分一行。分数用等宽字：一串分数竖排下来时，
    // 比例字体会让每位数字的宽度都不一样。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          '评分',
          trailing: Text(
            post.score.isEmpty ? '—' : post.score,
            style: AppType.monoData.copyWith(
              color: c.gold,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
        ),
        const SizedBox(height: AppTheme.gapS),
        Row(
          children: [
            for (final v in const [
              VoteType.great,
              VoteType.good,
              VoteType.none,
              VoteType.bad,
            ]) ...[
              Expanded(
                child: _voteButton(c, v),
              ),
              if (v != VoteType.bad) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }

  Widget _voteButton(AppPalette c, VoteType v) {
    final selected = _currentVote == v;
    final flashed = _flashKey == 'vote-${v.name}';
    final color = selected ? c.gold : c.inkDim;
    return Tooltip(
      message: v.label,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: _busy ? null : () => _vote(v),
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.surface : Colors.transparent,
            border: Border.all(
              color: selected ? c.gold.withValues(alpha: 0.4) : c.line,
            ),
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                flashed ? Icons.check : _voteIcon(v),
                size: AppTheme.iconXs,
                color: flashed ? c.safe : color,
              ),
              const SizedBox(width: 5),
              Text(
                v.label,
                style: AppType.chip.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 投票类型对应的图标：正面用赞、负面用踩、「取消」用取消赞。
  static IconData _voteIcon(VoteType v) => switch (v) {
        VoteType.great || VoteType.good => Icons.thumb_up_alt_outlined,
        VoteType.bad => Icons.thumb_down_alt_outlined,
        _ => Icons.thumb_up_off_alt_outlined,
      };

  /// 资料区里这几行的值是数字，用等宽字体 + 等宽数字对齐。
  static const Set<String> _monoValueLabels = {'尺寸', '体积', 'MD5'};

  Widget _infoTable(AppPalette c) {
    final rows = <(String, String)>[
      ('作者', post.author.isEmpty ? '未知' : post.author),
      ('分级', _ratingLabel(post.rating)),
      ('分数', post.score.isEmpty ? '-' : post.score),
      ('尺寸', '${post.width}×${post.height}'),
      ('体积', _humanSize(post.fileSize)),
      ('上传', _formatDate(post.createdAtUtc)),
      if (post.source.isNotEmpty) ('来源', post.source),
      ('MD5', post.md5),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value) in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: c.line.withValues(alpha: 0.6)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: AppTheme.labelColumnDetail,
                  child: Text(
                    label,
                    style: AppType.caption.copyWith(color: c.inkFaint),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    value,
                    style: _monoValueLabels.contains(label)
                        ? AppType.monoData.copyWith(
                            color: c.ink,
                            fontFeatures: AppTheme.tabularFigures,
                          )
                        : AppType.body.copyWith(color: c.ink),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _tagWrap(AppPalette c) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in post.tagList)
          _tagChip(c, tag),
      ],
    );
  }

  Widget _tagChip(AppPalette c, String tag) {
    final flashed = _flashKey == 'tag-$tag';
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: tag));
        _flash('tag-$tag');
      },
      borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: flashed ? c.safe.withValues(alpha: 0.12) : c.surface,
          borderRadius: BorderRadius.circular(AppTheme.chipRadius),
          border: Border.all(
            color: flashed ? c.safe.withValues(alpha: 0.4) : c.line,
          ),
        ),
        child: Text(
          tag,
          style: AppType.chip.copyWith(color: flashed ? c.safe : c.inkDim),
        ),
      ),
    );
  }

  static String _ratingLabel(String rating) => switch (rating) {
        's' => 'Safe',
        'q' => 'Questionable',
        'e' => 'Explicit',
        _ => rating.isEmpty ? '未知' : rating,
      };

  static String _humanSize(int bytes) {
    if (bytes <= 0) return '-';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  static String _formatDate(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}

/// Esc 返回。单独声明一个 Intent 而不是复用 DismissIntent：
/// 后者在对话框里另有语义，详情页要的只是「退一层」。
class _DismissIntent extends Intent {
  const _DismissIntent();
}

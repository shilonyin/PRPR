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
import '../widgets/hero_flight.dart';

/// 图片详情页。对应原 UWP 的 `ImagePage`。
///
/// 原版页面有五栏（图片 / 标签 / 属性 / 操作 / 相关），这里压成两栏：
/// 左边大图可缩放拖动，右边是资料与操作。桌面端横屏空间足够，
/// 原版那种上下堆叠反而要一直滚动。
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

  /// 收藏成功的回弹计数。每次收藏成功加一，让 [TweenAnimationBuilder] 重播。
  int _favBounce = 0;


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

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppSettings>();
    if (settings.isLoggedIn) {
      _refreshVote();
    }
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
    return Scaffold(
      appBar: AppBar(
        title: Text('#${post.id}'),
        // 曾经在 actions 里挂一个 18px 的圈表示「有操作在跑」。但页内每个按钮
        // 自己就有进度反馈，顶部再转一个只会让人猜「到底是哪个在转」。
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 7, child: _buildImage()),
          const VerticalDivider(width: 1),
          Expanded(flex: 4, child: _buildSidebar()),
        ],
      ),
    );
  }

  /// 大图区。
  ///
  /// 这里有三件必须一起做的事：
  ///
  /// 1. **外框必须是紧约束**。Hero 的起终点矩形取自 Hero 自己的 render box，
  ///    以前 Hero 外面套着 `Center`，详情页这边拿到的是整块可用区域，瓦片那边
  ///    拿到的是卡片，两端比例不同，飞行途中图会被拉伸。现在 Hero 只包住
  ///    按原图比例算出的那个框，和瓦片一致。
  /// 2. **底层先放预览图**。预览图在列表里早就下好了，进页面立刻有东西看；
  ///    用户选的画质（常常是几 MB 的原图）解码要几百毫秒，让它自己淡入接住。
  /// 3. **换画质用淡入**。硬切会让整块图闪白一下，看起来像加载失败。
  Widget _buildImage() {
    final url = post.urlFor(_version);
    if (url.isEmpty) {
      return const Center(child: Text('该图片没有可显示的版本'));
    }
    final scheme = Theme.of(context).colorScheme;
    final previewUrl = post.urlFor(PostImageVersion.preview);
    // 极端长图按原比例铺开会把两侧留成大片空白，限一下。
    final ratio = post.preferredRatio.clamp(0.2, 5.0);

    return ColoredBox(
      color: scheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.gapL),
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
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
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
                              ColoredBox(color: scheme.surfaceContainerHighest),
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
                          placeholder: (context, _) =>
                              const SizedBox.shrink(),
                          errorWidget: (context, _, _) => Center(
                            child: Text(
                              '图片加载失败',
                              style: TextStyle(color: scheme.onSurfaceVariant),
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

  Widget _buildSidebar() {
    return ListView(
      padding: const EdgeInsets.all(AppTheme.pagePadding),
      children: [
        _versionPicker(),
        const SizedBox(height: AppTheme.gapL),
        _actionRow(),
        const SizedBox(height: AppTheme.gapL),
        _voteRow(),
        const Divider(height: 32),
        _infoSection(),
        const Divider(height: 32),
        _tagSection(),
      ],
    );
  }

  Widget _versionPicker() {
    final versions = <(PostImageVersion, String)>[
      (PostImageVersion.source, '原图'),
      (PostImageVersion.jpeg, 'JPEG'),
      (PostImageVersion.sample, '大图'),
      (PostImageVersion.preview, '预览'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppTheme.sectionAccent(context),
            Text('画质', style: AppTheme.sectionTitle(context)),
          ],
        ),
        const SizedBox(height: AppTheme.gapS),
        Wrap(
          spacing: AppTheme.gapS,
          children: versions.map((entry) {
            final (version, label) = entry;
            final available = post.urlFor(version).isNotEmpty;
            return ChoiceChip(
              label: Text(label),
              selected: _version == version,
              onSelected: available
                  ? (_) => setState(() => _version = version)
                  : null,
            );
          }).toList(growable: false),
        ),
      ],
    );
  }

  Widget _actionRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppTheme.sectionAccent(context),
            Text('操作', style: AppTheme.sectionTitle(context)),
          ],
        ),
        const SizedBox(height: AppTheme.gapS),
        // 只换左侧图标、不换文案：文案一变按钮就跳宽，鼠标还没来得及抬起来
        // 目标已经移走了。12px 的环足够表示「在跑」，也足够小到不挤动布局。
        FilledButton.icon(
          onPressed: _busy ? null : _applyAsWallpaper,
          icon: _applying
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wallpaper_outlined),
          label: const Text('设为壁纸'),
        ),
        const SizedBox(height: AppTheme.gapS),
        Wrap(
          spacing: AppTheme.gapS,
          runSpacing: AppTheme.gapS,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _toggleFavorite,
              // 收藏是用户主动、有明确结果的动作，值得被确认一次：图标先回弹
              // 一下，再落成实心或空心。
              icon: TweenAnimationBuilder<double>(
                key: ValueKey<int>(_favBounce),
                // easeOutBack 会过冲到 1.1 左右再回落到 1.0，这就是那次「心跳」。
                tween: Tween<double>(begin: 0.7, end: 1.0),
                curve: Curves.easeOutBack,
                duration: _favBounce == 0
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                builder: (context, value, child) => Transform.scale(
                  // 0.7 → 1.0 的 easeOutBack：先被压小再弹回并略微过冲。
                  scale: _favBounce == 0 ? 1 : value,
                  child: child,
                ),
                child: Icon(
                  _flashKey == 'fav'
                      ? Icons.check
                      : _currentVote == VoteType.favorite
                          ? Icons.favorite
                          : Icons.favorite_border,
                ),
              ),
              label: Text(_currentVote == VoteType.favorite ? '已收藏' : '收藏'),
            ),
            OutlinedButton.icon(
              onPressed: _copyLink,
              // 复制成功把图标换成对勾：结果就落在用户点的地方，不用去追一条
              // 从底下飘过去的提示。
              icon: Icon(_flashKey == 'link' ? Icons.check : Icons.link),
              label: const Text('复制图片地址'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _voteRow() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppTheme.sectionAccent(context),
            Text('评分', style: AppTheme.sectionTitle(context)),
          ],
        ),
        const SizedBox(height: AppTheme.gapS),
        Wrap(
          spacing: AppTheme.gapS,
          children: [
            for (final v in const [
              VoteType.great,
              VoteType.good,
              VoteType.none,
              VoteType.bad,
            ])
              ChoiceChip(
                // 评分组带赞 / 踩图标，和上面同构的画质组区分开。
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _flashKey == 'vote-${v.name}' ? Icons.check : _voteIcon(v),
                      size: AppTheme.iconXs,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppTheme.gapXs),
                    Text(v.label),
                  ],
                ),
                selected: _currentVote == v,
                onSelected: _busy ? null : (_) => _vote(v),
              ),
          ],
        ),
      ],
    );
  }

  /// 投票类型对应的图标：正面用赞、负面用踩、「取消」用取消赞。
  static IconData _voteIcon(VoteType v) => switch (v) {
        VoteType.great || VoteType.good => Icons.thumb_up_alt_outlined,
        VoteType.bad => Icons.thumb_down_alt_outlined,
        _ => Icons.thumb_up_off_alt_outlined,
      };

  /// 资料区里这三行的值是数字，用等宽字体 + 等宽数字对齐。
  static const Set<String> _monoValueLabels = {'尺寸', '体积', 'MD5'};

  Widget _infoSection() {
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppTheme.sectionAccent(context),
            Text('资料', style: AppTheme.sectionTitle(context)),
          ],
        ),
        const SizedBox(height: AppTheme.gapS),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: AppTheme.labelColumnDetail,
                  child: Text(label, style: AppTheme.hint(context)),
                ),
                Expanded(
                  child: SelectableText(
                    value,
                    style: _monoValueLabels.contains(label)
                        ? const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 13,
                            fontFeatures: AppTheme.tabularFigures,
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _tagSection() {
    final host = context.read<AppState>().client.host;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppTheme.sectionAccent(context),
            Text('标签', style: AppTheme.sectionTitle(context)),
          ],
        ),
        const SizedBox(height: AppTheme.gapS),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in post.tagList)
              ActionChip(
                avatar: _flashKey == 'tag-$tag'
                    ? const Icon(Icons.check, size: AppTheme.iconXs)
                    : null,
                label: Text(tag),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: tag));
                  _flash('tag-$tag');
                },
              ),
          ],
        ),
        const SizedBox(height: AppTheme.gapM),
        TextButton.icon(
          onPressed: () async {
            final url = post.detailUrl(host);
            await Clipboard.setData(ClipboardData(text: url));
            _flash('detail-url');
          },
          icon: Icon(
            _flashKey == 'detail-url' ? Icons.check : Icons.open_in_new,
          ),
          label: const Text('复制站点详情页地址'),
        ),
      ],
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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../../services/app_settings.dart';
import '../../services/yande_client.dart';
import '../app_state.dart';
import '../theme.dart';

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
  VoteType? _currentVote;

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

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyAsWallpaper() => _run(() async {
        final state = context.read<AppState>();
        final result = await state.applyPost(post);
        _toast(result.message);
      });

  Future<void> _toggleFavorite() async {
    final state = context.read<AppState>();
    final settings = state.settings;
    if (!settings.isLoggedIn) {
      _toast('请先在设置里登录才能收藏');
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
        _toast(favorite ? '已加入收藏' : '已取消收藏');
      } else {
        _toast('操作失败，请检查登录状态');
      }
    });
  }

  Future<void> _vote(VoteType v) async {
    final state = context.read<AppState>();
    final settings = state.settings;
    if (!settings.isLoggedIn) {
      _toast('请先在设置里登录才能投票');
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
        _toast('已投票：${v.label}');
      } else {
        _toast('投票失败');
      }
    });
  }

  Future<void> _copyLink() async {
    final url = post.urlFor(_version);
    if (url.isEmpty) {
      _toast('该版本没有可用地址');
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    _toast('已复制图片地址');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('#${post.id}'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
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

  Widget _buildImage() {
    final url = post.urlFor(_version);
    if (url.isEmpty) {
      return const Center(child: Text('该图片没有可显示的版本'));
    }
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 6,
            child: Center(
              child: Hero(
                tag: '${widget.heroPrefix}${post.id}',
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (context, _) =>
                      const Center(child: CircularProgressIndicator()),
                  errorWidget: (context, _, _) => Center(
                    child: Text(
                      '图片加载失败',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
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
        FilledButton.icon(
          onPressed: _busy ? null : _applyAsWallpaper,
          icon: const Icon(Icons.wallpaper_outlined),
          label: const Text('设为壁纸'),
        ),
        const SizedBox(height: AppTheme.gapS),
        Wrap(
          spacing: AppTheme.gapS,
          runSpacing: AppTheme.gapS,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _toggleFavorite,
              icon: Icon(
                _currentVote == VoteType.favorite
                    ? Icons.favorite
                    : Icons.favorite_border,
              ),
              label: Text(_currentVote == VoteType.favorite ? '已收藏' : '收藏'),
            ),
            OutlinedButton.icon(
              onPressed: _copyLink,
              icon: const Icon(Icons.link),
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
                      _voteIcon(v),
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
                label: Text(tag),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: tag));
                  _toast('已复制标签：$tag');
                },
              ),
          ],
        ),
        const SizedBox(height: AppTheme.gapM),
        TextButton.icon(
          onPressed: () async {
            final url = post.detailUrl(host);
            await Clipboard.setData(ClipboardData(text: url));
            _toast('已复制详情页地址：$url');
          },
          icon: const Icon(Icons.open_in_new),
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

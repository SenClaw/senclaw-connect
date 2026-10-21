import 'package:flutter/material.dart';
import '../../models/skill_history_models.dart';
import '../../models/api_models.dart' show ApiException;
import '../../services/language_service.dart';
import '../../services/plugins_api.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';

/// Every change to one skill: what changed it, the diff, what the security
/// scan said, how the skill has behaved since, and a way back. Mirrors the
/// web `SkillHistoryPanel` and the desktop History dialog.
class SkillHistoryScreen extends StatefulWidget {
  final String name;
  final String source;

  /// True only for skills in the managed directory.
  final bool canRollback;

  /// Runs after a successful restore, so the skill list can refresh.
  final VoidCallback? onRestored;

  /// The daemon calls; a test passes its own.
  final PluginsApi? api;

  const SkillHistoryScreen({
    super.key,
    required this.name,
    required this.source,
    required this.canRollback,
    this.onRestored,
    this.api,
  });

  @override
  State<SkillHistoryScreen> createState() => _SkillHistoryScreenState();
}

class _SkillHistoryScreenState extends State<SkillHistoryScreen> {
  late final PluginsApi _api = widget.api ?? PluginsApi();
  List<SkillRevision>? _revisions;
  Map<String, UsageVersion> _usage = const {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final h = await _api.skillHistory(widget.name, widget.source);
      if (!mounted) return;
      setState(() {
        _revisions = h.revisions;
        _error = null;
      });
      final usage = await _api.skillUsage(h.source, h.key);
      if (mounted) setState(() => _usage = usage);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _revisions = const [];
        _error = e is ApiException ? e.message : '$e';
      });
    }
  }

  String _ago(int ms) {
    final s = (DateTime.now().millisecondsSinceEpoch - ms) ~/ 1000;
    if (s < 60) return tr('vừa xong', 'just now');
    final m = (s / 60).round();
    if (m < 60) return tr('$m phút trước', '$m min ago');
    final h = (m / 60).round();
    if (h < 48) return tr('$h giờ trước', '$h h ago');
    final d = (h / 24).round();
    return tr('$d ngày trước', '$d days ago');
  }

  Color _tone(String tone) {
    switch (tone) {
      case 'brand':
        return AppTokens.brand;
      case 'brandAlt':
        return AppTokens.brandAlt;
      case 'cyan':
        return AppTokens.cyan;
      case 'danger':
        return AppTokens.danger;
      case 'warning':
        return AppTokens.warning;
      default:
        return Colors.grey;
    }
  }

  Future<void> _open(SkillRevision r, SkillRevision current) async {
    final restored = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      builder: (_) => _RevisionSheet(
        api: _api,
        name: widget.name,
        source: widget.source,
        revision: r,
        currentId: current.id,
        canRollback: widget.canRollback,
        tone: _tone,
      ),
    );
    if (restored == true) {
      widget.onRestored?.call();
      if (mounted) {
        setState(() => _revisions = null);
        _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: Text(
          '${tr('Lịch sử', 'History')} · ${widget.name}',
          style: TextStyle(color: c.textPrimary, fontSize: 16),
        ),
      ),
      body: _body(c),
    );
  }

  Widget _body(dynamic c) {
    final revs = _revisions;
    if (revs == null) return const LoadingState();
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    if (revs.isEmpty) {
      return EmptyState(
        icon: Icons.history,
        message: tr('Chưa có lịch sử', 'No history yet'),
        hint: tr(
          'Lịch sử của skill bắt đầu từ lần đầu nó được đổi qua SenClaw hoặc được daemon thấy.',
          "A skill's history starts the first time it is changed through SenClaw or seen by the daemon.",
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: revs.length,
        itemBuilder: (_, i) {
          final r = revs[i];
          final style = originStyle(r.origin);
          final u = _usage[r.contentHash];
          final warn = r.scan != null && r.scan!.verdict != 'allow';
          return Card(
            key: ValueKey('skill-revision-${r.id}'),
            color: c.surfaceAlt,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: c.border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _open(r, revs.first),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Chip(style.label, _tone(style.tone)),
                        if (i == 0)
                          _Chip(tr('hiện tại', 'current'), AppTokens.success),
                        if (warn)
                          _Chip(
                            tr(
                              'quét: ${r.scan!.findings.length}',
                              'scan: ${r.scan!.findings.length}',
                            ),
                            r.scan!.verdict == 'block'
                                ? AppTokens.danger
                                : AppTokens.warning,
                          ),
                        if (r.shadows != null)
                          _Chip(
                            tr(
                              'thay thế ${shadowedName(r.shadows!)}',
                              'overrides ${shadowedName(r.shadows!)}',
                            ),
                            AppTokens.warning,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      r.changeSummary.isEmpty ? '—' : r.changeSummary,
                      style: TextStyle(color: c.textPrimary, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_ago(r.createdAt)} · ${r.actor}',
                      style: TextStyle(color: c.textMuted, fontSize: 11),
                    ),
                    if (u != null)
                      Text(
                        tr(
                          '${u.loads} lần nạp · lỗi lượt ${pct(u.fallbackRate)} · tool hỏng ${pct(u.toolFailureRate)}',
                          '${u.loads} loads · fallback ${pct(u.fallbackRate)} · tool failures ${pct(u.toolFailureRate)}',
                        ),
                        style: TextStyle(color: c.textMuted, fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 11)),
  );
}

/// One revision in full: its scan findings, the diff, and Restore.
class _RevisionSheet extends StatefulWidget {
  final PluginsApi api;
  final String name;
  final String source;
  final SkillRevision revision;
  final String currentId;
  final bool canRollback;
  final Color Function(String) tone;
  const _RevisionSheet({
    required this.api,
    required this.name,
    required this.source,
    required this.revision,
    required this.currentId,
    required this.canRollback,
    required this.tone,
  });

  @override
  State<_RevisionSheet> createState() => _RevisionSheetState();
}

class _RevisionSheetState extends State<_RevisionSheet> {
  SkillRevision? _detail;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    widget.api
        .skillRevision(widget.name, widget.revision.id, widget.source)
        .then((r) {
          if (mounted) setState(() => _detail = r);
        })
        .catchError((_) {});
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Khôi phục bản này?', 'Restore this revision?')),
        content: Text(
          tr(
            'Các tệp của skill được đưa về như lúc đó. Nội dung hiện tại vẫn nằm trong lịch sử.',
            "The skill's files are put back as they were. The current content stays in the history.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Huỷ', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Khôi phục', 'Restore')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _restoring = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final done = tr('Đã khôi phục skill', 'Skill restored');
    final failed = tr(
      'Không khôi phục được bản này',
      'Could not restore this revision',
    );
    try {
      await widget.api.rollbackSkill(widget.name, widget.revision.id);
      messenger?.showSnackBar(SnackBar(content: Text(done)));
      navigator.pop(true);
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : failed)),
      );
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = _detail ?? widget.revision;
    final style = originStyle(r.origin);
    final why = r.restoreBlockedReason(
      canRollback: widget.canRollback,
      currentId: widget.currentId,
    );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  style.label,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('skill-history-restore'),
                onPressed: why == null && !_restoring ? _restore : null,
                icon: const Icon(Icons.restore, size: 16),
                label: Text(tr('Khôi phục', 'Restore')),
              ),
            ],
          ),
          if (why != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                why,
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '${DateTime.fromMillisecondsSinceEpoch(r.createdAt).toLocal().toString().split('.').first} · ${tr('thế hệ', 'generation')} ${r.generation} · ${r.fileCount} ${tr('tệp', r.fileCount == 1 ? 'file' : 'files')}',
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
          SelectableText(
            '${r.id} · sha256 ${r.contentHash.length >= 12 ? r.contentHash.substring(0, 12) : r.contentHash} · ${r.actor}${r.restoredFrom != null ? ' · ${tr('khôi phục từ', 'restored from')} ${r.restoredFrom}' : ''}',
            style: TextStyle(
              color: c.textMuted,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          if (r.shadows != null) ...[
            const SizedBox(height: 12),
            _Note(
              color: AppTokens.cyan,
              title: tr(
                'Skill này thay thế ${shadowedName(r.shadows!)} cùng tên.',
                'This skill replaces ${shadowedName(r.shadows!)} with the same name.',
              ),
              body: tr(
                'Skill trong thư mục quản lý được ưu tiên hơn skill dựng sẵn; bản kia bị ẩn khi bản này còn.',
                'Skills in the managed directory take precedence over bundled ones; the other one is hidden while this exists.',
              ),
            ),
          ],
          if (r.scan != null && r.scan!.findings.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Note(
              color: r.scan!.verdict == 'block'
                  ? AppTokens.danger
                  : AppTokens.warning,
              title: tr(
                'Quét bảo mật: ${r.scan!.findings.length} phát hiện (rủi ro ${r.scan!.riskScore}/100)',
                'Security scan: ${r.scan!.findings.length} findings (risk ${r.scan!.riskScore}/100)',
              ),
              body: r.scan!.findings
                  .map(
                    (f) =>
                        '${f.rule}  ${f.severity} — ${f.title} (${f.file}${f.line != null ? ':${f.line}' : ''})',
                  )
                  .join('\n'),
              mono: true,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            tr('THAY ĐỔI', 'CHANGE'),
            style: TextStyle(
              color: c.textMuted,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          if (r.diff == null)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            _DiffView(diff: r.diff!),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final Color color;
  final String title;
  final String body;
  final bool mono;
  const _Note({
    required this.color,
    required this.title,
    required this.body,
    this.mono = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            body,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: mono ? 11 : 12,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// A unified diff with the added and removed lines tinted.
class _DiffView extends StatelessWidget {
  final String diff;
  const _DiffView({required this.diff});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (diff.trim().isEmpty) {
      return Text(
        tr(
          'Nội dung không khác bản trước.',
          'No content difference from the previous revision.',
        ),
        style: TextStyle(color: c.textMuted, fontSize: 12),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in diff.trimRight().split('\n')) _line(c, line),
          ],
        ),
      ),
    );
  }

  Widget _line(dynamic c, String line) {
    final (bg, fg, weight) = switch (diffLineKind(line)) {
      DiffLineKind.added => (
        AppTokens.success.withValues(alpha: 0.16),
        AppTokens.success,
        FontWeight.w400,
      ),
      DiffLineKind.removed => (
        AppTokens.danger.withValues(alpha: 0.16),
        AppTokens.danger,
        FontWeight.w400,
      ),
      DiffLineKind.hunk => (
        AppTokens.brand.withValues(alpha: 0.14),
        AppTokens.brand,
        FontWeight.w400,
      ),
      DiffLineKind.header => (
        Colors.transparent,
        c.textPrimary as Color,
        FontWeight.w700,
      ),
      DiffLineKind.context => (
        Colors.transparent,
        c.textSecondary as Color,
        FontWeight.w400,
      ),
    };
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        line.isEmpty ? ' ' : line,
        softWrap: false,
        style: TextStyle(
          color: fg,
          fontWeight: weight,
          fontSize: 12,
          height: 1.5,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

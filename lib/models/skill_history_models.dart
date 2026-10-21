/// Wire shapes of the daemon's skill history and usage ledger
/// (`GET /api/skills/:name/history[/:rev]`, `POST /api/skills/:name/rollback/:rev`,
/// `GET /api/skill-usage/summary`; `../senclaw/docs/skill-history.md`).
///
/// A revision is one change to a skill directory: an API write, a hub install,
/// a rollback, a removal, or an edit found on disk.
library;

import '../services/language_service.dart';

class ScanFinding {
  final String rule;
  final String severity;
  final String title;
  final String file;
  final int? line;
  const ScanFinding(this.rule, this.severity, this.title, this.file, this.line);

  factory ScanFinding.fromJson(Map<String, dynamic> j) => ScanFinding(
    '${j['rule'] ?? ''}',
    '${j['severity'] ?? ''}',
    '${j['title'] ?? ''}',
    '${j['file'] ?? ''}',
    j['line'] is int ? j['line'] as int : null,
  );
}

/// What the security scan said about a revision. Never carries matched text.
class ScanSummary {
  final String verdict; // allow | warn | block
  final int riskScore;
  final List<ScanFinding> findings;
  const ScanSummary(this.verdict, this.riskScore, this.findings);

  factory ScanSummary.fromJson(Map<String, dynamic> j) => ScanSummary(
    '${j['verdict'] ?? 'allow'}',
    (j['riskScore'] as num?)?.toInt() ?? 0,
    ((j['findings'] as List?) ?? const [])
        .whereType<Map>()
        .map((f) => ScanFinding.fromJson(Map<String, dynamic>.from(f)))
        .toList(),
  );
}

class SkillRevision {
  final String id;

  /// MANUAL | IMPORTED | ROLLBACK | REMOVED | DETECTED | BASELINE
  final String origin;
  final String actor;
  final String contentHash;
  final int generation;
  final int fileCount;

  /// False for a removal, and once the content is older than the newest 30.
  final bool hasSnapshot;

  /// A size cap left something out: the revision cannot be restored.
  final bool truncated;
  final String? restoredFrom;
  final String changeSummary;

  /// The lower-precedence source this skill replaces, when it does.
  final String? shadows;
  final ScanSummary? scan;

  /// Epoch milliseconds.
  final int createdAt;

  /// Unified diff against the parent; only on a single-revision fetch.
  final String? diff;

  const SkillRevision({
    required this.id,
    required this.origin,
    required this.actor,
    required this.contentHash,
    required this.generation,
    required this.fileCount,
    required this.hasSnapshot,
    required this.truncated,
    required this.restoredFrom,
    required this.changeSummary,
    required this.shadows,
    required this.scan,
    required this.createdAt,
    this.diff,
  });

  factory SkillRevision.fromJson(Map<String, dynamic> j) => SkillRevision(
    id: '${j['id'] ?? ''}',
    origin: '${j['origin'] ?? ''}',
    actor: '${j['actor'] ?? ''}',
    contentHash: '${j['contentHash'] ?? ''}',
    generation: (j['generation'] as num?)?.toInt() ?? 0,
    fileCount: (j['fileCount'] as num?)?.toInt() ?? 0,
    hasSnapshot: j['hasSnapshot'] == true,
    truncated: j['truncated'] == true,
    restoredFrom: j['restoredFrom'] as String?,
    changeSummary: '${j['changeSummary'] ?? ''}',
    shadows: j['shadows'] as String?,
    scan: j['scan'] is Map
        ? ScanSummary.fromJson(Map<String, dynamic>.from(j['scan'] as Map))
        : null,
    createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
    diff: j['diff'] as String?,
  );

  /// Why this revision cannot be restored, or null when it can.
  String? restoreBlockedReason({
    required bool canRollback,
    required String currentId,
  }) {
    if (id == currentId) {
      return tr('Đây là bản hiện tại.', 'This is the current revision.');
    }
    if (origin == 'REMOVED') {
      return tr(
        'Bản gỡ không có nội dung riêng; hãy chọn bản ngay trước nó.',
        'A removal has no content of its own; pick the revision before it.',
      );
    }
    if (truncated) {
      return tr(
        'Bản này chạm giới hạn kích thước nên nội dung không đầy đủ.',
        'This revision hit a size cap, so its content is incomplete.',
      );
    }
    if (!hasSnapshot) {
      return tr(
        'Nội dung đã bị bỏ: chỉ 30 bản mới nhất còn giữ.',
        'Its content was dropped: only the newest 30 revisions keep it.',
      );
    }
    if (!canRollback) {
      return tr(
        'Chỉ skill trong thư mục skill được quản lý mới khôi phục được.',
        'Only skills in the managed skills directory can be restored.',
      );
    }
    return null;
  }
}

/// The ledger's numbers for one content version of a skill.
class UsageVersion {
  final int loads;
  final double? fallbackRate;
  final double? toolFailureRate;
  const UsageVersion(this.loads, this.fallbackRate, this.toolFailureRate);
}

String pct(double? r) => r == null ? '–' : '${(r * 100).round()}%';

/// Usage numbers keyed by content hash, from `GET /api/skill-usage/summary`,
/// for the skill at `(source, key)`.
Map<String, UsageVersion> usageByHash(
  dynamic summary,
  String source,
  String key,
) {
  final out = <String, UsageVersion>{};
  if (summary is! Map) return out;
  for (final s in (summary['skills'] as List?) ?? const []) {
    if (s is! Map || s['source'] != source || s['key'] != key) continue;
    for (final v in (s['versions'] as List?) ?? const []) {
      if (v is! Map || v['contentHash'] is! String) continue;
      out[v['contentHash'] as String] = UsageVersion(
        (v['loads'] as num?)?.toInt() ?? 0,
        (v['fallbackRate'] as num?)?.toDouble(),
        (v['toolFailureRate'] as num?)?.toDouble(),
      );
    }
  }
  return out;
}

/// A revision kind's label and the hint that explains it.
({String label, String hint, String tone}) originStyle(String origin) {
  switch (origin) {
    case 'MANUAL':
      return (
        label: tr('Đã sửa', 'Edited'),
        hint: tr(
          'Ghi qua SenClaw: tạo mới, ghi đè hoặc lưu trong trình soạn thảo.',
          'Written through SenClaw: created, overwritten or saved in the editor.',
        ),
        tone: 'brand',
      );
    case 'IMPORTED':
      return (
        label: tr('Đã cài', 'Installed'),
        hint: tr('Cài từ ClawHub.', 'Installed from ClawHub.'),
        tone: 'brandAlt',
      );
    case 'ROLLBACK':
      return (
        label: tr('Đã khôi phục', 'Restored'),
        hint: tr(
          'Đã đưa về một bản trước đó.',
          'Put back to an earlier revision.',
        ),
        tone: 'cyan',
      );
    case 'REMOVED':
      return (
        label: tr('Đã gỡ', 'Removed'),
        hint: tr(
          'Skill đã bị gỡ. Nội dung cuối cùng vẫn khôi phục được.',
          'The skill was removed. Its last content is still restorable.',
        ),
        tone: 'danger',
      );
    case 'DETECTED':
      return (
        label: tr('Đổi ngoài SenClaw', 'Changed outside SenClaw'),
        hint: tr(
          'Phát hiện khác trên đĩa: cài bằng CLI, kit hoặc trình soạn thảo. Cũng dùng để giữ lại bản có trước khi SenClaw ghi đè.',
          'Found different on disk: a CLI install, a kit, or a text editor. Also used to keep what was there just before SenClaw overwrote it.',
        ),
        tone: 'warning',
      );
    default:
      return (
        label: tr('Thấy lần đầu', 'First seen'),
        hint: tr(
          'Lần đầu SenClaw thấy skill này; không biết gì về trước đó.',
          'The first time SenClaw saw this skill; nothing earlier is known.',
        ),
        tone: 'muted',
      );
  }
}

/// "the bundled skill", for the source a skill replaces.
String shadowedName(String source) {
  switch (source) {
    case 'bundled':
      return tr('skill dựng sẵn', 'the bundled skill');
    case 'global-compat':
    case 'global-sema':
      return tr('skill dùng chung', 'the global skill');
    default:
      return tr('skill $source', 'the $source skill');
  }
}

/// Added / removed / hunk / header lines of a unified diff, for tinting.
enum DiffLineKind { added, removed, hunk, header, context }

DiffLineKind diffLineKind(String line) {
  if (line.startsWith('+++') || line.startsWith('---')) {
    return DiffLineKind.header;
  }
  if (line.startsWith('+')) return DiffLineKind.added;
  if (line.startsWith('-')) return DiffLineKind.removed;
  if (line.startsWith('@@')) return DiffLineKind.hunk;
  return DiffLineKind.context;
}

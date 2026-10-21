// SkillHistoryScreen (Connect): what it exists to communicate, all daemon
// decisions the screen must not soften — a revision that cannot be restored
// says why and has no live button, the scan findings and the shadow note are
// shown, and nothing is restored before the person confirms.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_connect/models/api_models.dart';
import 'package:senclaw_connect/models/skill_history_models.dart';
import 'package:senclaw_connect/screens/plugins/skill_history_screen.dart';
import 'package:senclaw_connect/services/plugins_api.dart';
import 'package:senclaw_connect/theme/app_theme.dart';

final _now = DateTime.now().millisecondsSinceEpoch;

SkillRevision _rev(
  String id,
  String origin, {
  String hash = 'aaa',
  bool hasSnapshot = true,
  String? shadows,
  ScanSummary? scan,
  int agoMs = 0,
  String? diff,
}) => SkillRevision(
  id: id,
  origin: origin,
  actor: 'api:readme',
  contentHash: hash.padRight(64, '0'),
  generation: 1,
  fileCount: 2,
  hasSnapshot: hasSnapshot,
  truncated: false,
  restoredFrom: null,
  changeSummary: '1 changed (+1 -1)',
  shadows: shadows,
  scan: scan,
  createdAt: _now - agoMs,
  diff: diff,
);

const _warn = ScanSummary('warn', 25, [
  ScanFinding(
    'INJ001',
    'high',
    'Instruction-override text in an agent prompt',
    'SKILL.md',
    8,
  ),
]);

/// A PluginsApi that never reaches a relay.
class _FakeApi extends PluginsApi {
  final calls = <String>[];
  final revisions = [
    _rev('rev_3', 'ROLLBACK', hash: 'aaa', agoMs: 60 * 1000),
    _rev('rev_2', 'MANUAL', hash: 'bbb', agoMs: 3 * 3600 * 1000, scan: _warn),
    _rev(
      'rev_1',
      'IMPORTED',
      hash: 'ccc',
      agoMs: 80 * 3600 * 1000,
      shadows: 'bundled',
    ),
    _rev(
      'rev_0',
      'BASELINE',
      hash: 'ddd',
      hasSnapshot: false,
      agoMs: 9 * 24 * 3600 * 1000,
    ),
  ];

  @override
  Future<({String source, String key, List<SkillRevision> revisions})>
  skillHistory(String name, String source) async {
    calls.add('history $name $source');
    return (source: source, key: name, revisions: revisions);
  }

  @override
  Future<SkillRevision> skillRevision(
    String name,
    String id,
    String source,
  ) async {
    calls.add('revision $id');
    final r = revisions.firstWhere((x) => x.id == id);
    return _rev(
      r.id,
      r.origin,
      hash: r.contentHash,
      hasSnapshot: r.hasSnapshot,
      shadows: r.shadows,
      scan: r.scan,
      diff:
          '--- a/SKILL.md\n+++ b/SKILL.md\n@@ -1,2 +1,2 @@\n keep\n-old line\n+new line\n',
    );
  }

  @override
  Future<void> rollbackSkill(String name, String id) async {
    calls.add('rollback $id');
  }

  @override
  Future<Map<String, UsageVersion>> skillUsage(
    String source,
    String key,
  ) async => {'bbb'.padRight(64, '0'): const UsageVersion(5, 0.6, 0.4)};
}

/// A daemon that refuses a restore with its own sentence.
class _RefusingApi extends _FakeApi {
  @override
  Future<void> rollbackSkill(String name, String id) async {
    throw const ApiException(409, 'this revision has no stored content');
  }
}

Future<void> _open(
  WidgetTester tester,
  PluginsApi api, {
  bool canRollback = true,
  VoidCallback? onRestored,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: SkillHistoryScreen(
        name: 'demo',
        source: 'clawhub-managed',
        canRollback: canRollback,
        onRestored: onRestored,
        api: api,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists every revision with its kind, scan badge and numbers', (
    tester,
  ) async {
    await _open(tester, _FakeApi());
    expect(tester.takeException(), isNull);
    for (final id in ['rev_3', 'rev_2', 'rev_1', 'rev_0']) {
      expect(find.byKey(ValueKey('skill-revision-$id')), findsOneWidget);
    }
    expect(find.textContaining('1 changed (+1 -1)'), findsNWidgets(4));
    // The numbers belong to the revision whose content they were counted on.
    expect(find.textContaining('60%'), findsOneWidget);
  });

  testWidgets(
    'an older revision opens with its diff and findings and can be restored after confirming',
    (tester) async {
      final api = _FakeApi();
      var restored = 0;
      await _open(tester, api, onRestored: () => restored++);

      await tester.tap(find.byKey(const ValueKey('skill-revision-rev_2')));
      await tester.pumpAndSettle();
      expect(find.textContaining('INJ001'), findsOneWidget);
      expect(find.text('-old line'), findsOneWidget);
      expect(find.text('+new line'), findsOneWidget);

      final restore = find.byKey(const ValueKey('skill-history-restore'));
      expect(tester.widget<FilledButton>(restore).onPressed, isNotNull);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      // Nothing is sent until the person confirms.
      expect(api.calls.where((c) => c.startsWith('rollback')), isEmpty);
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();

      expect(api.calls.where((c) => c.startsWith('rollback')), [
        'rollback rev_2',
      ]);
      expect(restored, 1);
    },
  );

  testWidgets(
    'the current revision cannot be restored and the sheet says why',
    (tester) async {
      await _open(tester, _FakeApi());
      await tester.tap(find.byKey(const ValueKey('skill-revision-rev_3')));
      await tester.pumpAndSettle();
      final restore = find.byKey(const ValueKey('skill-history-restore'));
      expect(tester.widget<FilledButton>(restore).onPressed, isNull);
      final reason = _FakeApi().revisions.first.restoreBlockedReason(
        canRollback: true,
        currentId: 'rev_3',
      );
      expect(reason, isNotNull);
      expect(find.text(reason!), findsOneWidget);
    },
  );

  testWidgets('a revision whose content was dropped offers no restore', (
    tester,
  ) async {
    await _open(tester, _FakeApi());
    await tester.tap(find.byKey(const ValueKey('skill-revision-rev_0')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('skill-history-restore')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('a skill outside the managed directory cannot be restored', (
    tester,
  ) async {
    await _open(tester, _FakeApi(), canRollback: false);
    await tester.tap(find.byKey(const ValueKey('skill-revision-rev_2')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('skill-history-restore')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets("the daemon's refusal is shown as it said it", (tester) async {
    await _open(tester, _RefusingApi());
    await tester.tap(find.byKey(const ValueKey('skill-revision-rev_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('skill-history-restore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
    expect(find.text('this revision has no stored content'), findsOneWidget);
  });
}

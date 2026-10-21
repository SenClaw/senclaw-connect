import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_connect/models/plugin_models.dart';
import 'package:senclaw_connect/models/skill_history_models.dart';

Map<String, dynamic> rev(
  String id,
  String origin, {
  bool hasSnapshot = true,
  bool truncated = false,
  String? shadows,
  Map<String, dynamic>? scan,
}) => {
  'id': id,
  'origin': origin,
  'actor': 'api:readme',
  'contentHash': 'aaa'.padRight(64, '0'),
  'generation': 2,
  'fileCount': 2,
  'hasSnapshot': hasSnapshot,
  'truncated': truncated,
  'restoredFrom': null,
  'changeSummary': '1 changed (+1 -1)',
  'shadows': shadows,
  'scan': scan,
  'createdAt': 1760000000000,
};

void main() {
  group('SkillRevision', () {
    test('reads a revision and its scan from the daemon JSON', () {
      final r = SkillRevision.fromJson(
        rev(
          'r',
          'MANUAL',
          scan: {
            'verdict': 'warn',
            'riskScore': 25,
            'findings': [
              {
                'rule': 'INJ001',
                'severity': 'high',
                'title': 'Instruction-override text',
                'file': 'SKILL.md',
                'line': 8,
              },
            ],
          },
        ),
      );
      expect((r.origin, r.generation, r.hasSnapshot), ('MANUAL', 2, true));
      expect(r.scan!.verdict, 'warn');
      expect(r.scan!.findings.single.rule, 'INJ001');
      expect(r.scan!.findings.single.line, 8);
      expect(SkillRevision.fromJson(rev('r', 'MANUAL')).scan, isNull);
    });

    test(
      'a restore is blocked for the current one, a removal, a pruned or '
      'truncated revision and an unmanaged skill, each with its own reason',
      () {
        String? why(Map<String, dynamic> j, {bool managed = true}) =>
            SkillRevision.fromJson(
              j,
            ).restoreBlockedReason(canRollback: managed, currentId: 'cur');
        expect(why(rev('old', 'MANUAL')), isNull);
        final reasons = [
          why(rev('cur', 'MANUAL')),
          why(rev('old', 'REMOVED')),
          why(rev('old', 'MANUAL', truncated: true)),
          why(rev('old', 'MANUAL', hasSnapshot: false)),
          why(rev('old', 'MANUAL'), managed: false),
        ];
        expect(reasons, everyElement(isNotNull));
        // The words are the app language's; what matters is that nothing is
        // reported with another case's reason.
        expect(reasons.toSet().length, reasons.length);
      },
    );
  });

  group('usage', () {
    test('is keyed by content hash and only for the skill asked about', () {
      final u = usageByHash(
        {
          'skills': [
            {
              'source': 'clawhub-managed',
              'key': 'demo',
              'versions': [
                {
                  'contentHash': 'h1',
                  'loads': 3,
                  'fallbackRate': 0.333,
                  'toolFailureRate': null,
                },
                {'contentHash': null, 'loads': 1},
              ],
            },
            {
              'source': 'bundled',
              'key': 'demo',
              'versions': [
                {'contentHash': 'h2', 'loads': 9},
              ],
            },
          ],
        },
        'clawhub-managed',
        'demo',
      );
      expect(u.keys, ['h1']);
      expect(u['h1']!.loads, 3);
      expect(pct(u['h1']!.fallbackRate), '33%');
      expect(pct(u['h1']!.toolFailureRate), '–');
      expect(usageByHash(null, 'x', 'y'), isEmpty);
    });
  });

  group('presentation', () {
    test('every revision kind has a label, a hint and a tone', () {
      for (final o in [
        'MANUAL',
        'IMPORTED',
        'ROLLBACK',
        'REMOVED',
        'DETECTED',
        'BASELINE',
      ]) {
        final s = originStyle(o);
        expect(s.label, isNotEmpty, reason: o);
        expect(s.hint, isNotEmpty, reason: o);
        expect(s.tone, isNotEmpty, reason: o);
      }
    });

    test('diff lines are classified for tinting', () {
      expect(diffLineKind('+++ b/SKILL.md'), DiffLineKind.header);
      expect(diffLineKind('--- a/SKILL.md'), DiffLineKind.header);
      expect(diffLineKind('+new'), DiffLineKind.added);
      expect(diffLineKind('-old'), DiffLineKind.removed);
      expect(diffLineKind('@@ -1 +1 @@'), DiffLineKind.hunk);
      expect(diffLineKind(' same'), DiffLineKind.context);
    });

    test('LocalSkill keeps the sources it replaces', () {
      final s = LocalSkill.fromJson({
        'name': 'web-research',
        'source': 'clawhub-managed',
        'shadows': ['bundled'],
      });
      expect(s.shadows, ['bundled']);
      expect(LocalSkill.fromJson({'name': 'x'}).shadows, isEmpty);
    });
  });
}

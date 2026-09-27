// Minimal smoke test: the app's root widget can be constructed.
//
// A full pumpWidget would require the secure-storage / relay plumbing that
// `SenClawApp` boots, so this just guards that the widget tree compiles and the
// root type is wired up.

import 'package:flutter_test/flutter_test.dart';

import 'package:senclaw_connect/main.dart';

void main() {
  test('SenClawApp can be instantiated', () {
    const app = SenClawApp();
    expect(app, isNotNull);
  });
}

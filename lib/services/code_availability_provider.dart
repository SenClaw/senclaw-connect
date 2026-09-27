import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'code_api.dart';

/// Whether the connected daemon serves the code-session API.
///
/// The daemon dropped `/api/code/sessions` in 83e9720 and re-adds it as a thin
/// layer over chats (plans/260912-0141-code-v2, phase 2). Older daemons answer
/// 404, so the drawer only shows "Code sessions" once the endpoint answers —
/// a tab that opens to an error is worse than no tab. Any failure (404, relay
/// down, auth) fails closed; the screen itself reports real errors once shown.
final codeSessionsAvailableProvider = FutureProvider<bool>((ref) async {
  try {
    await CodeApi().listSessions();
    return true;
  } catch (_) {
    return false;
  }
});

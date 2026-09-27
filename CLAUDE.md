# CLAUDE.md

Guidance for working in this repository.

## Project overview

SenClaw Connect is the Flutter remote client (iOS / Android / macOS) for
[SenClaw](../senclaw). It pairs to a daemon over the encrypted relay hub and
tunnels `/api/*` and chat events through that connection. It does not
supervise a daemon, does not embed the web console, and does not hold daemon
config. `../senclaw`, `../desktop`, and `../web-app` are sibling repos.

**Run tests against no live daemon and no real hub.** `flutter test` covers
parsers and the pairing-QR helper; nothing in this repo should open the user's
hub or write into `~/.senclaw`.

## Transport

- **One seam:** `RelayManager` / `RelayService` (`lib/services/`), exposed by
  `lib/core/relay_providers.dart`. Screens call `*Api` classes
  (`lib/services/*_api.dart`); those go through the relay. Do not add a direct
  HTTP client to `127.0.0.1:18788`.
- **Pairing QR** (`lib/services/connect_qr.dart`): mint `senclaw://connect`
  (what `../desktop` and `../web-app` already emit). Scanning also accepts
  `semaclaw://connect` so a code from before the split still pairs. Do not
  drop the old scheme, and do not mint it.

## Surfaces that are limited on purpose

These are daemon constraints, not missing UI. Do not "fix" them in this app
by claiming a jid or a content-type the relay cannot carry:

- **Dispatch** polls `GET /api/dispatch`. `dispatch:update` is admin-WebSocket
  only. Retry buttons call `POST /api/dispatch/parents/:id/retry` and
  `.../tasks/:id/retry`. A refusal (the daemon's message: "already running",
  "finished successfully") is shown verbatim — a generic "retry failed" makes
  the user tap again.
- **Cowork team chat** is read-only. Sending is owned by
  `app:<channelId>:user:<sender>` only.
- **Patterns / Kits** install from a source, not from a file upload. The relay
  carries JSON.
- **Workbench** artifacts arrive as `workbench:new` events.
  `WorkbenchStore` plus `LocalCache` is the only list; the daemon has no
  backfill endpoint. A fresh install of this app does not see artifacts
  another device already received.

## Watch strip

`WatchStrip` (`lib/widgets/watch_strip.dart`) is the only UI for a chat's
in-flight `schedule_watch`es. It polls `GET /api/watches?chatJid=` every 15s
(a watch is silent by design) and stops one with `POST /api/watches/:id/stop`.
Do not build a second watch UI, and do not treat a missing field as "done".

## Strings

User-facing copy is Vietnamese and English via `tr(vi, en)` in
`lib/services/language_service.dart` (both translations live at the call
site). `t(key)` is the older registry in the same file — pairing and welcome
only. Do not add a third lookup. Ids, URLs, and text the daemon returns
(a retry refusal, an error body) stay as the daemon sent them.

## Testing

`flutter analyze` and `flutter test`. New parse or QR behaviour gets a test
under `test/` that imports `package:senclaw_connect/...` and does not touch a
device, a hub, or a daemon.

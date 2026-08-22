/// Resolving the app-support directory when the platform will not tell us.
///
/// `path_provider` has **no implementation on the Toyota Connected
/// `ivi-homescreen` embedder** — measured 2026-08-23 running our own AOT bundle
/// under it: `MissingPluginException(No implementation found for method
/// getApplicationCacheDirectory on channel plugins.flutter.io/path_provider)`,
/// thrown from `main()` before a single frame. The app did not start.
///
/// The fix is NOT to pretend a directory exists. It is to fall back to the
/// location the platform's own convention already specifies, and to say so.
///
/// **Durability is the invariant, not convenience.** The consent database and
/// the saved-place store both promise that data survives an app restart. A
/// fallback to `Directory.systemTemp` would satisfy the type and silently break
/// that promise — absence resolving to a benign-looking answer, which is the
/// defect class this catalog has spent its life removing. So the fallback is
/// XDG (`$XDG_DATA_HOME`, else `$HOME/.local/share`), which IS durable, and if
/// neither is resolvable the failure is surfaced rather than papered over.
library;

import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException, PlatformException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// How the app-support directory was obtained. Callers that care about
/// provenance (diagnostics, telemetry, an on-screen "storage degraded" chip)
/// can read it; nothing is inferred from the path itself.
enum AppSupportSource {
  /// The platform answered — `path_provider` resolved it.
  platform,

  /// The platform had no implementation; resolved by XDG convention instead.
  /// Still durable across restarts.
  xdgFallback,
}

/// The resolved directory plus how we got it.
class AppSupportDir {
  const AppSupportDir(this.directory, this.source);

  final Directory directory;
  final AppSupportSource source;

  bool get isFallback => source == AppSupportSource.xdgFallback;
}

/// Resolves the app-support directory, tolerating an embedder that ships no
/// `path_provider` implementation.
///
/// Throws [StateError] only when NEITHER the platform NOR the XDG environment
/// can name a directory — a genuinely unreadable state, which is reported, not
/// substituted.
Future<AppSupportDir> resolveAppSupportDir({
  Map<String, String>? environment,
}) async {
  try {
    final dir = await getApplicationSupportDirectory();
    return AppSupportDir(dir, AppSupportSource.platform);
  } on MissingPluginException {
    // The embedder ships no path_provider plugin. Expected on ivi-homescreen.
  } on PlatformException {
    // The plugin exists but could not answer.
  } on Exception {
    // Any other refusal from the platform layer. Deliberately broad: the
    // question this function answers is "did the platform give us a directory",
    // and every no is the same no. Narrowing it would let one unanticipated
    // failure mode kill main() again, which is the defect being closed.
  }

  final env = environment ?? Platform.environment;
  final xdg = env['XDG_DATA_HOME'];
  final home = env['HOME'];

  final String base;
  if (xdg != null && xdg.isNotEmpty) {
    base = xdg;
  } else if (home != null && home.isNotEmpty) {
    base = p.join(home, '.local', 'share');
  } else {
    throw StateError(
      'Cannot resolve an app-support directory: the platform has no '
      'path_provider implementation and neither XDG_DATA_HOME nor HOME is set. '
      'Refusing to substitute a temporary directory — the consent database and '
      'saved-place store promise data survives restart, and a temp path would '
      'break that promise silently.',
    );
  }

  return AppSupportDir(
    Directory(p.join(base, 'sngnav_snow_scene')),
    AppSupportSource.xdgFallback,
  );
}

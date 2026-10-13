import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../logging/app_logger.dart';

/// App name passed to `localNotifier.setup`. WinToast uses it as the
/// AppUserModelID and as the name of the Start menu shortcut it creates
/// (`%APPDATA%\Microsoft\Windows\Start Menu\Programs\<name>.lnk`).
const String kNotificationAppName = 'Pulse Diagnostics';

/// SLGP_UNCPRIORITY: return the target path in its standard form.
const int _kSlgpUncPriority = 0x2;

/// Reads the target path of a `.lnk` file, or null when it cannot be read.
typedef ShortcutTargetReader = String? Function(String shortcutPath);

/// Removes the notification shortcut when it points to another `Pulse.exe`.
///
/// WinToast only checks that the shortcut exists, not where it points. Because
/// the taskbar takes Pulse's icon from the shortcut that carries its
/// AppUserModelID, a stale one (Pulse reinstalled elsewhere, a deleted dev
/// build) showed a blank taskbar icon. Deleting it lets `localNotifier.setup`
/// recreate it for the running executable. Returns true when it was removed.
bool removeStaleNotificationShortcut({
  required AppLogger logger,
  String? appData,
  String? currentExecutable,
  ShortcutTargetReader readTarget = readShortcutTarget,
}) {
  final roaming = appData ?? Platform.environment['APPDATA'];
  if (roaming == null || roaming.isEmpty) return false;
  final shortcut = File(
    '$roaming\\Microsoft\\Windows\\Start Menu\\Programs\\$kNotificationAppName.lnk',
  );
  if (!shortcut.existsSync()) return false;

  final current = currentExecutable ?? Platform.resolvedExecutable;
  final target = readTarget(shortcut.path);
  if (target != null && _samePath(target, current)) return false;

  try {
    shortcut.deleteSync();
    logger.info(
      'Notifications',
      'Removed stale shortcut (target: ${target ?? 'unreadable'}); it is '
          'recreated for $current',
    );
    return true;
  } on FileSystemException catch (e) {
    logger.warn('Notifications', 'Could not remove stale shortcut: $e');
    return false;
  }
}

bool _samePath(String a, String b) =>
    File(a).absolute.path.toLowerCase() == File(b).absolute.path.toLowerCase();

/// Reads a shortcut target with the Shell's IShellLink (COM must already be
/// initialized on this thread; the Flutter runner does so for the UI thread).
String? readShortcutTarget(String shortcutPath) {
  final link = ShellLink.createInstance();
  final persist = IPersistFile.from(link);
  final path = shortcutPath.toNativeUtf16();
  final buffer = calloc<Uint16>(MAX_PATH).cast<Utf16>();
  try {
    if (FAILED(persist.load(path, STGM_READ))) return null;
    if (FAILED(link.getPath(buffer, MAX_PATH, nullptr, _kSlgpUncPriority))) {
      return null;
    }
    final target = buffer.toDartString();
    return target.isEmpty ? null : target;
  } finally {
    free(path);
    calloc.free(buffer);
    persist.release();
    link.release();
  }
}

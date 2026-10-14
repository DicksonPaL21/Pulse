import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pulse_protocol/pulse_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Why an export went to Downloads instead of Documents.
enum ExportFallback {
  /// Written where intended.
  none,

  /// Documents was blocked just now.
  blockedNow,

  /// Documents was blocked earlier; Pulse did not try it again.
  blockedEarlier,
}

/// Where an export ended up.
class ExportResult {
  const ExportResult({required this.path, this.fallback = ExportFallback.none});

  final String path;
  final ExportFallback fallback;

  /// True when the file went to Downloads instead of Documents.
  bool get usedFallback => fallback != ExportFallback.none;

  /// "Saved to `path`", plus why when it went to Downloads.
  String get summary => switch (fallback) {
        ExportFallback.none => 'Saved to $path',
        ExportFallback.blockedNow => 'Saved to $path. Windows blocked writing '
            'to Documents, so Pulse saved it to Downloads and will keep using '
            'Downloads. This usually means Controlled folder access is on: '
            'allow Pulse in Windows Security → Ransomware protection, or '
            'choose an export folder in Settings.',
        ExportFallback.blockedEarlier => 'Saved to $path (Windows Security '
            'blocks Documents for Pulse; choose an export folder in Settings '
            'to change this).',
      };
}

/// An export that could not be written anywhere; [message] is user-facing.
class ExportWriteException implements Exception {
  const ExportWriteException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Remembers that Documents was blocked, per Pulse version: a new version
/// (for example a signed one) tries Documents again once.
abstract class DocumentsBlockedStore {
  Future<bool> isBlocked();
  Future<void> markBlocked();
}

class PrefsDocumentsBlockedStore implements DocumentsBlockedStore {
  const PrefsDocumentsBlockedStore();

  static const _key = 'exports.documents_blocked_version';

  @override
  Future<bool> isBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) == kAppVersion;
  }

  @override
  Future<void> markBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, kAppVersion);
  }
}

/// Writes exports (reports, Timeline, diagnostics, settings).
///
/// Windows Security's Controlled folder access blocks apps it does not trust
/// from writing to Documents and Desktop, and Pulse must not work around it.
/// When the default Documents folder is blocked, the file goes to the same
/// subfolder under Downloads (not a protected folder) and the result says so.
/// Pulse then stops trying Documents, so Windows Security does not show a
/// block notification on every export. A folder the user chose in Settings
/// is never silently replaced.
class ExportWriter {
  ExportWriter({
    Future<Directory> Function()? documentsDirectory,
    Future<Directory?> Function()? downloadsDirectory,
    this.blockedStore = const PrefsDocumentsBlockedStore(),
  })  : _documents = documentsDirectory ?? getApplicationDocumentsDirectory,
        _downloads = downloadsDirectory ?? getDownloadsDirectory;

  final Future<Directory> Function() _documents;
  final Future<Directory?> Function() _downloads;
  final DocumentsBlockedStore blockedStore;

  /// Writes [bytes] as [fileName] under [customDirectory] when set, else
  /// under Documents/[defaultSubfolder] (Downloads/[defaultSubfolder] when
  /// Documents is blocked).
  Future<ExportResult> write({
    required String fileName,
    required List<int> bytes,
    required List<String> defaultSubfolder,
    String customDirectory = '',
  }) async {
    final custom = customDirectory.trim();
    if (custom.isNotEmpty) {
      try {
        return ExportResult(
          path: await _writeInto(Directory(custom), fileName, bytes),
        );
      } on FileSystemException catch (e) {
        throw ExportWriteException(
          'Windows did not let Pulse write to $custom (${_reason(e)}). '
          'If Controlled folder access is on, allow Pulse in Windows '
          'Security → Ransomware protection, or choose another export '
          'folder in Settings.',
        );
      }
    }

    if (await blockedStore.isBlocked()) {
      return _writeToDownloads(
        fileName,
        bytes,
        defaultSubfolder,
        ExportFallback.blockedEarlier,
        onFailure: 'Windows did not let Pulse save the export to Downloads. '
            'Choose an export folder in Settings.',
      );
    }

    final documents = _join(await _documents(), defaultSubfolder);
    try {
      return ExportResult(path: await _writeInto(documents, fileName, bytes));
    } on FileSystemException catch (documentsError) {
      await blockedStore.markBlocked();
      return _writeToDownloads(
        fileName,
        bytes,
        defaultSubfolder,
        ExportFallback.blockedNow,
        onFailure: 'Windows did not let Pulse save the export to Documents or '
            'Downloads (${_reason(documentsError)}). Choose an export folder '
            'in Settings.',
      );
    }
  }

  Future<ExportResult> _writeToDownloads(
    String fileName,
    List<int> bytes,
    List<String> subfolder,
    ExportFallback fallback, {
    required String onFailure,
  }) async {
    final root = await _downloads();
    if (root == null) throw ExportWriteException(onFailure);
    try {
      return ExportResult(
        path: await _writeInto(_join(root, subfolder), fileName, bytes),
        fallback: fallback,
      );
    } on FileSystemException {
      throw ExportWriteException(onFailure);
    }
  }

  static Future<String> _writeInto(
    Directory dir,
    String fileName,
    List<int> bytes,
  ) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final path = '${dir.path}${Platform.pathSeparator}$fileName';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  static Directory _join(Directory root, List<String> parts) => Directory(
        [root.path, ...parts].join(Platform.pathSeparator),
      );

  static String _reason(FileSystemException e) {
    final os = e.osError;
    if (os == null) return e.message;
    return 'Windows error ${os.errorCode}';
  }
}

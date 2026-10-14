import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where an export ended up.
class ExportResult {
  const ExportResult({required this.path, required this.usedFallback});

  final String path;

  /// True when Documents could not be written and the file went to
  /// Downloads instead.
  final bool usedFallback;

  /// "Saved to `path`", plus why when it went to Downloads.
  String get summary =>
      usedFallback ? 'Saved to $path. $fallbackNote' : 'Saved to $path';

  /// User-facing note for [usedFallback]; empty otherwise.
  String get fallbackNote => usedFallback
      ? 'Windows blocked writing to Documents, so Pulse saved it to '
          'Downloads instead. This usually means Controlled folder access '
          'is on: allow Pulse in Windows Security → Ransomware protection, '
          'or choose an export folder in Settings.'
      : '';
}

/// An export that could not be written anywhere; [message] is user-facing.
class ExportWriteException implements Exception {
  const ExportWriteException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Writes exports (reports, Timeline, diagnostics, settings).
///
/// Windows Security's Controlled folder access blocks apps it does not trust
/// from writing to Documents and Desktop, and Pulse must not work around it.
/// When the default Documents folder is blocked, the file goes to the same
/// subfolder under Downloads (not a protected folder) and the result says so.
/// A folder the user chose in Settings is never silently replaced.
class ExportWriter {
  ExportWriter({
    Future<Directory> Function()? documentsDirectory,
    Future<Directory?> Function()? downloadsDirectory,
  })  : _documents = documentsDirectory ?? getApplicationDocumentsDirectory,
        _downloads = downloadsDirectory ?? getDownloadsDirectory;

  final Future<Directory> Function() _documents;
  final Future<Directory?> Function() _downloads;

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
          usedFallback: false,
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

    final documents = _join(await _documents(), defaultSubfolder);
    try {
      return ExportResult(
        path: await _writeInto(documents, fileName, bytes),
        usedFallback: false,
      );
    } on FileSystemException catch (documentsError) {
      final downloadsRoot = await _downloads();
      if (downloadsRoot == null) {
        throw ExportWriteException(_bothBlocked(documentsError));
      }
      try {
        return ExportResult(
          path: await _writeInto(
            _join(downloadsRoot, defaultSubfolder),
            fileName,
            bytes,
          ),
          usedFallback: true,
        );
      } on FileSystemException {
        throw ExportWriteException(_bothBlocked(documentsError));
      }
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

  static String _bothBlocked(FileSystemException e) =>
      'Windows did not let Pulse save the export to Documents or Downloads '
      '(${_reason(e)}). Choose an export folder in Settings.';
}

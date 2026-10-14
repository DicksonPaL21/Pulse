import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/platform/export_writer.dart';

void main() {
  late Directory root;
  late Directory documents;
  late Directory downloads;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pulse-export-test-');
    documents = await Directory('${root.path}/Documents').create();
    downloads = await Directory('${root.path}/Downloads').create();
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  ExportWriter writer({Directory? downloadsDir}) => ExportWriter(
        documentsDirectory: () async => documents,
        downloadsDirectory: () async => downloadsDir,
      );

  /// Simulates Controlled folder access: "Pulse" exists as a file, so the
  /// export folder cannot be created under Documents.
  Future<void> blockDocuments() =>
      File('${documents.path}/Pulse').writeAsString('blocked');

  test('writes under Documents by default', () async {
    final saved = await writer(downloadsDir: downloads).write(
      fileName: 'a.json',
      bytes: utf8.encode('{}'),
      defaultSubfolder: const ['Pulse', 'exports'],
    );
    expect(saved.usedFallback, isFalse);
    expect(saved.path, contains('Documents'));
    expect(await File(saved.path).readAsString(), '{}');
    expect(saved.summary, 'Saved to ${saved.path}');
  });

  test('falls back to Downloads when Documents is blocked', () async {
    await blockDocuments();
    final saved = await writer(downloadsDir: downloads).write(
      fileName: 'a.json',
      bytes: utf8.encode('{}'),
      defaultSubfolder: const ['Pulse', 'exports'],
    );
    expect(saved.usedFallback, isTrue);
    expect(saved.path, startsWith(downloads.path));
    expect(await File(saved.path).exists(), isTrue);
    expect(saved.summary, contains('Controlled folder access'));
  });

  test('a custom folder is never silently replaced', () async {
    final blockedCustom = File('${root.path}/custom');
    await blockedCustom.writeAsString('not a folder');
    expect(
      () => writer(downloadsDir: downloads).write(
        fileName: 'a.json',
        bytes: utf8.encode('{}'),
        defaultSubfolder: const ['Pulse'],
        customDirectory: blockedCustom.path,
      ),
      throwsA(isA<ExportWriteException>()),
    );
  });

  test('explains when neither Documents nor Downloads can be used', () async {
    await blockDocuments();
    await expectLater(
      writer(downloadsDir: null).write(
        fileName: 'a.json',
        bytes: utf8.encode('{}'),
        defaultSubfolder: const ['Pulse', 'exports'],
      ),
      throwsA(
        isA<ExportWriteException>().having(
          (e) => e.message,
          'message',
          contains('Choose an export folder in Settings'),
        ),
      ),
    );
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/logging/app_log_file.dart';
import 'package:pulse/logging/app_logger.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pulse_app_log_test');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('AppLogger appends structured JSON lines to a daily file', () {
    final file = AppLogFile(dir);
    final logger = AppLogger(file: file);

    logger.info('Test', 'first');
    logger.error('Test', 'second "quoted"');
    file.close();

    final files = dir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    expect(
      files.single.uri.pathSegments.last,
      matches(RegExp(r'^pulse-app-\d{4}-\d{2}-\d{2}\.jsonl$')),
    );

    final entries = files.single
        .readAsLinesSync()
        .map((l) => jsonDecode(l) as Map<String, dynamic>)
        .toList();
    expect(entries.map((e) => e['level']), ['info', 'error']);
    expect(entries.last['component'], 'Test');
    expect(entries.last['message'], 'second "quoted"');
    expect(DateTime.tryParse(entries.first['timestamp'] as String), isNotNull);
  });

  test('pruneOldFiles removes only expired daily files', () {
    final now = DateTime.utc(2026, 10, 13);
    File('${dir.path}/pulse-app-2026-09-01.jsonl').writeAsStringSync('{}\n');
    File('${dir.path}/pulse-app-2026-10-12.jsonl').writeAsStringSync('{}\n');
    File('${dir.path}/notes.txt').writeAsStringSync('keep');

    AppLogFile(dir).pruneOldFiles(now: now);

    final names = dir
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .toList()
      ..sort();
    expect(names, ['notes.txt', 'pulse-app-2026-10-12.jsonl']);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/app/theme/pulse_theme.dart';
import 'package:pulse/features/crashes/crash_display.dart';
import 'package:pulse/features/crashes/crash_history_summary.dart';
import 'package:pulse/features/crashes/widgets/crash_group_panel.dart';
import 'package:pulse/features/crashes/widgets/crash_group_tile.dart';
import 'package:pulse/features/crashes/widgets/crash_overview_header.dart';
import 'package:pulse/features/timeline/hidden_event_types.dart';
import 'package:pulse_protocol/pulse_wire.dart';

Widget _wrap(Widget child, {double width = 1200}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: PulseTheme.dark(),
    builder: (context, app) {
      final pulse = Theme.of(context).extension<PulseThemeData>();
      if (pulse != null) PulseThemeScope.current = pulse;
      return app ?? const SizedBox.shrink();
    },
    home: Scaffold(
      body: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

int _daysAgo(DateTime now, int days, {int hour = 12}) =>
    DateTime(now.year, now.month, now.day - days, hour).millisecondsSinceEpoch;

CrashGroup _appCrash(DateTime now) => CrashGroup(
      kind: CrashKind.appCrash,
      key: 'app|game.exe|nvwgf2umx.dll|0xC0000005',
      subject: 'Game.exe',
      moduleName: 'nvwgf2umx.dll',
      modulePath:
          r'C:\Windows\System32\DriverStore\FileRepository\nv.inf\nvwgf2umx.dll',
      moduleCompany: 'NVIDIA Corporation',
      moduleOrigin: FaultingModuleOrigin.driver,
      code: 0xC0000005,
      hasCode: true,
      title: 'Game Crashed',
      summary: 'Game closed unexpectedly after a memory access error. The '
          'error happened in nvwgf2umx.dll, part of a device driver from '
          'NVIDIA Corporation.',
      recommendation: "Update or reinstall the driver from the device maker's "
          'website.',
      count: 5,
      firstUnixMs: _daysAgo(now, 20),
      lastUnixMs: _daysAgo(now, 1),
      occurrenceUnixMs: [
        _daysAgo(now, 1),
        _daysAgo(now, 1, hour: 9),
        _daysAgo(now, 2),
        _daysAgo(now, 10),
        _daysAgo(now, 20),
      ],
      versions: [
        CrashVersion(version: '2.1', count: 4, lastUnixMs: _daysAgo(now, 1)),
        CrashVersion(version: '2.0', count: 1, lastUnixMs: _daysAgo(now, 20)),
      ],
      recent: [
        CrashOccurrence(
          timestampUnixMs: _daysAgo(now, 1),
          channel: 'Application',
          recordId: 42,
          version: '2.1',
        ),
      ],
    );

CrashGroup _blueScreen(DateTime now) => CrashGroup(
      kind: CrashKind.blueScreen,
      key: 'bsod|0x00000133',
      subject: 'DPC_WATCHDOG_VIOLATION',
      code: 0x133,
      hasCode: true,
      title: 'Windows Crashed With a Blue Screen',
      summary: 'Stop code: DPC_WATCHDOG_VIOLATION (0x00000133).',
      count: 2,
      firstUnixMs: _daysAgo(now, 3),
      lastUnixMs: _daysAgo(now, 0, hour: 1),
      // The second one is older than the period and must not be drawn.
      occurrenceUnixMs: [_daysAgo(now, 0, hour: 1), _daysAgo(now, 40)],
    );

CrashGroup _hang(DateTime now) => CrashGroup(
      kind: CrashKind.appHang,
      key: 'hang|tool.exe',
      subject: 'Tool.exe',
      title: 'Tool Stopped Responding',
      summary: 'Tool stopped responding and was closed.',
      count: 1,
      firstUnixMs: _daysAgo(now, 1),
      lastUnixMs: _daysAgo(now, 1),
      occurrenceUnixMs: [_daysAgo(now, 1)],
    );

void main() {
  final now = DateTime.now();

  group('CrashHistorySummary', () {
    test('no crashes', () {
      final summary =
          CrashHistorySummary.from(CrashHistory(days: 30), now: now);
      expect(summary.total, 0);
      expect(summary.headline, 'No crashes in the last 30 days.');
      expect(summary.buckets, hasLength(30));
      expect(summary.buckets.last.day, DateTime(now.year, now.month, now.day));
      expect(summary.peakBucketCount, 0);
      expect(summary.lastCrashUnixMs, 0);
    });

    test('counts, headline and daily buckets', () {
      final history = CrashHistory(
        days: 30,
        groups: [_blueScreen(now), _appCrash(now), _hang(now)],
      );
      final summary = CrashHistorySummary.from(history, now: now);
      expect(summary.total, 8);
      expect(summary.counts[CrashCategory.blueScreens], 2);
      expect(summary.counts[CrashCategory.appCrashes], 5);
      expect(summary.counts[CrashCategory.notResponding], 1);
      expect(summary.counts[CrashCategory.restarts], 0);
      expect(summary.headline, '8 crashes in the last 30 days.');
      expect(summary.detail, contains('blue screen 2 times'));
      expect(summary.detail, contains('Most often: Game Crashed, 5 times.'));

      final today = summary.buckets.last;
      expect(today.count, 1);
      expect(today.worst, CrashKind.blueScreen);
      final yesterday = summary.buckets[summary.buckets.length - 2];
      expect(yesterday.count, 3); // Two app crashes and a hang.
      expect(yesterday.worst, CrashKind.appCrash);
      // 40 days ago is outside the period.
      expect(
        summary.buckets.fold<int>(0, (sum, b) => sum + b.count),
        7,
      );
      expect(summary.peakBucketCount, 3);
    });

    test('category filter', () {
      final history = CrashHistory(
        days: 7,
        groups: [_blueScreen(now), _appCrash(now), _hang(now)],
      );
      expect(crashGroupsIn(history, null), hasLength(3));
      expect(
        crashGroupsIn(history, CrashCategory.notResponding).single.key,
        'hang|tool.exe',
      );
      expect(crashGroupsIn(history, CrashCategory.restarts), isEmpty);
      expect(CrashCategory.of(CrashKind.gpuReset), CrashCategory.other);
    });
  });

  test('display helpers', () {
    expect(formatCrashCode(0xC0000005), '0xC0000005');
    expect(formatCrashCode(0x9F), '0x0000009F');
    expect(crashTimesLabel(1), '1 time');
    expect(crashTimesLabel(3), '3 times');
    expect(
      faultingModuleOriginLabel(FaultingModuleOrigin.driver),
      'Part of a device driver',
    );
    expect(faultingModuleOriginLabel(FaultingModuleOrigin.unknown), isEmpty);
  });

  test('hidden app crashes are named for the whole type', () {
    final crash = TimelineEvent(
      providerName: 'Application Error',
      winEventId: 1000,
      title: 'Discord Crashed',
    );
    expect(hiddenEventTypeTitleOf(crash, crash.title), 'App crashes');
    final other = TimelineEvent(providerName: 'TPM-WMI', winEventId: 1801);
    expect(hiddenEventTypeTitleOf(other, 'Secure Boot'), 'Secure Boot');
  });

  group('widgets', () {
    // The window is at least 1200 px wide; 900 leaves room for the rail.
    testWidgets('overview header fits the narrowest page and filters',
        (tester) async {
      CrashCategory? picked;
      final summary = CrashHistorySummary.from(
        CrashHistory(days: 90, groups: [_blueScreen(now), _appCrash(now)]),
        now: now,
      );
      await tester.pumpWidget(_wrap(
        CrashOverviewHeader(
          summary: summary,
          selectedDays: 90,
          selectedCategory: null,
          onCategory: (category) => picked = category,
          onDays: (_) {},
        ),
        width: 900,
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('7 crashes in the last 90 days.'), findsOneWidget);
      await tester.tap(find.text('Blue screens'));
      expect(picked, CrashCategory.blueScreens);
    });

    testWidgets('group tile and panel explain an app crash', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final group = _appCrash(now);
      CrashOccurrence? opened;
      await tester.pumpWidget(_wrap(
        SizedBox(
          height: 1500,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CrashGroupTile(
                  group: group,
                  selected: true,
                  onTap: () {},
                ),
              ),
              SizedBox(
                width: 452,
                child: CrashGroupPanel(
                  group: group,
                  onClose: () {},
                  onOpenOccurrence: (o) => opened = o,
                ),
              ),
            ],
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Game Crashed'), findsNWidgets(2));
      expect(
        find.text('Part of a device driver · NVIDIA Corporation'),
        findsOneWidget,
      );
      expect(find.text('0xC0000005'), findsOneWidget);
      expect(find.text('Newest 1 of 5'.toUpperCase()), findsOneWidget);
      await tester.ensureVisible(find.text('2.1').last);
      await tester.tap(find.text('2.1').last);
      expect(opened?.recordId, 42);
    });
  });
}

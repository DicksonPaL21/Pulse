import 'package:pulse_protocol/pulse_wire.dart';

import 'crash_display.dart';

/// The five counters of the Crashes page; each also filters the list.
enum CrashCategory {
  blueScreens('Blue screens'),
  appCrashes('App crashes'),
  notResponding('Not responding'),
  restarts('Unexpected restarts'),
  other('Other');

  const CrashCategory(this.label);

  final String label;

  static CrashCategory of(CrashKind kind) {
    return switch (kind) {
      CrashKind.blueScreen => CrashCategory.blueScreens,
      CrashKind.appCrash => CrashCategory.appCrashes,
      CrashKind.appHang => CrashCategory.notResponding,
      CrashKind.unexpectedRestart => CrashCategory.restarts,
      CrashKind.gpuReset ||
      CrashKind.serviceCrash ||
      CrashKind.hardwareError ||
      CrashKind.unspecified =>
        CrashCategory.other,
    };
  }
}

/// Crashes on one local calendar day.
class CrashDayBucket {
  const CrashDayBucket({
    required this.day,
    required this.count,
    required this.worst,
  });

  /// Local midnight.
  final DateTime day;
  final int count;

  /// The most serious kind that day; null without crashes.
  final CrashKind? worst;
}

/// Plain-language overview of a [CrashHistory] for the Crashes page hero.
class CrashHistorySummary {
  const CrashHistorySummary._({
    required this.days,
    required this.total,
    required this.counts,
    required this.buckets,
    required this.headline,
    required this.detail,
    required this.lastCrashUnixMs,
  });

  factory CrashHistorySummary.from(
    CrashHistory history, {
    required DateTime now,
  }) {
    final days = history.days > 0 ? history.days : _fallbackDays;
    final counts = {for (final c in CrashCategory.values) c: 0};
    var total = 0;
    var lastCrash = 0;
    CrashGroup? mostFrequent;
    for (final group in history.groups) {
      counts[CrashCategory.of(group.kind)] =
          counts[CrashCategory.of(group.kind)]! + group.count;
      total += group.count;
      if (group.lastUnixMs > lastCrash) lastCrash = group.lastUnixMs;
      // Groups arrive newest first, so ties go to the more recent one.
      if (mostFrequent == null || group.count > mostFrequent.count) {
        mostFrequent = group;
      }
    }

    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(today.year, today.month, today.day - (days - 1));
    final bucketCounts = List<int>.filled(days, 0);
    final bucketWorst = List<CrashKind?>.filled(days, null);
    for (final group in history.groups) {
      for (final unixMs in group.occurrenceUnixMs) {
        final local = DateTime.fromMillisecondsSinceEpoch(unixMs);
        final day = DateTime(local.year, local.month, local.day);
        // Whole days between local midnights; rounding absorbs DST hours.
        final index = (day.difference(first).inHours / 24).round();
        if (index < 0 || index >= days) continue;
        bucketCounts[index]++;
        final worst = bucketWorst[index];
        if (worst == null || _rank(group.kind) > _rank(worst)) {
          bucketWorst[index] = group.kind;
        }
      }
    }
    final buckets = [
      for (var i = 0; i < days; i++)
        CrashDayBucket(
          day: DateTime(first.year, first.month, first.day + i),
          count: bucketCounts[i],
          worst: bucketWorst[i],
        ),
    ];

    final blueScreens = counts[CrashCategory.blueScreens]!;
    final String headline;
    final String detail;
    if (total == 0) {
      headline = 'No crashes in the last $days days.';
      detail = 'Windows recorded no blue screens, app crashes or unexpected '
          'restarts.';
    } else {
      headline = '$total ${total == 1 ? 'crash' : 'crashes'} '
          'in the last $days days.';
      final top = mostFrequent!;
      final most = top.count > 1
          ? 'Most often: ${top.title}, ${crashTimesLabel(top.count)}.'
          : '';
      detail = [
        if (blueScreens > 0)
          'Windows stopped with a blue screen ${crashTimesLabel(blueScreens)}.',
        if (most.isNotEmpty) most,
        if (blueScreens == 0 && most.isEmpty)
          'Each one is listed below with what it means.',
      ].join(' ');
    }

    return CrashHistorySummary._(
      days: days,
      total: total,
      counts: counts,
      buckets: buckets,
      headline: headline,
      detail: detail,
      lastCrashUnixMs: lastCrash,
    );
  }

  /// Used when the reply does not say its period (older services).
  static const int _fallbackDays = 30;

  final int days;
  final int total;
  final Map<CrashCategory, int> counts;

  /// One per day, oldest first, ending today.
  final List<CrashDayBucket> buckets;
  final String headline;
  final String detail;

  /// 0 without crashes.
  final int lastCrashUnixMs;

  int get peakBucketCount =>
      buckets.fold(0, (peak, b) => b.count > peak ? b.count : peak);

  /// How serious a kind is, for colouring a day by its worst crash.
  static int _rank(CrashKind kind) {
    return switch (kind) {
      CrashKind.blueScreen || CrashKind.hardwareError => 4,
      CrashKind.unexpectedRestart => 3,
      CrashKind.appCrash || CrashKind.serviceCrash => 2,
      CrashKind.gpuReset || CrashKind.appHang => 1,
      CrashKind.unspecified => 0,
    };
  }
}

/// Groups of [history] in [category]; all groups when [category] is null.
List<CrashGroup> crashGroupsIn(CrashHistory history, CrashCategory? category) {
  if (category == null) return history.groups;
  return [
    for (final group in history.groups)
      if (CrashCategory.of(group.kind) == category) group,
  ];
}

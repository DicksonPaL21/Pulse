import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/timeline/timeline_display.dart';
import 'package:pulse_protocol/pulse_wire.dart';

TimelineEvent _event(String id, int unixMs) =>
    TimelineEvent(eventId: id, timestampUnixMs: unixMs);

void main() {
  test('latest is the newest event, not the first row (pinned sort first)', () {
    // Pinned 20:34 event listed above the newer 23:15 event.
    final rows = [
      _event('pinned-old', 1000),
      _event('newest', 5000),
      _event('older', 3000),
    ];
    expect(latestEventIdOf(rows), 'newest');
  });

  test('events without an id are ignored; empty input has no latest', () {
    expect(latestEventIdOf([_event('', 9000), _event('a', 1)]), 'a');
    expect(latestEventIdOf(const []), isNull);
  });
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../ipc/pulse_ipc_client.dart';
import '../logging/app_logger.dart';
import '../presentation/utils/pulse_user_errors.dart';

/// Loads the crash history (doc 43) for the Crashes page. Nothing is read
/// until the page is shown; a shown page reloads data older than
/// [staleAfter].
class CrashHistoryController extends ChangeNotifier {
  CrashHistoryController({required this.ipc, required this.logger}) {
    ipc.addListener(_onIpcChanged);
  }

  /// The periods the page offers, in days; the service caps at 90.
  static const List<int> periods = [7, 30, 90];
  static const int defaultDays = 30;
  static const Duration staleAfter = Duration(minutes: 2);

  final PulseIpcClient ipc;
  final AppLogger logger;

  CrashHistory? _history;
  bool _loading = false;
  String? _error;
  int _days = defaultDays;
  DateTime? _loadedAt;
  bool _pageVisible = false;
  int _requestSerial = 0;
  IpcConnectionState _lastState = IpcConnectionState.disconnected;

  CrashHistory? get history => _history;
  bool get loading => _loading;
  String? get error => _error;
  int get days => _days;
  DateTime? get loadedAt => _loadedAt;

  /// Called by the shell when the Crashes page shows or hides.
  void setPageVisible(bool visible) {
    _pageVisible = visible;
    if (visible) unawaited(refreshIfStale());
  }

  Future<void> setDays(int days) async {
    if (days == _days && _history != null) return;
    _days = days;
    notifyListeners();
    await load();
  }

  Future<void> refreshIfStale() async {
    if (_loading) return;
    final loadedAt = _loadedAt;
    final stale = loadedAt == null ||
        DateTime.now().difference(loadedAt) > staleAfter ||
        _history?.days != _days;
    if (stale) await load();
  }

  Future<void> load() async {
    if (ipc.status.state != IpcConnectionState.connected) return;
    final serial = ++_requestSerial;
    final days = _days;
    _loading = true;
    _error = null;
    notifyListeners();
    final watch = Stopwatch()..start();
    try {
      final history = await ipc.getCrashHistory(days: days);
      if (serial != _requestSerial) return; // A newer request replaced it.
      _history = history;
      _loadedAt = DateTime.now();
      logger.info(
        'CrashHistory',
        'Loaded days=$days groups=${history.groups.length} '
            'scanned=${history.scannedEvents} truncated=${history.truncated} '
            'ms=${watch.elapsedMilliseconds}',
      );
    } on CrashHistoryUnavailable catch (e) {
      if (serial != _requestSerial) return;
      _error = e.serviceTooOld
          ? 'PulseService is older than this version of Pulse and cannot '
              'read crash history yet. Update or reinstall Pulse so both '
              'match.'
          : PulseUserErrors.fromMessage(e.toString());
      logger.warn('CrashHistory', 'Load failed: $e');
    } catch (e) {
      if (serial != _requestSerial) return;
      _error = PulseUserErrors.fromObject(e);
      logger.warn('CrashHistory', 'Load failed: $e');
    } finally {
      if (serial == _requestSerial) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Loads as soon as the service connects while the page is shown.
  void _onIpcChanged() {
    final state = ipc.status.state;
    if (state == _lastState) return;
    _lastState = state;
    if (state == IpcConnectionState.connected && _pageVisible) {
      unawaited(refreshIfStale());
    }
  }

  @override
  void dispose() {
    ipc.removeListener(_onIpcChanged);
    super.dispose();
  }
}

// Renders the README and website screenshots from the real Pulse UI with the
// sample data in sample_data.dart, so no real PC data ever appears in them.
//
// Run from apps/pulse_app:
//   flutter test test/screenshots/readme_screenshots.dart
//
// Writes docs/readme/<name>.png and, when the website checkout sits next to
// this repository (../pulse-web), public/screens/<name>.png; set
// PULSE_WEB_SCREENS to that folder when the repository is reached through
// another path (for example a subst drive). Not part of the regular test run:
// `flutter test` only picks up files ending in _test.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pulse/app/pulse_app.dart';
import 'package:pulse/application/assistant_controller.dart';
import 'package:pulse/application/background_mode_controller.dart';
import 'package:pulse/application/client_frame_metrics.dart';
import 'package:pulse/application/connection_controller.dart';
import 'package:pulse/application/crash_history_controller.dart';
import 'package:pulse/application/diagnostics_controller.dart';
import 'package:pulse/application/evtx_import_controller.dart';
import 'package:pulse/application/health_navigation.dart';
import 'package:pulse/application/service_lifecycle_controller.dart';
import 'package:pulse/application/settings_controller.dart';
import 'package:pulse/application/shell_navigation.dart';
import 'package:pulse/application/timeline_library_controller.dart';
import 'package:pulse/application/timeline_session_controller.dart';
import 'package:pulse/application/update_check_controller.dart';
import 'package:pulse/assistant/local_ai_chat.dart';
import 'package:pulse/assistant/local_ai_provider.dart';
import 'package:pulse/assistant/local_ai_types.dart';
import 'package:pulse/ipc/pulse_ipc_client.dart';
import 'package:pulse/logging/app_logger.dart';
import 'package:pulse/platform/pulse_service_scm.dart';
import 'package:pulse/presentation/components/pulse_nav_rail.dart';
import 'package:pulse_protocol/pulse_constants.dart';
import 'package:pulse_protocol/pulse_wire.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sample_data.dart';

/// Window size of the screenshots (logical pixels) and output scale.
const _windowSize = Size(1440, 900);
const _pixelRatio = 1.0;

/// Health history the charts show (one sample per second).
const _healthSeconds = 60;

/// Output file per screen: README name, website name (null = not used).
const _outputs = <String, (String?, String?)>{
  'timeline': ('timeline', 'timeline'),
  'crashes': ('crashes', 'crashes'),
  'health': ('system-health', 'health'),
  'inventory': ('inventory', 'inventory'),
  'reports': ('reports', 'reports'),
  'diagnostics': ('diagnostics', null),
  'assistant': ('assistant', 'assistant'),
};

const _readmeDir = '../../docs/readme';
final _websiteDir = Platform.environment['PULSE_WEB_SCREENS'] ??
    '../../../pulse-web/public/screens';

final _shotKey = GlobalKey();

/// IPC client that answers from sample data instead of PulseService.
class _SampleIpc extends PulseIpcClient {
  _SampleIpc(this.now);

  final DateTime now;
  final _health = StreamController<HealthUpdate>.broadcast();
  final _live = StreamController<TimelineEvent>.broadcast();

  @override
  Stream<HealthUpdate> get healthUpdates => _health.stream;

  @override
  Stream<TimelineEvent> get liveEvents => _live.stream;

  void emitHealth(HealthSample sample) => _health.add(HealthUpdate(sample: sample));

  @override
  Future<void> start() async {}

  @override
  Future<Pong> ping() async => Pong(
        nonce: 1,
        unixMs: DateTime.now().millisecondsSinceEpoch,
        serviceVersion: kAppVersion,
      );

  @override
  Future<TimelineSnapshot> getTimelineSnapshot({
    int limit = 100,
    String channel = 'System',
  }) async =>
      TimelineSnapshot(
        events: sampleTimelineEvents(now),
        channel: channel,
        requestedLimit: limit,
        collectedUnixMs: now.millisecondsSinceEpoch,
      );

  @override
  Future<TimelineEventDetail> getTimelineEventDetail({
    required String channel,
    required int recordId,
  }) async {
    final match = sampleTimelineEvents(now).where(
      (e) => e.channel == channel && e.recordId == recordId,
    );
    return TimelineEventDetail(
      found: match.isNotEmpty,
      event: match.isEmpty ? null : match.first,
    );
  }

  @override
  Future<InventoryDomainSnapshot> getInventoryDomain({
    required InventoryDomainId domain,
    bool forceRefresh = false,
    int sinceGeneration = 0,
    int limit = 0,
  }) async =>
      sampleInventory(now, domain);

  @override
  Future<CrashHistory> getCrashHistory({int days = 30}) async =>
      sampleCrashHistory(now, days);

  @override
  Future<void> startLiveMonitoring({String channel = 'System'}) async {}

  @override
  Future<void> stopLiveMonitoring() async {}

  @override
  Future<HealthSnapshot> getHealthSnapshot() async => HealthSnapshot(
        info: sampleHealthInfo(),
        sample: sampleHealthSample(now, 0, total: _healthSeconds),
      );

  @override
  Future<void> startHealthMonitoring() async {}

  @override
  Future<void> stopHealthMonitoring() async {}

  @override
  Future<DiagnosticsSnapshot> getDiagnosticsSnapshot() async =>
      sampleDiagnostics(now, kAppVersion);

  Future<void> close() async {
    await _health.close();
    await _live.close();
  }
}

/// A local model that asks for the crash history, then answers from it. The
/// tool call runs for real against the sample IPC; only the model is scripted.
class _SampleLocalAi implements LocalAiProvider {
  int _turn = 0;

  @override
  String get id => 'ollama';

  @override
  String get displayName => 'Ollama';

  @override
  bool get isLocal => true;

  @override
  Uri get baseUri => Uri.parse('http://127.0.0.1:11434');

  @override
  Future<LocalAiProviderStatus> probe() async => LocalAiProviderStatus.ready(
        models: const [LocalAiModel(id: 'qwen3:8b', displayName: 'qwen3:8b')],
      );

  @override
  Future<LocalAiChatTurn> chat(LocalAiChatRequest request) async {
    if (_turn++ == 0) {
      return const LocalAiChatTurn(
        toolCalls: [
          LocalAiToolCall(id: 'call_1', name: 'crash_history', arguments: {'days': 30}),
        ],
      );
    }
    return const LocalAiChatTurn(content: sampleAssistantAnswer);
  }
}

class _RunningScm implements PulseServiceScm {
  @override
  PulseServiceScmSnapshot query() =>
      const PulseServiceScmSnapshot(state: PulseServiceScmState.running);
}

/// Loads every font in the app's FontManifest (Geist, Geist Mono, Lucide,
/// Material Icons) so text and icons render as in the app, not as boxes.
Future<void> _loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
      as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// Window and backdrop plugins have no host in tests; answer them quietly.
void _mockPlatformChannels() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final channel in const ['window_manager', 'flutter_acrylic']) {
    messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
      return switch (call.method) {
        'isMaximized' || 'isFullScreen' || 'isMinimized' => false,
        'isFocused' || 'isVisible' => true,
        _ => null,
      };
    });
  }
}

Future<Widget> _app(_SampleIpc ipc) async {
  SharedPreferences.setMockInitialValues({});
  final logger = AppLogger();
  final settings = SettingsController(logger: logger);
  await settings.load();
  await settings.completeWelcome();
  await settings.setAssistantLocalAiSelection(providerId: 'ollama', modelId: 'qwen3:8b');
  final timelineLibrary = TimelineLibraryController(logger: logger);
  await timelineLibrary.load();
  final timeline = TimelineSessionController(ipc: ipc, settings: settings, logger: logger);
  final frameMetrics = ClientFrameMetrics();
  final shellNavigation = ShellNavigation();
  final lifecycle = ServiceLifecycleController(logger: logger, scm: _RunningScm())
    ..refresh();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PulseIpcClient>.value(value: ipc),
      Provider.value(value: logger),
      ChangeNotifierProvider(create: (_) => ConnectionController(ipc: ipc, logger: logger)),
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: timeline),
      ChangeNotifierProvider.value(value: timelineLibrary),
      ChangeNotifierProvider(create: (_) => EvtxImportController(logger: logger)),
      ChangeNotifierProvider(
        create: (_) => UpdateCheckController(settings: settings, logger: logger),
      ),
      ChangeNotifierProvider(
        create: (_) => DiagnosticsController(
          ipc: ipc,
          timeline: timeline,
          settings: settings,
          logger: logger,
          frameMetrics: frameMetrics,
        ),
      ),
      ChangeNotifierProvider.value(value: lifecycle),
      ChangeNotifierProvider.value(value: frameMetrics),
      ChangeNotifierProvider(create: (_) => HealthNavigation()),
      ChangeNotifierProvider.value(value: shellNavigation),
      ChangeNotifierProvider(
        create: (_) => BackgroundModeController(
          settings: settings,
          ipc: ipc,
          shellNavigation: shellNavigation,
          timelineLibrary: timelineLibrary,
          logger: logger,
        ),
      ),
      ChangeNotifierProvider(
        create: (_) => AssistantController(
          settings: settings,
          ipc: ipc,
          registry: LocalAiProviderRegistry(
            providers: [_SampleLocalAi()],
            preferredProviderId: 'ollama',
            preferredModelId: 'qwen3:8b',
          ),
        ),
      ),
      ChangeNotifierProvider(create: (_) => CrashHistoryController(ipc: ipc, logger: logger)),
    ],
    child: RepaintBoundary(key: _shotKey, child: const PulseApp()),
  );
}

/// Lets futures, streams and animations finish (no pumpAndSettle: some
/// widgets animate forever).
Future<void> _settle(WidgetTester tester, {int seconds = 2}) async {
  for (var i = 0; i < seconds * 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openPage(WidgetTester tester, String railLabel) async {
  final item = find.descendant(
    of: find.byType(PulseNavRail),
    matching: find.text(railLabel),
  );
  await tester.tap(item.first);
  await _settle(tester);
}

Future<void> _capture(WidgetTester tester, String screen) async {
  final (readmeName, websiteName) = _outputs[screen]!;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    if (readmeName != null) {
      File('$_readmeDir/$readmeName.png').writeAsBytesSync(bytes);
    }
    if (websiteName != null && Directory(_websiteDir).existsSync()) {
      File('$_websiteDir/$websiteName.png').writeAsBytesSync(bytes);
    }
  });
}

void main() {
  testWidgets('README and website screenshots', (tester) async {
    // A debug-only Material check (ListTile ink inside a coloured box) is
    // not an error in the screenshots; anything else still fails the run.
    final reportError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('ListTile background color')) return;
      reportError?.call(details);
    };
    addTearDown(() => FlutterError.onError = reportError);
    tester.view.physicalSize = _windowSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(_loadFonts);
    _mockPlatformChannels();

    final now = DateTime.now();
    final ipc = _SampleIpc(now)
      ..debugSetStatusForTest(const IpcStatus(state: IpcConnectionState.connecting));
    await tester.pumpWidget(await tester.runAsync(() => _app(ipc)) as Widget);
    await tester.pump();
    // The connecting → connected edge loads every page, as in the app.
    ipc.debugSetStatusForTest(
      const IpcStatus(state: IpcConnectionState.connected, serviceVersion: kAppVersion),
    );
    await _settle(tester, seconds: 3);
    await _capture(tester, 'timeline');

    await _openPage(tester, 'Crashes');
    await tester.tap(find.text('Discord Crashed').first);
    await _settle(tester);
    await _capture(tester, 'crashes');

    await _openPage(tester, 'Health');
    for (var i = 0; i < _healthSeconds; i++) {
      ipc.emitHealth(sampleHealthSample(now, i, total: _healthSeconds));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _settle(tester);
    await _capture(tester, 'health');

    await _openPage(tester, 'Inventory');
    await tester.tap(find.text('PulseService · running · automatic').first);
    await _settle(tester);
    await _capture(tester, 'inventory');

    await _openPage(tester, 'Reports');
    await tester.tap(find.text('Crash history').first);
    await _settle(tester);
    await _capture(tester, 'reports');

    await _openPage(tester, 'Diagnose');
    await _capture(tester, 'diagnostics');

    await _openPage(tester, 'Assistant');
    final assistant = Provider.of<AssistantController>(
      tester.element(find.byType(PulseNavRail)),
      listen: false,
    );
    await _settle(tester);
    await tester.runAsync(assistant.refreshConnection);
    await _settle(tester);
    if (assistant.selectedProvider == null) {
      await tester.runAsync(() => assistant.selectProvider('ollama'));
      await _settle(tester);
    }
    assistant.setDraft(sampleAssistantQuestion);
    await tester.runAsync(assistant.sendDraft);
    await _settle(tester, seconds: 3);
    await _capture(tester, 'assistant');

    // Tear the app down so its timers stop before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester, seconds: 1);
    await tester.runAsync(ipc.close);
  });
}

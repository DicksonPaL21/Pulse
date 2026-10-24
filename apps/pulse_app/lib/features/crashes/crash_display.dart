import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../app/theme/pulse_theme.dart';
import '../../presentation/components/pulse_badge.dart';
import '../../presentation/utils/pulse_formatters.dart';
import '../timeline/timeline_display.dart';

/// How a crash kind looks in the Crashes page.
class CrashKindVisual {
  const CrashKindVisual({
    required this.label,
    required this.icon,
    required this.color,
    required this.tone,
  });

  /// Singular label, e.g. "Blue screen".
  final String label;
  final IconData icon;
  final Color color;
  final PulseBadgeTone tone;

  static CrashKindVisual of(CrashKind kind) {
    return switch (kind) {
      CrashKind.blueScreen => CrashKindVisual(
          label: 'Blue screen',
          icon: LucideIcons.monitorX,
          color: PulseTokens.severityCritical,
          tone: PulseBadgeTone.error,
        ),
      CrashKind.appCrash => CrashKindVisual(
          label: 'App crash',
          icon: LucideIcons.appWindow,
          color: PulseTokens.severityError,
          tone: PulseBadgeTone.error,
        ),
      CrashKind.appHang => CrashKindVisual(
          label: 'Not responding',
          icon: LucideIcons.hourglass,
          color: PulseTokens.severityWarning,
          tone: PulseBadgeTone.warning,
        ),
      CrashKind.unexpectedRestart => CrashKindVisual(
          label: 'Unexpected restart',
          icon: LucideIcons.power,
          color: PulseTokens.severityError,
          tone: PulseBadgeTone.error,
        ),
      CrashKind.gpuReset => CrashKindVisual(
          label: 'Graphics driver reset',
          icon: LucideIcons.gpu,
          color: PulseTokens.severityWarning,
          tone: PulseBadgeTone.warning,
        ),
      CrashKind.serviceCrash => CrashKindVisual(
          label: 'Service crash',
          icon: LucideIcons.cog,
          color: PulseTokens.severityWarning,
          tone: PulseBadgeTone.warning,
        ),
      CrashKind.hardwareError => CrashKindVisual(
          label: 'Hardware error',
          icon: LucideIcons.cpu,
          color: PulseTokens.severityCritical,
          tone: PulseBadgeTone.error,
        ),
      CrashKind.unspecified => CrashKindVisual(
          label: 'Crash',
          icon: LucideIcons.octagonAlert,
          color: PulseTokens.severityError,
          tone: PulseBadgeTone.error,
        ),
    };
  }
}

/// "0xC0000005" — the eight-digit form Windows shows codes in.
String formatCrashCode(int code) =>
    '0x${code.toUnsigned(32).toRadixString(16).toUpperCase().padLeft(8, '0')}';

/// Plain-language owner of the file an app crashed in; empty when unknown.
String faultingModuleOriginLabel(FaultingModuleOrigin origin) {
  return switch (origin) {
    FaultingModuleOrigin.app => "The app's own file",
    FaultingModuleOrigin.windows => 'Part of Windows',
    FaultingModuleOrigin.driver => 'Part of a device driver',
    FaultingModuleOrigin.other => 'Another program loaded into the app',
    FaultingModuleOrigin.unknown => '',
  };
}

/// "1 time" / "12 times".
String crashTimesLabel(int count) => count == 1 ? '1 time' : '$count times';

/// Local date and clock time, e.g. "2026-10-24 19:32".
String formatCrashTime(int unixMs) {
  final local = DateTime.fromMillisecondsSinceEpoch(unixMs);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${PulseFormatters.clockTime(local)}';
}

/// "2d ago" within a week, the date after that ("2026-10-04").
String formatCrashAgo(int unixMs) {
  final local = DateTime.fromMillisecondsSinceEpoch(unixMs);
  if (DateTime.now().difference(local).inDays < 7) {
    return formatRelativeTime(unixMs, '');
  }
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

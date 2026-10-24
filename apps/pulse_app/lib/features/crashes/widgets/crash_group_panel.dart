import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../../app/theme/pulse_theme.dart';
import '../../../presentation/components/pulse_badge.dart';
import '../../../presentation/components/pulse_focus.dart';
import '../../timeline/widgets/detail_section.dart';
import '../../timeline/widgets/metadata_table.dart';
import '../crash_display.dart';

/// Inspector for one crash group: the explanation first, then what crashed,
/// the versions it happened on and the events to open (Level 2 / 3 live in
/// the Timeline details panel those open).
class CrashGroupPanel extends StatelessWidget {
  const CrashGroupPanel({
    super.key,
    required this.group,
    required this.onClose,
    required this.onOpenOccurrence,
    this.openingRecordId,
  });

  final CrashGroup group;
  final VoidCallback onClose;
  final ValueChanged<CrashOccurrence> onOpenOccurrence;

  /// The event being loaded, to show progress on its row.
  final int? openingRecordId;

  @override
  Widget build(BuildContext context) {
    final visual = CrashKindVisual.of(group.kind);
    final textTheme = Theme.of(context).textTheme;
    final hasRecommendation = group.recommendation.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, PulseTokens.pagePadX, 12),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: PulseTokens.surface,
          borderRadius: BorderRadius.circular(PulseTokens.radiusCard),
          border: Border.all(color: PulseTokens.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 10, 2),
              child: Row(
                children: [
                  Text(
                    'Crash details',
                    style: textTheme.labelLarge?.copyWith(
                      color: PulseTokens.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: onClose,
                    icon: const Icon(LucideIcons.x, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      PulseBadge(
                        label: visual.label,
                        tone: visual.tone,
                        icon: visual.icon,
                        compact: true,
                      ),
                      PulseBadge(
                        label: crashTimesLabel(group.count),
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    group.title.isNotEmpty ? group.title : visual.label,
                    style: textTheme.headlineSmall?.copyWith(
                      fontSize: 22,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    group.summary,
                    style: textTheme.bodyLarge?.copyWith(
                      color: PulseTokens.textSecondary,
                      fontSize: 15,
                    ),
                  ),
                  if (hasRecommendation) ...[
                    const SizedBox(height: 18),
                    _RecommendationBox(text: group.recommendation.trim()),
                  ],
                  const SizedBox(height: 8),
                  DetailSection(
                    title: 'What crashed',
                    child: MetadataTable(entries: _facts(group)),
                  ),
                  if (group.versions.isNotEmpty)
                    DetailSection(
                      title: 'Versions',
                      child: _VersionList(versions: group.versions),
                    ),
                  DetailSection(
                    title: group.count > group.recent.length
                        ? 'Newest ${group.recent.length} of ${group.count}'
                        : 'Each time',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final occurrence in group.recent)
                          _OccurrenceRow(
                            occurrence: occurrence,
                            opening: occurrence.recordId == openingRecordId,
                            onTap: () => onOpenOccurrence(occurrence),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Open one to see the full Windows event.',
                          style: textTheme.bodySmall?.copyWith(
                            color: PulseTokens.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<MetadataEntry> _facts(CrashGroup group) {
    final origin = faultingModuleOriginLabel(group.moduleOrigin);
    final owner = [
      if (origin.isNotEmpty) origin,
      if (group.moduleCompany.isNotEmpty) group.moduleCompany,
    ].join(' · ');
    final code = group.hasCode ? formatCrashCode(group.code) : '';
    final knownModule = group.moduleName.isNotEmpty &&
        group.moduleName.toLowerCase() != 'unknown';
    return switch (group.kind) {
      CrashKind.appCrash => [
          MetadataEntry('App', group.subject),
          MetadataEntry('File', knownModule ? group.moduleName : 'Unknown'),
          MetadataEntry('Belongs to', owner),
          MetadataEntry('Path', knownModule ? group.modulePath : ''),
          MetadataEntry('Exception code', code),
          ..._times(group),
        ],
      CrashKind.appHang => [
          MetadataEntry('App', group.subject),
          ..._times(group),
        ],
      CrashKind.blueScreen => [
          MetadataEntry(
            'Stop code',
            group.subject.isNotEmpty && code.isNotEmpty &&
                    group.subject != code
                ? '${group.subject} ($code)'
                : group.subject.isNotEmpty
                    ? group.subject
                    : code,
          ),
          ..._times(group),
        ],
      CrashKind.serviceCrash => [
          MetadataEntry('Service', group.subject),
          ..._times(group),
        ],
      CrashKind.gpuReset => [
          MetadataEntry('Driver', group.subject),
          ..._times(group),
        ],
      CrashKind.unexpectedRestart ||
      CrashKind.hardwareError ||
      CrashKind.unspecified =>
        _times(group),
    };
  }

  static List<MetadataEntry> _times(CrashGroup group) => [
        MetadataEntry('Last time', formatCrashTime(group.lastUnixMs)),
        if (group.count > 1)
          MetadataEntry('First time', formatCrashTime(group.firstUnixMs)),
      ];
}

class _RecommendationBox extends StatelessWidget {
  const _RecommendationBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tone = PulseTokens.severityWarning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(PulseTokens.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.circleAlert, size: 20, color: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What you can do',
                  style: textTheme.titleSmall?.copyWith(
                    color: PulseTokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: textTheme.bodyMedium?.copyWith(
                    color: PulseTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionList extends StatelessWidget {
  const _VersionList({required this.versions});

  final List<CrashVersion> versions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        for (var i = 0; i < versions.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  versions[i].version,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontFamily: PulseTheme.monoFont,
                    fontFamilyFallback: PulseTheme.monoFallback,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  '${crashTimesLabel(versions[i].count)} · last '
                  '${formatCrashAgo(versions[i].lastUnixMs)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: PulseTokens.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _OccurrenceRow extends StatelessWidget {
  const _OccurrenceRow({
    required this.occurrence,
    required this.opening,
    required this.onTap,
  });

  final CrashOccurrence occurrence;
  final bool opening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(PulseTokens.radiusMd);
    return PulseFocus(
      onPressed: onTap,
      borderRadius: radius,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          mouseCursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    formatCrashTime(occurrence.timestampUnixMs),
                    style: textTheme.bodyMedium?.copyWith(
                      fontFamily: PulseTheme.monoFont,
                      fontFamilyFallback: PulseTheme.monoFallback,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                if (occurrence.version.isNotEmpty) ...[
                  Text(
                    occurrence.version,
                    style: textTheme.bodySmall?.copyWith(
                      color: PulseTokens.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (opening)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: PulseTokens.textTertiary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

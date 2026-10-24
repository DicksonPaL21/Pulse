import 'package:flutter/material.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../../app/theme/pulse_theme.dart';
import '../../../presentation/components/pulse_badge.dart';
import '../../../presentation/components/pulse_focus.dart';
import '../../../presentation/components/safe_hover.dart';
import '../crash_display.dart';

/// One crash group: what happened in plain language, how often, and when.
class CrashGroupTile extends StatefulWidget {
  const CrashGroupTile({
    super.key,
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final CrashGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<CrashGroupTile> createState() => _CrashGroupTileState();
}

class _CrashGroupTileState extends State<CrashGroupTile> with SafeHoverState {
  static const double _rowRadius = 12;
  static const double _iconWell = 36;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final visual = CrashKindVisual.of(group.kind);
    final selected = widget.selected;
    final textTheme = Theme.of(context).textTheme;

    return PulseFocus(
      onPressed: widget.onTap,
      borderRadius: BorderRadius.circular(_rowRadius),
      child: AnimatedContainer(
        duration: PulseTokens.motionFast,
        curve: PulseTokens.motionCurve,
        decoration: BoxDecoration(
          color: selected || hover
              ? PulseTokens.surfaceElevated
              : Colors.transparent,
          borderRadius: BorderRadius.circular(_rowRadius),
          border: Border.all(
            color: selected
                ? PulseTokens.accent.withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onHover: setHovered,
            borderRadius: BorderRadius.circular(_rowRadius),
            splashColor: visual.color.withValues(alpha: 0.06),
            highlightColor: visual.color.withValues(alpha: 0.03),
            mouseCursor: SystemMouseCursors.click,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: _iconWell,
                    height: _iconWell,
                    decoration: BoxDecoration(
                      color: visual.color.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(PulseTokens.radiusIconWell),
                    ),
                    child: Icon(visual.icon, size: 18, color: visual.color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              group.title.isNotEmpty ? group.title : visual.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(
                                fontSize: 15,
                                height: 1.3,
                              ),
                            ),
                            if (group.subject.isNotEmpty &&
                                group.kind == CrashKind.blueScreen)
                              PulseBadge(
                                label: group.subject,
                                tone: visual.tone,
                                compact: true,
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          group.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            color: PulseTokens.textSecondary,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _metaLine(group, visual),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: PulseTokens.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CountLabel(count: group.count, color: visual.color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// When and what kind: "Last 2d ago · first 2026-10-04 · App crash".
  static String _metaLine(CrashGroup group, CrashKindVisual visual) {
    final parts = <String>[
      'Last ${formatCrashAgo(group.lastUnixMs)}',
      if (group.count > 1 && group.firstUnixMs != group.lastUnixMs)
        'first ${formatCrashAgo(group.firstUnixMs)}',
      visual.label,
    ];
    return parts.join(' · ');
  }
}

class _CountLabel extends StatelessWidget {
  const _CountLabel({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: crashTimesLabel(count),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$count',
              style: textTheme.titleLarge?.copyWith(
                fontFamily: PulseTheme.monoFont,
                fontFamilyFallback: PulseTheme.monoFallback,
                letterSpacing: 0,
                fontWeight: FontWeight.w500,
                color: count > 1 ? color : PulseTokens.textSecondary,
              ),
            ),
            Text(
              count == 1 ? 'time' : 'times',
              style: textTheme.bodySmall?.copyWith(
                color: PulseTokens.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

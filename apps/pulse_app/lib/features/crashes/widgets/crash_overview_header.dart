import 'package:flutter/material.dart';

import '../../../app/theme/pulse_theme.dart';
import '../../../application/crash_history_controller.dart';
import '../../../presentation/components/pulse_focus.dart';
import '../../../presentation/components/pulse_segmented_control.dart';
import '../../../presentation/components/safe_hover.dart';
import '../crash_display.dart';
import '../crash_history_summary.dart';

/// Crashes hero, in the Timeline hero's style: a plain-language sentence, the
/// period, one counter per category (each filters the list) and a bar per day.
class CrashOverviewHeader extends StatelessWidget {
  const CrashOverviewHeader({
    super.key,
    required this.summary,
    required this.selectedDays,
    required this.selectedCategory,
    required this.onCategory,
    required this.onDays,
  });

  final CrashHistorySummary summary;

  /// The period picked, which may still be loading.
  final int selectedDays;

  /// Null shows every category.
  final CrashCategory? selectedCategory;
  final ValueChanged<CrashCategory?> onCategory;
  final ValueChanged<int> onDays;

  static const double _stripHeight = 56;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mono = TextStyle(
      fontFamily: PulseTheme.monoFont,
      fontFamilyFallback: PulseTheme.monoFallback,
      letterSpacing: 0,
    );
    final eyebrow = [
      'Last ${summary.days} days',
      if (summary.lastCrashUnixMs > 0)
        'last crash ${formatCrashAgo(summary.lastCrashUnixMs)}',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 20),
      decoration: BoxDecoration(
        color: PulseTokens.surface,
        borderRadius: BorderRadius.circular(PulseTokens.radiusCard),
        border: Border.all(color: PulseTokens.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 32,
            runSpacing: 16,
            alignment: WrapAlignment.spaceBetween,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow.toUpperCase(),
                      style: textTheme.labelSmall?.merge(mono).copyWith(
                            color: PulseTokens.textTertiary,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      summary.headline,
                      style: textTheme.headlineMedium?.copyWith(
                        fontSize: 30,
                        height: 1.15,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      summary.detail,
                      style: textTheme.bodyLarge?.copyWith(
                        color: PulseTokens.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              PulseSegmentedControl<int>(
                segments: [
                  for (final days in CrashHistoryController.periods)
                    PulseSegment(value: days, label: '$days days'),
                ],
                selected: selectedDays,
                onChanged: onDays,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in CrashCategory.values)
                _CategoryCounter(
                  category: category,
                  count: summary.counts[category] ?? 0,
                  selected: selectedCategory == category,
                  mono: mono,
                  onTap: () => onCategory(
                    selectedCategory == category ? null : category,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Semantics(
            label: 'Crashes per day over the last ${summary.days} days. '
                '${summary.total} in total.',
            child: ExcludeSemantics(
              child: SizedBox(
                height: _stripHeight,
                child: _DayStrip(summary: summary),
              ),
            ),
          ),
          const SizedBox(height: 8),
          DefaultTextStyle(
            style: (textTheme.labelSmall ?? const TextStyle())
                .merge(mono)
                .copyWith(color: PulseTokens.textTertiary, fontSize: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${summary.days} days ago'),
                Text('${summary.days ~/ 2} days ago'),
                const Text('Today'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCounter extends StatefulWidget {
  const _CategoryCounter({
    required this.category,
    required this.count,
    required this.selected,
    required this.mono,
    required this.onTap,
  });

  final CrashCategory category;
  final int count;
  final bool selected;
  final TextStyle mono;
  final VoidCallback onTap;

  @override
  State<_CategoryCounter> createState() => _CategoryCounterState();
}

class _CategoryCounterState extends State<_CategoryCounter>
    with SafeHoverState {
  static const double _width = 148;

  Color? get _highlight {
    if (widget.count == 0) return null;
    return switch (widget.category) {
      CrashCategory.blueScreens => PulseTokens.severityCritical,
      CrashCategory.appCrashes ||
      CrashCategory.restarts =>
        PulseTokens.severityError,
      CrashCategory.notResponding ||
      CrashCategory.other =>
        PulseTokens.severityWarning,
    };
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(PulseTokens.radiusLg);
    final selected = widget.selected;
    return Semantics(
      button: true,
      selected: selected,
      label: '${widget.category.label}: ${widget.count}. '
          '${selected ? 'Showing only these. Tap to show all.' : 'Tap to show only these.'}',
      child: PulseFocus(
        onPressed: widget.onTap,
        borderRadius: radius,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setHovered(true),
          onExit: (_) => setHovered(false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: PulseTokens.motionFast,
              curve: PulseTokens.motionCurve,
              width: _width,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: selected || hover
                    ? PulseTokens.surfaceElevated
                    : Colors.transparent,
                borderRadius: radius,
                border: Border.all(
                  color: selected
                      ? PulseTokens.accent.withValues(alpha: 0.45)
                      : PulseTokens.stroke,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall
                        ?.copyWith(color: PulseTokens.textTertiary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.count}',
                    style: textTheme.headlineSmall?.merge(widget.mono).copyWith(
                          fontSize: 26,
                          height: 1.1,
                          fontWeight: FontWeight.w500,
                          color: _highlight ?? PulseTokens.textPrimary,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.summary});

  final CrashHistorySummary summary;

  static const double _minBarHeight = 4;

  @override
  Widget build(BuildContext context) {
    final peak = summary.peakBucketCount;
    final buckets = summary.buckets;
    // Narrower gaps when there are many days, so 90 bars still fit.
    final gap = buckets.length > 45 ? 1.5 : 3.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < buckets.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bucket = buckets[i];
                final ratio = peak == 0 ? 0.0 : bucket.count / peak;
                final height = _minBarHeight +
                    ratio * (constraints.maxHeight - _minBarHeight);
                final worst = bucket.worst;
                return Tooltip(
                  message: '${_dayLabel(bucket.day)}: '
                      '${bucket.count == 0 ? 'no crashes' : crashTimesLabel(bucket.count)}',
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: height,
                      decoration: BoxDecoration(
                        color: worst == null
                            ? PulseTokens.strokeStrong
                            : CrashKindVisual.of(worst).color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  static String _dayLabel(DateTime day) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${day.year}-${two(day.month)}-${two(day.day)}';
  }
}

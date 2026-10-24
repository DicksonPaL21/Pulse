import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../app/theme/pulse_theme.dart';
import '../../application/connection_controller.dart';
import '../../application/crash_history_controller.dart';
import '../../features/crashes/crash_history_summary.dart';
import '../../features/crashes/widgets/crash_group_panel.dart';
import '../../features/crashes/widgets/crash_group_tile.dart';
import '../../features/crashes/widgets/crash_overview_header.dart';
import '../../features/timeline/widgets/timeline_details_panel.dart';
import '../../ipc/pulse_ipc_client.dart';
import '../components/pulse_app_bar.dart';
import '../components/pulse_empty_state.dart';
import '../components/pulse_loading.dart';
import '../components/service_lifecycle_controls.dart';
import '../utils/pulse_snack.dart';
import '../utils/pulse_user_errors.dart';

/// Crash history (doc 43): blue screens, app crashes and hangs, unexpected
/// restarts and other failures of the last days, grouped by cause and
/// explained. Read from the Event Log by PulseService on demand.
class CrashesPage extends StatefulWidget {
  const CrashesPage({super.key, required this.title});

  final String title;

  @override
  State<CrashesPage> createState() => _CrashesPageState();
}

class _CrashesPageState extends State<CrashesPage> {
  String? _selectedKey;
  CrashCategory? _category;

  /// A Windows event opened from the selected group.
  TimelineEvent? _openedEvent;
  int? _openingRecordId;

  void _select(CrashGroup group) {
    setState(() {
      _selectedKey = group.key == _selectedKey ? null : group.key;
      _openedEvent = null;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedKey = null;
      _openedEvent = null;
    });
  }

  Future<void> _openOccurrence(CrashOccurrence occurrence) async {
    if (_openingRecordId != null) return;
    setState(() => _openingRecordId = occurrence.recordId);
    try {
      final detail = await context.read<PulseIpcClient>().getTimelineEventDetail(
            channel: occurrence.channel,
            recordId: occurrence.recordId,
          );
      if (!mounted) return;
      if (!detail.found) {
        PulseSnack.info(
          context,
          'This event is no longer in the Windows log. Windows removes old '
          'events when a log is full.',
        );
        return;
      }
      setState(() => _openedEvent = detail.event);
    } catch (e) {
      if (!mounted) return;
      PulseSnack.error(context, PulseUserErrors.fromObject(e));
    } finally {
      if (mounted) setState(() => _openingRecordId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CrashHistoryController>();
    final connectionLabel = context.select<ConnectionController, String>(
      (c) => c.statusLabel,
    );
    final state = context.select<PulseIpcClient, IpcConnectionState>(
      (c) => c.status.state,
    );
    final offline = state == IpcConnectionState.disconnected ||
        state == IpcConnectionState.error;
    final history = controller.history;

    final Widget body;
    if (offline) {
      body = const ServiceOfflineRecovery(titleFallback: 'Ready when Windows is');
    } else if (history == null && controller.error != null) {
      body = PulseEmptyState(
        useBrandIllustration: true,
        title: 'Could not read the crash history',
        message: controller.error!,
        actionLabel: 'Retry',
        onAction: controller.load,
      );
    } else if (history == null) {
      body = const _CrashesLoading();
    } else {
      final groups = crashGroupsIn(history, _category);
      CrashGroup? selected;
      for (final group in groups) {
        if (group.key == _selectedKey) selected = group;
      }
      body = _CrashesBody(
        history: history,
        summary: CrashHistorySummary.from(history, now: DateTime.now()),
        groups: groups,
        selectedDays: controller.days,
        loading: controller.loading,
        refreshError: controller.error,
        category: _category,
        selected: selected,
        openedEvent: _openedEvent,
        openingRecordId: _openingRecordId,
        onCategory: (category) => setState(() => _category = category),
        onDays: (days) {
          _clearSelection();
          controller.setDays(days);
        },
        onSelect: _select,
        onClear: _clearSelection,
        onOpenOccurrence: _openOccurrence,
        onCloseEvent: () => setState(() => _openedEvent = null),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PulseAppBar(
          title: widget.title,
          connectionState: state,
          connectionLabel: connectionLabel,
          headerActions: [
            PulseHeaderAction(
              label: 'Refresh',
              icon: LucideIcons.refreshCw,
              tooltip: 'Read the crash history again',
              onPressed:
                  offline || controller.loading ? null : controller.load,
            ),
          ],
        ),
        Expanded(child: body),
      ],
    );
  }
}

class _CrashesBody extends StatelessWidget {
  const _CrashesBody({
    required this.history,
    required this.summary,
    required this.groups,
    required this.selectedDays,
    required this.loading,
    required this.refreshError,
    required this.category,
    required this.selected,
    required this.openedEvent,
    required this.openingRecordId,
    required this.onCategory,
    required this.onDays,
    required this.onSelect,
    required this.onClear,
    required this.onOpenOccurrence,
    required this.onCloseEvent,
  });

  final CrashHistory history;
  final CrashHistorySummary summary;

  /// Groups in [category], newest first.
  final List<CrashGroup> groups;
  final int selectedDays;
  final bool loading;

  /// A failed reload; the previous history stays on screen.
  final String? refreshError;
  final CrashCategory? category;
  final CrashGroup? selected;
  final TimelineEvent? openedEvent;
  final int? openingRecordId;
  final ValueChanged<CrashCategory?> onCategory;
  final ValueChanged<int> onDays;
  final ValueChanged<CrashGroup> onSelect;
  final VoidCallback onClear;
  final ValueChanged<CrashOccurrence> onOpenOccurrence;
  final VoidCallback onCloseEvent;

  /// Inspector width including its right gutter, as in the Timeline.
  static const double _detailsPanelWidth = 452;
  static const double _wideLayoutWidth = 980;

  Widget? _inspector() {
    final group = selected;
    if (group == null) return null;
    final event = openedEvent;
    if (event != null) {
      return TimelineDetailsPanel(
        key: ValueKey('crash-event-${event.eventId}'),
        event: event,
        onClose: onCloseEvent,
      );
    }
    return CrashGroupPanel(
      key: ValueKey('crash-group-${group.key}'),
      group: group,
      onClose: onClear,
      onOpenOccurrence: onOpenOccurrence,
      openingRecordId: openingRecordId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideLayoutWidth;
        final inspector = _inspector();
        final list = CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                PulseTokens.pagePadX,
                4,
                PulseTokens.pagePadX,
                8,
              ),
              sliver: SliverToBoxAdapter(
                child: CrashOverviewHeader(
                  summary: summary,
                  selectedDays: selectedDays,
                  selectedCategory: category,
                  onCategory: onCategory,
                  onDays: onDays,
                ),
              ),
            ),
            for (final notice in _notices())
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  PulseTokens.pagePadX,
                  8,
                  PulseTokens.pagePadX,
                  0,
                ),
                sliver: SliverToBoxAdapter(child: notice),
              ),
            if (loading)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  PulseTokens.pagePadX,
                  12,
                  PulseTokens.pagePadX,
                  0,
                ),
                sliver: SliverToBoxAdapter(child: LinearProgressIndicator()),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                PulseTokens.pagePadX,
                12,
                PulseTokens.pagePadX,
                PulseTokens.pagePadBottom,
              ),
              sliver: groups.isEmpty
                  ? SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: _emptyState(),
                      ),
                    )
                  : DecoratedSliver(
                      decoration: BoxDecoration(
                        color: PulseTokens.surface,
                        borderRadius:
                            BorderRadius.circular(PulseTokens.radiusCard),
                        border: Border.all(color: PulseTokens.stroke),
                      ),
                      sliver: SliverPadding(
                        padding: const EdgeInsets.all(10),
                        sliver: SliverList.separated(
                          itemCount: groups.length,
                          separatorBuilder: (context, i) =>
                              const SizedBox(height: 2),
                          itemBuilder: (context, i) {
                            final group = groups[i];
                            return CrashGroupTile(
                              key: ValueKey(group.key),
                              group: group,
                              selected: group.key == selected?.key,
                              onTap: () => onSelect(group),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ],
        );

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: list),
              if (inspector != null)
                SizedBox(width: _detailsPanelWidth, child: inspector),
            ],
          );
        }
        return Stack(
          children: [
            Positioned.fill(child: list),
            if (inspector != null)
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onClear,
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.38),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: constraints.maxWidth.clamp(300, 420),
                      child: inspector,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _emptyState() {
    if (summary.total == 0) {
      return const PulseEmptyState(
        useBrandIllustration: true,
        title: 'No crashes',
        message: 'Windows recorded no blue screens, app crashes, hangs or '
            'unexpected restarts in this period.',
      );
    }
    return PulseEmptyState(
      icon: LucideIcons.listFilter,
      title: 'Nothing in this category',
      message: 'Other kinds of crashes happened in this period.',
      actionLabel: 'Show all',
      onAction: () => onCategory(null),
    );
  }

  List<Widget> _notices() {
    return [
      if (refreshError != null)
        _Notice(
          icon: LucideIcons.triangleAlert,
          text: 'Could not refresh: $refreshError Showing the last result.',
        ),
      if (history.truncated)
        const _Notice(
          icon: LucideIcons.info,
          text: 'There were more crash events than Pulse reads at once, so '
              'the oldest ones in this period are not counted.',
        ),
      if (history.unreadableChannels.isNotEmpty)
        _Notice(
          icon: LucideIcons.triangleAlert,
          text: 'Pulse could not read the '
              '${history.unreadableChannels.join(' and ')} log, so its '
              'crashes are missing here.',
        ),
    ];
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: PulseTokens.surface,
        borderRadius: BorderRadius.circular(PulseTokens.radiusLg),
        border: Border.all(color: PulseTokens.stroke),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: PulseTokens.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PulseTokens.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrashesLoading extends StatelessWidget {
  const _CrashesLoading();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PulseTokens.space2xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PulseInlineSpinner(size: 28),
            const SizedBox(height: PulseTokens.spaceLg),
            Text(
              'Reading the crash history…',
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(
                fontSize: 22,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'PulseService is looking through the Windows logs.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: PulseTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

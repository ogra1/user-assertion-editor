import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaru/yaru.dart';

import '../models/wizard_state.dart';
import '../models/wizard_step.dart';
import '../services/status_bar_service.dart';
import '../theme/status_colors.dart';
import '../widgets/status_bar_content.dart';
import '../widgets/truncating_tooltip_text.dart';
import 'device_page.dart';
import 'export_page.dart';
import 'sign_page.dart';
import 'timing_page.dart';
import 'user_page.dart';

/// The app shell: window title bar, a collapsible navigation rail holding
/// the five wizard steps, the step body, and a footer with status +
/// Back/Next.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final WizardState _state = WizardState();
  WizardStep _current = WizardStep.user;
  bool _extendedRail = true;
  KeyEventCallback? _escapeHandler;

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// Switches the visible step and records that the user has reached it, so
  /// the rail checkmark for that step (and the steps it implies) can appear.
  void _setCurrent(WizardStep step) {
    if (step == _current) return;
    _state.markVisited(step);
    setState(() => _current = step);
  }

  void _goTo(WizardStep step) {
    if (_state.isStepEnabled(step)) {
      StatusBarService.instance.clear();
      _setCurrent(step);
    } else {
      _showBlockedStatus(step);
    }
  }

  void _showBlockedStatus(WizardStep step) {
    for (final s in WizardStep.values) {
      if (s.index >= step.index) break;
      if (!_state.isStepComplete(s)) {
        final errors = _state.errorsFor(s);
        StatusBarService.instance.error(
          'Complete "${s.label}" first: ${errors.isNotEmpty ? errors.first : ''}',
        );
        return;
      }
    }
  }

  bool get _canGoNext =>
      _state.isStepComplete(_current) &&
      _current.index < WizardStep.values.length - 1;

  bool get _canGoBack => _current.index > 0;

  void _next() {
    if (_canGoNext) _goTo(WizardStep.values[_current.index + 1]);
  }

  void _back() {
    if (_canGoBack) {
      StatusBarService.instance.clear();
      _setCurrent(WizardStep.values[_current.index - 1]);
    }
  }

  // Global Escape handler: dismiss the status-bar error even when no
  // widget has focus.
  bool _handleGlobalKey(KeyEvent event) {
    if (event is KeyUpEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      StatusBarService.instance.clear();
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _escapeHandler = _handleGlobalKey;
    HardwareKeyboard.instance.addHandler(_escapeHandler!);
    _state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    if (_escapeHandler != null) {
      HardwareKeyboard.instance.removeHandler(_escapeHandler!);
    }
    _state.removeListener(_onStateChanged);
    _state.dispose();
    super.dispose();
  }

  Widget _buildBody() {
    switch (_current) {
      case WizardStep.user:
        return UserPage(state: _state);
      case WizardStep.device:
        return DevicePage(state: _state);
      case WizardStep.timing:
        return TimingPage(state: _state);
      case WizardStep.sign:
        return SignPage(state: _state);
      case WizardStep.export:
        return ExportPage(state: _state);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: YaruWindowTitleBar(
        title: const Text('User Assertion Editor'),
        leading: Padding(
          padding: EdgeInsets.only(left: 8),
          child: SizedBox(
            width: 20,
            height: 20,
            child: Image.asset('assets/icon.png'),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _buildNavigationRail(),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Stack(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: KeyedSubtree(
                          key: ValueKey(_current),
                          child: _buildBody(),
                        ),
                      ),
                      if (_state.busy) _buildBusyOverlay(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _buildFooterBar(),
        ],
      ),
    );
  }

  Widget _buildBusyOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x33000000),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              if (_state.busyMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_state.busyMessage!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static const double _railExtendedWidth = 240;
  static const double _railCollapsedWidth = 84;

  Widget _buildNavigationRail() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: _extendedRail ? _railExtendedWidth : _railCollapsedWidth,
      child: NavigationRail(
        extended: _extendedRail,
        scrollable: true,
        minWidth: _railCollapsedWidth,
        minExtendedWidth: _railExtendedWidth,
        selectedIndex: _current.index,
        onDestinationSelected: (i) => _goTo(WizardStep.values[i]),
        leading: _buildBrandHeader(),
        destinations: WizardStep.values.map((step) {
          final complete = _state.showStepComplete(step);
          final enabled = _state.isStepEnabled(step);
          return NavigationRailDestination(
            disabled: !enabled,
            icon: _StepIcon(
                icon: step.icon, complete: complete, enabled: enabled),
            selectedIcon: _StepIcon(
                icon: step.selectedIcon,
                complete: complete,
                enabled: enabled,
                selected: true),
            label: Text(step.label),
          );
        }).toList(),
        trailing: _buildRailFooter(),
      ),
    );
  }

  static const double _headerWideWidth = 100;

  Widget _buildBrandHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _headerWideWidth;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  left: 10, right: 6, top: 8, bottom: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.asset('assets/icon.png', width: 30, height: 30),
                  ),
                  if (wide) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'User Assertion',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  IconButton(
                    icon: Icon(_extendedRail
                        ? Icons.chevron_left
                        : Icons.chevron_right),
                    tooltip: _extendedRail ? 'Collapse' : 'Expand',
                    onPressed:
                        () => setState(() => _extendedRail = !_extendedRail),
                    iconSize: 18,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            if (wide)
              Container(height: 1, color: Theme.of(context).dividerColor),
          ],
        );
      },
    );
  }

  Widget _buildRailFooter() {
    final done = _current == WizardStep.export &&
        (_state.signOutput?.report.allPassed ?? false);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Tooltip(
        message: 'system-user assertion builder',
        child: Icon(
          done ? YaruIcons.checkmark : YaruIcons.user,
          size: 22,
          color: done
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildFooterBar() {
    final hint = _current != WizardStep.export
        ? _state.errorsFor(_current).firstOrNull
        : (_state.signOutput?.report.allPassed ?? false)
            ? null
            : 'Sign the assertion in this step.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: StatusBarService.instance,
              // A fresh (non-const) widget per build so the newest message
              // actually renders.
              builder: (context, _) =>
                  StatusBarService.instance.hasCurrent
                      ? const StatusBarContent()
                      : _footerHint(hint),
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton(
            onPressed: _canGoBack ? _back : null,
            child: const Text('Back'),
          ),
          const SizedBox(width: 12),
          if (_current != WizardStep.export)
            ElevatedButton(
              onPressed: _canGoNext ? _next : null,
              child: const Text('Next'),
            ),
        ],
      ),
    );
  }

  Widget _footerHint(String? hint) {
    if (hint == null || hint.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(Icons.info_outline,
            size: 18, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 8),
        Flexible(
          child: TruncatingTooltipText(
            hint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ),
      ],
    );
  }
}

/// A step icon, mirroring the model-builder rail: the step's own
/// icon is always shown (so the collapsed rail is still readable as
/// person / device / schedule / key / download), and a small green
/// check badge is overlaid once the step is complete. Locked steps are
/// dimmed.
class _StepIcon extends StatelessWidget {
  final IconData icon;
  final bool complete;
  final bool enabled;
  final bool selected;

  const _StepIcon({
    required this.icon,
    required this.complete,
    required this.enabled,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = enabled
        ? (selected ? theme.colorScheme.primary : null)
        : theme.disabledColor;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, color: baseColor),
        if (complete)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle,
                  size: 14, color: StatusColors.success),
            ),
          ),
      ],
    );
  }
}

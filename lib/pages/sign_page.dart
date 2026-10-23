import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/wizard_state.dart';
import '../services/signing_key_service.dart';

/// Step 4 — choose the brand key that will sign the assertion.
class SignPage extends StatefulWidget {
  final WizardState state;
  const SignPage({super.key, required this.state});

  @override
  State<SignPage> createState() => _SignPageState();
}

class _SignPageState extends State<SignPage> {
  static const _prefLastKeyName = 'sign.lastKeyName';

  final SigningKeyService _service = const SigningKeyService();
  List<SigningKey> _keys = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _keys = await _service.listKeys();
      if (!mounted) return;

      // Drop a previously selected key that no longer exists.
      final selected = widget.state.selectedKeyName;
      if (selected != null &&
          !_keys.any((k) => k.name == selected)) {
        widget.state.selectedKeyName = null;
        widget.state.setSignOutput(null);
      }

      // Restore the remembered key when nothing is selected.
      if (widget.state.selectedKeyName == null) {
        String? remembered;
        try {
          final prefs = await SharedPreferences.getInstance();
          remembered = prefs.getString(_prefLastKeyName);
        } catch (_) {}
        if (remembered != null &&
            _keys.any((k) => k.name == remembered)) {
          widget.state.selectedKeyName = remembered;
          widget.state.setSignOutput(null);
        }
      }
    } on Exception catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
      if (mounted) widget.state.refresh();
    }
  }

  void _select(SigningKey key) {
    widget.state.selectedKeyName = key.name;
    widget.state.setSignOutput(null); // key change invalidates prior signing
    widget.state.refresh();
    try {
      SharedPreferences.getInstance()
          .then((p) => p.setString(_prefLastKeyName, key.name));
    } catch (_) {}
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.state.selectedKeyName;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Signing Key', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'The assertion must be signed by a key belonging to the brand '
          '(or a model-listed system-user-authority). Choose a key from your '
          'local snapd keyring.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        YaruSection(
          headline: Row(
            children: [
              const Text('Local keys (snap keys)'),
              const Spacer(),
              TextButton.icon(
                icon: Icon(YaruIcons.refresh, size: 18),
                label: const Text('Refresh'),
                onPressed: _loading ? null : _loadKeys,
              ),
            ],
          ),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _error != null
                  ? Column(
                      children: [
                        Row(
                          children: [
                            Icon(YaruIcons.error,
                                color: Theme.of(context).colorScheme.error,
                                size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(YaruIcons.refresh, size: 18),
                          label: const Text('Try again'),
                          onPressed: _loadKeys,
                        ),
                      ],
                    )
                  : _keys.isEmpty
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('No signing keys found.'),
                            const SizedBox(height: 8),
                            Text(
                              'Create one in a terminal with:\n\n'
                              '    snap create-key my-brand-key\n\n'
                              'then register it with the store:\n\n'
                              '    snapcraft login\n'
                              '    snap export-key my-brand-key <account-id>\n\n'
                              'Finally press "Refresh".',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                  ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            for (final key in _keys)
                              ListTile(
                                selected: key.name == selected,
                                selectedTileColor: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 12),
                                leading: Icon(
                                  key.name == selected
                                      ? YaruIcons.checkmark
                                      : YaruIcons.key,
                                  color: key.name == selected
                                      ? Theme.of(context)
                                          .colorScheme
                                          .primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                ),
                                title: Text(key.name,
                                    style: const TextStyle(
                                        fontFamily: 'monospace')),
                                subtitle: Text(
                                    '${key.sha3384.substring(0, key.sha3384.length > 16 ? 16 : key.sha3384.length)}\u2026'),
                                onTap: () => _select(key),
                              ),
                          ],
                        ),
        ),
        if (_keys.isNotEmpty && selected == null)
          const SizedBox(height: 16),
        if (_keys.isNotEmpty && selected == null)
          Text(
            'Select a key to continue.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
      ],
    );
  }
}

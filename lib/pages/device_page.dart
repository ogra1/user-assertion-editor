import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../models/wizard_state.dart';
import '../widgets/form_fields.dart';
import '../widgets/tag_chip_field.dart';

/// Step 2 — which brand and device model(s) the assertion applies to.
class DevicePage extends StatefulWidget {
  final WizardState state;
  const DevicePage({super.key, required this.state});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final _brand = TextEditingController();
  final _authority = TextEditingController();
  bool _mirrorAuthority = true;

  @override
  void initState() {
    super.initState();
    final u = widget.state.model;
    _brand.text = u.brandId;
    _authority.text = u.authorityId;
  }

  @override
  void dispose() {
    _brand.dispose();
    _authority.dispose();
    super.dispose();
  }

  void _commit() {
    final u = widget.state.model;
    u.brandId = _brand.text.trim();
    if (_mirrorAuthority) {
      u.authorityId = _brand.text.trim();
    } else {
      u.authorityId = _authority.text.trim();
    }
    widget.state.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.state.model;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Device', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Which systems may create this user from the assertion?',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        YaruSection(
          headline: const Text('Brand'),
          child: Column(
            children: [
              FormTextField(
                label: 'Brand ID *',
                controller: _brand,
                hint: 'Your Snap Store account ID',
                helper:
                    'Found at dashboard.snapcraft.io → Account ("Snap account id"). '
                    'The brand owns the device model.',
                onChanged: (_) {
                  _commit();
                },
              ),
              const SizedBox(height: 16),
              FormTextField(
                label: 'Authority ID',
                controller: _authority,
                hint: 'Defaults to the brand ID',
                helper: 'The account that signs this assertion. When the model '
                    'assertion has no system-user-authority field, this must be '
                    'the brand or a listed authority.',
                onChanged: (v) {
                  _mirrorAuthority = v.trim() == _brand.text.trim();
                  _commit();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        YaruSection(
          headline: const Text('Models'),
          // Left-align the (narrower) chip box regardless of how wide the
          // intro paragraph above it wraps — otherwise the box appears
          // centred under the heading.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Leave empty to make a "global" assertion that works on any '
                'model of the brand — but snapd then limits it to 365 days '
                'of validity. Naming models is the common case.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              TagChipField(
                label: 'Model names',
                values: u.models,
                onChanged: (v) {
                  u.models
                    ..clear()
                    ..addAll(v);
                  widget.state.refresh();
                },
                hint: 'e.g. pc-amd64',
                helper: 'The "model" value from the device model assertion.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        YaruSection(
          headline: const Text('Device serials (optional)'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Restrict the assertion to specific devices. Requires exactly '
                'one model above.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              TagChipField(
                label: 'Serial numbers',
                values: u.serials,
                onChanged: (v) {
                  u.serials
                    ..clear()
                    ..addAll(v);
                  widget.state.refresh();
                },
                hint: 'e.g. 12345678',
                helper: 'The device serial (snap device info → serial).',
              ),
              if (u.hasSerials && u.models.length != 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Serials require exactly one model — you have '
                    '${u.models.length}.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:yaru/yaru.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/wizard_state.dart';
import '../services/assertion_builder.dart';
import '../services/assertion_verifier.dart';
import '../services/sign_service.dart';
import '../services/status_bar_service.dart';
import '../services/import_service.dart';
import '../theme/status_colors.dart';

/// Step 5 — review the JSON, sign, verify, and save the result.
class ExportPage extends StatefulWidget {
  final WizardState state;
  const ExportPage({super.key, required this.state});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  static const _prefAlsoSaveJson = 'export.alsoSaveJson';
  static const _prefLastDir = 'export.lastDir';

  bool _signing = false;
  bool _alsoSaveJson = false;
  String? _lastDir;
  String? _savedPath;
  String? _jsonSavedPath;
  String _previewTab = 'json'; // json | chain
  bool _showPreview = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_prefAlsoSaveJson);
      final dir = prefs.getString(_prefLastDir);
      if (mounted) {
        setState(() {
          if (saved != null) _alsoSaveJson = saved;
          if (dir != null && dir.isNotEmpty) _lastDir = dir;
        });
      }
    } catch (_) {}
  }

  Future<void> _sign() async {
    final keyName = widget.state.selectedKeyName;
    if (keyName == null) return;

    setState(() => _signing = true);
    try {
      final result = await SignService().sign(widget.state.model, keyName);
      final report = await AssertionVerifier().verify(
        signedChain: result.signedChain,
        user: widget.state.model,
        keyName: keyName,
      );
      if (!mounted) return;
      setState(() {
        _previewTab = 'chain';
      });
      widget.state.model.signedChain = result.signedChain;
      widget.state.model.jsonHeader = result.jsonHeader;
      widget.state.setSignOutput(SignOutput(
        signedChain: result.signedChain,
        jsonHeader: result.jsonHeader,
        report: report,
        signedAt: DateTime.now(),
      ));
      _savedPath = null;
      _jsonSavedPath = null;
      if (!report.allPassed) {
        StatusBarService.instance.error(
            'Signed, but verification found problems — see the report.');
      } else {
        StatusBarService.instance.success(
            'Signed and verified. Save it as auto-import.assert.');
      }
    } on SignException catch (e) {
      if (mounted) StatusBarService.instance.error(e.message);
    } on Exception catch (e) {
      if (mounted) StatusBarService.instance.error('Signing failed: $e');
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  Future<void> _saveAs({bool json = false}) async {
    final output = widget.state.signOutput;
    if (output == null) return;

    final defaultName = json
        ? 'system-user.json'
        : 'auto-import.assert';

    try {
      final location = await getSaveLocation(
        acceptedTypeGroups: [
          XTypeGroup(
            label: json ? 'JSON' : 'Assertion',
            extensions: [json ? 'json' : 'assert'],
          ),
        ],
        suggestedName: defaultName,
        initialDirectory: _lastDir,
      );
      if (location == null) return;
      final path = location.path;
      final content = json ? output.jsonHeader : output.signedChain;
      await File(path).writeAsString(content);
      _lastDir = p.dirname(path);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefLastDir, _lastDir!);
        if (json) {
          await prefs.setBool(_prefAlsoSaveJson, _alsoSaveJson);
        }
      } catch (_) {}
      setState(() {
        if (json) {
          _jsonSavedPath = path;
        } else {
          _savedPath = path;
        }
      });
      StatusBarService.instance.success('Saved $path');
    } on Exception catch (e) {
      StatusBarService.instance.error('Could not save file: $e');
    }
  }

  Future<void> _importExisting() async {
    try {
      final picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Assertion / JSON',
            extensions: ['assert', 'json', 'txt'],
          ),
        ],
        initialDirectory: _lastDir,
      );
      if (picked == null) return;
      final path = picked.path;
      final text = await File(path).readAsString();
      final imported = ImportService().import(text);
      widget.state.replaceModel(imported.user);
      _lastDir = p.dirname(path);
      setState(() {
        _savedPath = null;
        _jsonSavedPath = null;
        _previewTab = 'json';
      });
      StatusBarService.instance.success('Imported $path');
    } on ImportException catch (e) {
      StatusBarService.instance.error(e.message);
    } on Exception catch (e) {
      StatusBarService.instance.error('Could not read file: $e');
    }
  }

  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      StatusBarService.instance.success('Copied to clipboard.');
    } catch (_) {
      StatusBarService.instance.error('Clipboard unavailable.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final output = widget.state.signOutput;
    final signed = output != null && output.report.allPassed;
    final keyName = widget.state.selectedKeyName;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Export',
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            TextButton.icon(
              icon: const Icon(YaruIcons.document_open, size: 18),
              label: const Text('Import existing'),
              onPressed: _importExisting,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Review the unsigned header, sign it, and save the resulting '
          'auto-import.assert.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),

        // Sign / re-sign controls
        YaruSection(
          headline: const Text('Sign'),
          child: Column(
            children: [
              Row(
                children: [
                  if (keyName != null) ...[
                    const Icon(YaruIcons.key_filled, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Key: $keyName',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ] else
                    const Text('No key selected (see Signing Key step).'),
                  const Spacer(),
                  ElevatedButton.icon(
                    icon: _signing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(YaruIcons.shield),
                    label: Text(signed ? 'Re-sign' : 'Sign assertion'),
                    onPressed:
                        (_signing || keyName == null) ? null : _sign,
                  ),
                ],
              ),
              if (signed)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Icon(YaruIcons.ok,
                          size: 18, color: StatusColors.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Signed & verified at ${output.signedAt.toLocal().toIso8601String().substring(0, 19)}.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(YaruIcons.save, size: 18),
                    label: Text(_savedPath == null
                        ? 'Save auto-import.assert\u2026'
                        : 'Saved: _savedPath'),
                    onPressed: output == null ? null : () => _saveAs(),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(YaruIcons.code, size: 18),
                    label: Text(_jsonSavedPath == null
                        ? 'Save JSON header\u2026'
                        : 'Saved: _jsonSavedPath'),
                    onPressed:
                        output == null ? null : () => _saveAs(json: true),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(YaruIcons.copy, size: 18),
                    label: const Text('Copy assertion'),
                    onPressed: output == null
                        ? null
                        : () => _copy(output.signedChain),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Also keep a copy of the JSON'),
                    value: _alsoSaveJson,
                    onChanged: (v) =>
                        setState(() => _alsoSaveJson = v ?? false),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Verification report
        if (output != null) ...[
          const SizedBox(height: 24),
          _ReportView(report: output.report),
        ],

        // Preview
        const SizedBox(height: 24),
        _PreviewPane(
          tab: _previewTab,
          onTabChanged: (t) => setState(() => _previewTab = t),
          visible: _showPreview,
          onToggle: () => setState(() => _showPreview = !_showPreview),
          json: widget.state.model.jsonHeader ??
              AssertionBuilder.preview(widget.state.model),
          chain: output?.signedChain,
        ),

        const SizedBox(height: 24),
        YaruSection(
          headline: const Text('How to use the file'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Step(num: 1, text: 'Copy auto-import.assert to the root of a '
                  'USB drive (FAT32 or ext4).'),
              _Step(num: 2, text: 'Insert it into the Ubuntu Core device and '
                  'reboot. snapd auto-imports it and creates the user.'),
              _Step(num: 3, text: 'Alternatively, seed it into an image with '
                  'ubuntu-image (extra-assertions). Note: seeded '
                  'system-user assertions must use an SSH key (no password) '
                  'and the model must be grade: dangerous.'),
              _Step(num: 4, text: 'Verify on the device with '
                  '"snap known system-user".'),
            ],
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int num;
  final String text;
  const _Step({required this.num, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Text('$num',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  final VerificationReport report;
  const _ReportView({required this.report});

  @override
  Widget build(BuildContext context) {
    return YaruSection(
      headline: Row(
        children: [
          const Text('Verification'),
          const SizedBox(width: 12),
          report.allPassed
              ? Chip(
                  label: const Text('All passed'),
                  backgroundColor:
                      StatusColors.success.withValues(alpha: 0.15),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                )
              : Chip(
                  label: const Text('Problems found'),
                  backgroundColor: StatusColors.error.withValues(alpha: 0.12),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
        ],
      ),
      child: Column(
        children: [
          for (final c in report.checks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (c.status) {
                      CheckStatus.pass => YaruIcons.ok,
                      CheckStatus.warn => YaruIcons.information,
                      CheckStatus.fail => YaruIcons.error,
                    },
                    size: 18,
                    color: switch (c.status) {
                      CheckStatus.pass => StatusColors.success,
                      CheckStatus.warn => StatusColors.orange,
                      CheckStatus.fail => StatusColors.error,
                    },
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 110,
                    child: Text(c.label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            )),
                  ),
                  Expanded(
                    child: SelectableText(
                      c.detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily:
                                c.detail.length > 40 ? 'monospace' : null,
                          ),
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

class _PreviewPane extends StatelessWidget {
  final String tab;
  final ValueChanged<String> onTabChanged;
  final bool visible;
  final VoidCallback onToggle;
  final String json;
  final String? chain;

  const _PreviewPane({
    required this.tab,
    required this.onTabChanged,
    required this.visible,
    required this.onToggle,
    required this.json,
    required this.chain,
  });

  @override
  Widget build(BuildContext context) {
    final content = tab == 'chain' ? (chain ?? '') : json;
    return YaruSection(
      headline: Row(
        children: [
          const Text('Preview'),
          const SizedBox(width: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'json', label: Text('JSON header (unsigned)')),
              ButtonSegment(
                  value: 'chain',
                  label: Text('Signed chain'),
                  icon: Icon(YaruIcons.key_filled, size: 16)),
            ],
            selected: {tab},
            onSelectionChanged: (s) => onTabChanged(s.first),
          ),
          const Spacer(),
          TextButton.icon(
            icon: Icon(visible ? Icons.arrow_drop_down : Icons.arrow_forward,
                size: 18),
            label: Text(visible ? 'Hide' : 'Show'),
            onPressed: onToggle,
          ),
        ],
      ),
      child: visible
          ? SizedBox(
              height: chain != null && tab == 'chain' ? 260 : 220,
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: SelectableText(
                    content.isEmpty ? '(not signed yet)' : content,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../models/wizard_state.dart';
import '../services/import_service.dart';
import '../services/password_hasher.dart';
import '../services/status_bar_service.dart';
import '../widgets/form_fields.dart';
import '../widgets/tag_chip_field.dart';

/// Step 1 — the user identity and how they authenticate.
///
/// Defaults to the simplest valid (SSO-style) shape: an SSH-key login with
/// no password. A password can be added optionally.
class UserPage extends StatefulWidget {
  final WizardState state;
  const UserPage({super.key, required this.state});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  final _username = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _passwordHashController = TextEditingController();

  bool _usingHash = false;
  String? _mismatch;
  String? _passwordError;

  /// The model generation this view was seeded from. An import swaps the
  /// whole model under us (a new [WizardState.modelGeneration]), and the
  /// local controllers — and the TagChipField's draft — cannot be reached by
  /// a plain refresh, so the page is rebuilt from the new model.
  int _seededGeneration = -1;

  @override
  void initState() {
    super.initState();
    _seededGeneration = widget.state.modelGeneration;
    _seedControllers();
    // Self-sufficient: react to a model swap even without the home page
    // rebuilding us. A plain refresh() is a no-op for this page — only a
    // generation change re-seeds anything.
    widget.state.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (!mounted) return;
    _rescheduleIfStale();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rescheduleIfStale();
  }

  @override
  void didUpdateWidget(covariant UserPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The home page rebuilds this page on every WizardState change; an
    // import is the one change that invalidates the local controllers.
    _rescheduleIfStale();
  }

  /// An import swaps the whole model under this page (a new
  /// [WizardState.modelGeneration]). The local controllers and the
  /// TagChipField's draft cannot be reached by a plain refresh, so re-seed
  /// the controllers and give the page subtree a new identity — which drops
  /// the SSH-keys TagChipField so its draft starts empty too.
  void _rescheduleIfStale() {
    final generation = widget.state.modelGeneration;
    if (generation == _seededGeneration) return;
    setState(() {
      _seededGeneration = generation;
      _seedControllers();
    });
  }

  /// (Re)seeds every local controller from the model. Only called from
  /// event handlers / rebuilds — never from build().
  void _seedControllers() {
    final u = widget.state.model;
    _username.text = u.username;
    _name.text = u.name;
    _email.text = u.email;
    _usingHash = u.hasPassword;
    if (u.passwordHash != null) {
      _passwordHashController.text = u.passwordHash!;
    } else {
      _passwordHashController.clear();
    }
    _password.clear();
    _confirm.clear();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _username.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _passwordHashController.dispose();
    super.dispose();
  }

  void _commitIdentity() {
    final u = widget.state.model;
    u
      ..username = _username.text.trim()
      ..name = _name.text.trim()
      ..email = _email.text.trim();
    if (_usingHash) {
      final h = _passwordHashController.text.trim();
      u.passwordHash = h.isEmpty ? null : h;
    } else {
      u.passwordHash = null;
    }
    widget.state.refresh();
  }

  void _hashPassword() {
    final pw = _password.text;
    if (pw.isEmpty) {
      setState(() {
        _passwordError = 'Enter a password to hash.';
        _mismatch = null;
      });
      return;
    }
    if (pw != _confirm.text) {
      setState(() {
        _mismatch = 'Passwords do not match.';
        _passwordError = null;
      });
      return;
    }
    final hash = PasswordHasher.sha512Crypt(pw);
    _passwordHashController.text = hash;
    _password.clear();
    _confirm.clear();
    setState(() {
      _mismatch = null;
      _passwordError = null;
      _usingHash = true;
    });
    _commitIdentity();
  }

  void _toggleAuthMode() {
    setState(() {
      _usingHash = !_usingHash;
      _passwordError = null;
      _mismatch = null;
    });
    _commitIdentity();
  }

  void _clearPassword() {
    setState(() => _usingHash = false);
    _passwordHashController.clear();
    _commitIdentity();
  }

  static String? _sshKeyError(String v) {
    if (RegExp(r'^(ssh-|ecdsa-|sk-|gpg-)[\w-]+ \S+').hasMatch(v)) return null;
    if (RegExp(r'^[A-Za-z0-9+/]{16,}={0,2} \S+').hasMatch(v)) return null;
    return 'That does not look like an OpenSSH public key line '
        '(type, base64 blob, then a comment).';
  }

  /// Loads an existing assertion (or its JSON header) into the editor so it
  /// can be reviewed and re-signed. This replaces the whole model, so it is
  /// offered on the first step — before any of the later fields have been
  /// filled in — rather than buried on the Export step.
  Future<void> _importExisting() async {
    try {
      final picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Assertion / JSON',
            extensions: ['assert', 'json', 'txt'],
          ),
        ],
      );
      if (picked == null) return;
      final path = picked.path;
      final text = await File(path).readAsString();
      final imported = ImportService().import(text);
      widget.state.replaceModel(imported.user);
      StatusBarService.instance.success('Imported $path');
    } on ImportException catch (e) {
      StatusBarService.instance.error(e.message);
    } on Exception catch (e) {
      StatusBarService.instance.error('Could not read file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.state.model;

    return ListView(
      key: ValueKey(_seededGeneration),
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('User',
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
          'Who is this assertion for, and how do they log in?',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        YaruSection(
          headline: const Text('Identity'),
          child: Column(
            children: [
              // Two-column identity grid: username and full name share a row,
              // the email takes the left column of the same grid (half the
              // section width), keeping the fields aligned in a single column.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: FormTextField(
                      label: 'Username *',
                      controller: _username,
                      hint: 'e.g. admin',
                      helper:
                          'Lowercase letters, digits, ".", "_" and "-"; must start with a letter or digit.',
                      onSubmitted: (_) => _commitIdentity(),
                      onChanged: (_) => _commitIdentity(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FormTextField(
                      label: 'Full name',
                      controller: _name,
                      hint: 'e.g. Ada Lovelace',
                      onChanged: (_) => _commitIdentity(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: FormTextField(
                      label: 'E-mail *',
                      controller: _email,
                      hint: 'e.g. ada@example.com',
                      helper:
                          'Part of the assertion index — snapd uses it to track the user.',
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => _commitIdentity(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Spacer(),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        YaruSection(
          headline: const Text('SSH keys'),
          child: Column(
            children: [
              Text(
                'Public keys for passwordless (SSO-style) login. Add at least '
                'one unless a password is set.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              TagChipField(
                label: 'Public keys',
                values: u.sshKeys,
                onChanged: (v) {
                  u.sshKeys
                    ..clear()
                    ..addAll(v);
                  widget.state.refresh();
                },
                hint: 'ssh-ed25519 AAAAC3NzaC1l… user@host',
                multiline: true,
                validateEntry: _sshKeyError,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildAuthSection(context),
      ],
    );
  }

  Widget _buildAuthSection(BuildContext context) {
    final u = widget.state.model;
    final showPasswordFields = !_usingHash;
    return YaruSection(
      headline: Row(
        children: [
          const Text('Authentication'),
          const Spacer(),
          OutlinedButton.icon(
            icon: Icon(_usingHash ? YaruIcons.key : YaruIcons.key_filled),
            label: Text(_usingHash ? 'Enter a password…' : 'Use password hash'),
            onPressed: _toggleAuthMode,
          ),
        ],
      ),
      child: showPasswordFields
          ? Column(
              children: [
                Text(
                  'Generate a crypt(3)-compatible sha512crypt hash. The '
                  'plaintext is hashed locally and never stored — only the '
                  'hash is placed in the assertion.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: FormTextField(
                        label: 'Password',
                        controller: _password,
                        obscure: true,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FormTextField(
                        label: 'Confirm password',
                        controller: _confirm,
                        obscure: true,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Push the button down by exactly one field-label height +
                    // gap so its top edge lines up with the two input boxes
                    // (the FormTextField renders a label above the field), and
                    // pin it to the input box height so its bottom edge is
                    // flush too (a default ElevatedButton is ~2px taller).
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(' ',
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 120,
                          height: 35,
                          child: ElevatedButton.icon(
                            icon: const Icon(YaruIcons.shield),
                            label: const Text('Hash it'),
                            onPressed: _hashPassword,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (_passwordError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_passwordError!,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.error)),
                  ),
                if (_mismatch != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_mismatch!,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 16),
                Text('Or paste a pre-computed hash:',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                FormTextField(
                  label: 'Hash (\$6\$salt\$hash)',
                  controller: _passwordHashController,
                  hint: r'$6$…',
                  helper: 'From mkpasswd -m sha512crypt, or generated above.',
                  onChanged: (_) => _commitIdentity(),
                ),
              ],
            )
          : Column(
              children: [
                FormTextField(
                  label: 'Password hash',
                  controller: _passwordHashController,
                  hint: r'$6$salt$hash',
                  helper:
                      'A crypt(3)-compatible sha512crypt hash, e.g. from mkpasswd -m sha512crypt.',
                  onChanged: (_) => _commitIdentity(),
                ),
                if (_usingHash) ...[
                  const SizedBox(height: 16),
                  YaruCheckboxListTile(
                    title: const Text('Force password change on first login'),
                    subtitle: const Text(
                        'The user must set a new password after the first '
                        'login; the new password cannot be empty.'),
                    value: u.forcePasswordChange,
                    onChanged: (v) {
                      u.forcePasswordChange = v ?? false;
                      widget.state.refresh();
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(YaruIcons.trash, size: 18),
                      label: const Text('Remove password (SSH-only login)'),
                      onPressed: _clearPassword,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

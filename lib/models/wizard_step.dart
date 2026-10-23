import 'package:flutter/material.dart';

/// The five stages of the assertion workflow.
enum WizardStep { user, device, timing, sign, export }

extension WizardStepInfo on WizardStep {
  String get label => switch (this) {
        WizardStep.user => 'User',
        WizardStep.device => 'Device',
        WizardStep.timing => 'Timing',
        WizardStep.sign => 'Signing Key',
        WizardStep.export => 'Export',
      };

  IconData get icon => switch (this) {
        WizardStep.user => Icons.person_outline,
        WizardStep.device => Icons.memory_outlined,
        WizardStep.timing => Icons.schedule_outlined,
        WizardStep.sign => Icons.vpn_key_outlined,
        WizardStep.export => Icons.verified_outlined,
      };

  IconData get selectedIcon => switch (this) {
        WizardStep.user => Icons.person,
        WizardStep.device => Icons.memory,
        WizardStep.timing => Icons.schedule,
        WizardStep.sign => Icons.vpn_key,
        WizardStep.export => Icons.verified,
      };

  String get description => switch (this) {
        WizardStep.user =>
          'Name, e-mail, and how the user authenticates — SSH keys by default, '
              'optionally a password.',
        WizardStep.device =>
          'Which brand and model (or models) may accept this assertion.',
        WizardStep.timing =>
          'When the assertion is valid, and whether the user is removed at '
              'expiration.',
        WizardStep.sign => 'Choose the brand key that signs the assertion.',
        WizardStep.export => 'Review, sign, and save auto-import.assert.',
      };
}

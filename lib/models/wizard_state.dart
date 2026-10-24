import 'package:flutter/foundation.dart';

import 'system_user_model.dart';
import 'wizard_step.dart';
import '../services/assertion_builder.dart';
import '../services/assertion_verifier.dart';

/// Shared wizard state: the assertion being edited, navigation gating,
/// busy state, and the signing key + result.
class WizardState extends ChangeNotifier {
  final SystemUser model = SystemUser.defaults();

  /// Bumped every time [replaceModel] swaps in a different model (e.g. an
  /// import). Step pages watch it to re-seed their [TextEditingController]s
  /// from the new model — the controllers are local state that [refresh]
  /// alone cannot reach.
  int modelGeneration = 0;

  /// The wizard steps the user has actually been to. The rail checkmark is
  /// gated on this in addition to validity, so a step that is *valid by
  /// default* — like Timing, which ships with a 30-day window — does not
  /// wear a green check before the user has visited it (or a following
  /// page). Purely cosmetic; navigation gating is unaffected.
  final Set<WizardStep> _visited = {WizardStep.user};

  String? selectedKeyName;
  SignOutput? signOutput;

  String? busyMessage;
  bool _busy = false;
  bool get busy => _busy;
  set busy(bool value) {
    _busy = value;
    if (!value) busyMessage = null;
    notifyListeners();
  }

  void refresh() => notifyListeners();

  List<String> errorsFor(WizardStep step) => switch (step) {
        WizardStep.user => AssertionValidation.userErrors(model),
        WizardStep.device => AssertionValidation.deviceErrors(model),
        WizardStep.timing => AssertionValidation.timingErrors(model),
        // Signing itself happens on the Export step; here only the key
        // must be chosen. (Requiring a signature here would deadlock: the
        // signature only exists once Export is reachable.)
        WizardStep.sign =>
          selectedKeyName == null
              ? const ['Choose a signing key. (If none exist, run '
                    '"snap create-key <name>" in a terminal, then press '
                    '"Refresh keys".)']
              : const [],
        WizardStep.export => signOutput?.report.allPassed ?? false
            ? const []
            : ['Sign the assertion first.'],
      };

  bool isStepComplete(WizardStep step) =>
      errorsFor(step).isEmpty;

  bool isStepEnabled(WizardStep step) {
    for (var i = 0; i < step.index; i++) {
      if (!isStepComplete(WizardStep.values[i])) return false;
    }
    return true;
  }

  /// Records navigation to [step]. Called by the shell whenever the current
  /// step changes (rail tap, Next, or Back).
  void markVisited(WizardStep step) {
    if (_visited.add(step)) {
      notifyListeners();
    }
  }

  /// Checkmark in the nav rail: the step is valid AND the user has visited
  /// that page or one of the following pages. This is what stops a
  /// default-valid step such as Timing from showing a check on startup.
  bool showStepComplete(WizardStep step) {
    if (!isStepComplete(step)) return false;
    return _visited.any((v) => v.index >= step.index);
  }

  /// Replaces the model (e.g. on import) and invalidates the signature.
  void replaceModel(SystemUser imported) {
    final u = model
      ..name = imported.name
      ..email = imported.email
      ..username = imported.username
      ..passwordHash = imported.passwordHash
      ..forcePasswordChange = imported.forcePasswordChange
      ..brandId = imported.brandId
      ..authorityId = imported.authorityId
      // Series stays fixed at '16' (see AssertionBuilder); imports never
      // override it, so a re-signed assertion always matches snapd's
      // only current series.
      ..since = imported.since
      ..until = imported.until
      ..userUntilExpiration = imported.userUntilExpiration;
    u.sshKeys
      ..clear()
      ..addAll(imported.sshKeys);
    u.models
      ..clear()
      ..addAll(imported.models);
    u.serials
      ..clear()
      ..addAll(imported.serials);
    signOutput = null;
    modelGeneration++;
    notifyListeners();
  }

  void setSignOutput(SignOutput? output) {
    signOutput = output;
    notifyListeners();
  }
}

/// Result of the Sign step: the chain + verification report + JSON header.
class SignOutput {
  final String signedChain;
  final String jsonHeader;
  final VerificationReport report;
  final DateTime signedAt;

  const SignOutput({
    required this.signedChain,
    required this.jsonHeader,
    required this.report,
    required this.signedAt,
  });
}

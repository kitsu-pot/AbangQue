import 'package:flutter/material.dart';

import '../presentation/widgets/glass.dart';
import '../theme.dart';
import 'auth_controller.dart';
import 'auth_validation.dart';

/// Passwords live only in this form and the existing authenticated API boundary.
class AccountSecurityDialog extends StatefulWidget {
  const AccountSecurityDialog({
    super.key,
    required this.controller,
    required this.deleting,
  });
  final AuthController controller;
  final bool deleting;
  @override
  State<AccountSecurityDialog> createState() => _AccountSecurityDialogState();
}

class _AccountSecurityDialogState extends State<AccountSecurityDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirmation = TextEditingController();
  final _hidden = [true, true, true];
  bool _confirmed = false;
  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = widget.controller;
    if (auth.busy ||
        auth.user == null ||
        (widget.deleting && !_confirmed) ||
        !_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    final done = widget.deleting
        ? await auth.deleteAccount(_current.text)
        : await auth.changePassword(
            _current.text,
            _next.text,
            _confirmation.text,
          );
    if (!mounted) return;
    _current.clear();
    _next.clear();
    _confirmation.clear();
    if (done) Navigator.pop(context, true);
  }

  Widget _password(int index, String label, TextEditingController field) =>
      TextFormField(
        key: ValueKey(
          [
            'account-current-password',
            'account-new-password',
            'account-confirm-password',
          ][index],
        ),
        controller: field,
        obscureText: _hidden[index],
        enabled: !widget.controller.busy && widget.controller.user != null,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: index == 2 || widget.deleting
            ? TextInputAction.done
            : TextInputAction.next,
        onFieldSubmitted: (_) {
          if (index == 2 || widget.deleting) _submit();
        },
        decoration: InputDecoration(
          labelText: label,
          errorMaxLines: 4,
          suffixIcon: IconButton(
            tooltip:
                '${_hidden[index] ? 'Show' : 'Hide'} ${label.toLowerCase()}',
            onPressed: () => setState(() => _hidden[index] = !_hidden[index]),
            icon: Icon(
              _hidden[index]
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
        ),
        validator: (value) {
          if (index == 0) {
            return value == null || value.isEmpty || value.length > 128
                ? 'Enter your current password.'
                : null;
          }
          if (index == 2) {
            return value != _next.text ? 'Passwords do not match.' : null;
          }
          return passwordError(value) ??
              (value == _current.text ? 'Choose a different password.' : null);
        },
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final auth = widget.controller;
      return PopScope(
        canPop: !auth.busy,
        child: Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          backgroundColor: JeepLinkColors.background,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      widget.deleting
                          ? Icons.delete_forever_outlined
                          : Icons.lock_reset_rounded,
                      size: 36,
                      color: widget.deleting
                          ? Theme.of(context).colorScheme.error
                          : JeepLinkColors.green,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.deleting
                          ? 'Delete your account?'
                          : 'Change password',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.deleting
                          ? 'This permanently deletes your passenger profile, password hash, Favorite Routes and all sign-in sessions from the active database. You cannot undo it. Public routes and jeepney reports are not deleted.'
                          : 'Use a different, unique passphrase of 15–128 characters. Other sessions will be signed out; this session keeps its original expiry.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'A server response is required. Account changes are never queued for later.',
                    ),
                    const SizedBox(height: 20),
                    _password(0, 'Current password', _current),
                    if (!widget.deleting) ...[
                      const SizedBox(height: 16),
                      _password(1, 'New password', _next),
                      const SizedBox(height: 16),
                      _password(2, 'Confirm new password', _confirmation),
                    ],
                    if (widget.deleting)
                      CheckboxListTile(
                        key: const ValueKey('confirm-account-deletion'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _confirmed,
                        onChanged: auth.busy
                            ? null
                            : (v) => setState(() => _confirmed = v ?? false),
                        title: const Text(
                          'I understand this permanently removes my account and favorites.',
                        ),
                      ),
                    if (auth.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            auth.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    if (auth.busy)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Confirming account change',
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const ValueKey('submit-account-change'),
                      style: widget.deleting
                          ? FilledButton.styleFrom(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .error,
                            )
                          : null,
                      onPressed:
                          auth.busy ||
                              auth.user == null ||
                              (widget.deleting && !_confirmed)
                          ? null
                          : _submit,
                      child: Text(
                        widget.deleting
                            ? 'Permanently delete account'
                            : 'Update password',
                      ),
                    ),
                    TextButton(
                      onPressed: auth.busy
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class PrivacyDataScreen extends StatelessWidget {
  const PrivacyDataScreen({super.key});
  @override
  Widget build(BuildContext context) => GlassBackdrop(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & Data'),
        toolbarHeight: MediaQuery.textScalerOf(context).scale(1) > 1.5
            ? 104
            : 64,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Your information, explained',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This describes the current app. It is not a formal privacy policy. Deployment-specific privacy notices and retention rules still need to be established.',
                  ),
                  const SizedBox(height: 20),
                  for (final section in const [
                    (
                      'Your passenger account',
                      'The backend stores your full name, normalized email, passenger role, account timestamps and an Argon2id password hash. It stores session-token hashes, expiry and revocation records. Your password is sent to the account service for authentication; it is not saved as plaintext. The device keeps sign-in credentials in secure storage, separate from public data. Production account traffic requires HTTPS.',
                    ),
                    (
                      'Favorite Routes',
                      'Favorites link registered route IDs and direction labels to your passenger account. Loaded favorites and profile information stay in memory for that account; they are cleared on sign-out, expiry or account change. Guests do not have saved favorites. Account changes need backend confirmation and are never queued offline.',
                    ),
                    (
                      'Your waiting location',
                      'Find Jeepneys checks foreground location permission and may request one reading. You can also choose a point manually. The app keeps the waiting point only in memory, clears it on account change or restart, and has no API upload for that point. Acquisition stops after a reading, timeout, cancellation or backgrounding. A separate preference remembers whether a permission prompt was attempted; it contains no coordinates.',
                    ),
                    (
                      'Maps and permission',
                      'OpenStreetMap tile requests reveal the viewed map area and network information to the tile service, which may apply its own policies. Centering on your waiting point can therefore reveal its surrounding area. On Android, open Settings → Apps → AbangQue → Permissions → Location to allow, restrict or deny access. Menu wording may vary. Manual map selection remains available.',
                    ),
                    (
                      'Offline public information',
                      'The app may cache public route directions, assignments, jeepney identities, last reported coordinates, manual-status metadata, source labels and original timestamps. Snapshots expire after 24 hours and files have size limits; Android may remove them sooner. Cached markers are last known locations, never proof of current availability. Current cached status is UNKNOWN and ETA is unavailable. No passenger profile, favorite, credential or waiting point is included in this cache.',
                    ),
                    (
                      'Delete your account',
                      'From Profile, choose Delete account, read the permanent-deletion explanation, confirm it and enter your current password. A successful server transaction removes your account, password hash, sessions and favorites from the active database. Public routes and jeepney records remain. This app cannot guarantee deletion from external database backups or infrastructure logs; their retention must be defined before public deployment.',
                    ),
                    (
                      'Signing out',
                      'Sign out clears the current account from the app and revokes its server session when reachable. During a network failure, a secure pending-sign-out marker prevents that token from restoring your profile; reconnect to finish revocation. Public transport caches remain available to guests. Other sessions are revoked when you change your password or delete your account.',
                    ),
                  ]) ...[
                    GlassPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            section.$1,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Text(section.$2),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

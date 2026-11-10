import 'dart:async';

import 'package:flutter/material.dart';

import '../presentation/widgets/common.dart';
import '../presentation/widgets/glass.dart';
import '../theme.dart';
import 'auth_controller.dart';
import 'auth_validation.dart';
import 'account_management.dart';
export 'auth_validation.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.controller, required this.child});
  final AuthController controller;
  final Widget child;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.restore());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.controller.guest) {
      unawaited(widget.controller.restore());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => widget.controller.entered
        ? widget.child
        : AuthScreen(controller: widget.controller),
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.controller,
    this.initialRegister = false,
    this.returnToJourney = false,
  });
  final AuthController controller;
  final bool initialRegister, returnToJourney;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late bool _register = widget.initialRegister;
  bool _hidePassword = true;
  bool _hideConfirm = true;
  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.controller.busy ||
        !widget.controller.enabled ||
        !_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    await widget.controller.authenticate(
      email: _email.text,
      password: _password.text,
      name: _register ? _name.text : null,
    );
    if (mounted && widget.returnToJourney && widget.controller.user != null) {
      Navigator.pop(context);
    }
  }

  Widget _passwordField({bool confirm = false}) {
    final hidden = confirm ? _hideConfirm : _hidePassword;
    return TextFormField(
      key: ValueKey(confirm ? 'auth-confirm' : 'auth-password'),
      controller: confirm ? _confirm : _password,
      obscureText: hidden,
      enabled: !widget.controller.busy && widget.controller.enabled,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: [
        confirm || _register
            ? AutofillHints.newPassword
            : AutofillHints.password,
      ],
      textInputAction: _register && !confirm
          ? TextInputAction.next
          : TextInputAction.done,
      onFieldSubmitted: (_) {
        if (!_register || confirm) unawaited(_submit());
      },
      decoration: InputDecoration(
        labelText: confirm ? 'Confirm password' : 'Password',
        helperText: _register && !confirm
            ? '15–128 characters. A long, unique passphrase works well.'
            : null,
        helperMaxLines: 4,
        errorMaxLines: 4,
        suffixIcon: IconButton(
          tooltip:
              '${hidden ? 'Show' : 'Hide'} ${confirm ? 'confirm password' : 'password'}',
          onPressed: () => setState(() {
            if (confirm) {
              _hideConfirm = !hidden;
            } else {
              _hidePassword = !hidden;
            }
          }),
          icon: Icon(
            hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
      validator: (value) => confirm
          ? (value != _password.text ? 'Passwords do not match.' : null)
          : _register
          ? passwordError(value)
          : (value == null || value.isEmpty || value.length > 128
                ? 'Enter your password.'
                : null),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => _formContent(context),
  );

  Widget _formContent(BuildContext context) => GlassBackdrop(
    child: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SoftEntrance(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 18),
                    const Icon(
                      Icons.airport_shuttle_rounded,
                      size: 46,
                      color: JeepLinkColors.green,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'AbangQue',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your Marinduque journey starts here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: JeepLinkColors.muted),
                    ),
                    const SizedBox(height: 26),
                    GlassPanel(
                      child: AutofillGroup(
                        child: Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _register
                                    ? 'Create your account'
                                    : 'Welcome aboard',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'An account is optional. Transport information is available to everyone.',
                              ),
                              const SizedBox(height: 22),
                              if (!widget.controller.enabled) ...[
                                const Text(
                                  'Offline DEMO is guest-only. Sign in or register in the API-connected Android or desktop app.',
                                ),
                                const SizedBox(height: 18),
                              ],
                              if (widget.controller.error != null) ...[
                                _AuthError(widget.controller.error!),
                                const SizedBox(height: 14),
                                TextButton(
                                  onPressed: widget.controller.busy
                                      ? null
                                      : widget.controller.restore,
                                  child: const Text('Retry session recovery'),
                                ),
                              ],
                              if (_register) ...[
                                TextFormField(
                                  key: const ValueKey('auth-name'),
                                  controller: _name,
                                  enabled:
                                      !widget.controller.busy &&
                                      widget.controller.enabled,
                                  autofillHints: const [AutofillHints.name],
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  validator: nameError,
                                  decoration: const InputDecoration(
                                    labelText: 'Full name',
                                    errorMaxLines: 3,
                                  ),
                                ),
                                const SizedBox(height: 18),
                              ],
                              TextFormField(
                                key: const ValueKey('auth-email'),
                                controller: _email,
                                enabled:
                                    !widget.controller.busy &&
                                    widget.controller.enabled,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                autofillHints: const [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                                validator: emailError,
                                decoration: const InputDecoration(
                                  labelText: 'Email address',
                                  errorMaxLines: 3,
                                ),
                              ),
                              const SizedBox(height: 18),
                              _passwordField(),
                              if (_register) ...[
                                const SizedBox(height: 18),
                                _passwordField(confirm: true),
                              ],
                              const SizedBox(height: 22),
                              if (widget.controller.busy) ...[
                                const LinearProgressIndicator(
                                  semanticsLabel: 'Checking passenger account',
                                ),
                                const SizedBox(height: 16),
                              ],
                              PassengerButton(
                                onPressed:
                                    widget.controller.busy ||
                                        !widget.controller.enabled
                                    ? null
                                    : _submit,
                                icon: Icon(
                                  _register
                                      ? Icons.person_add_alt_rounded
                                      : Icons.login_rounded,
                                ),
                                label: Text(
                                  _register ? 'Create account' : 'Sign in',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: widget.controller.busy
                                    ? null
                                    : () {
                                        widget.controller.clearError();
                                        setState(() {
                                          _register = !_register;
                                          _password.clear();
                                          _confirm.clear();
                                          _hidePassword = _hideConfirm = true;
                                          _form.currentState?.reset();
                                        });
                                      },
                                child: Text(
                                  _register
                                      ? 'Already have an account? Sign in'
                                      : 'New to AbangQue? Register',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed:
                          widget.controller.busy && !widget.controller.restoring
                          ? null
                          : () {
                              widget.controller.continueAsGuest();
                              if (widget.returnToJourney) {
                                Navigator.pop(context);
                              }
                            },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Continue as Guest',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Choose municipalities and view available route information without an account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: JeepLinkColors.muted,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PassengerProfileScreen extends StatefulWidget {
  const PassengerProfileScreen({super.key, required this.controller});
  final AuthController controller;
  @override
  State<PassengerProfileScreen> createState() => _PassengerProfileScreenState();
}

class _PassengerProfileScreenState extends State<PassengerProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  String? _nameAccount, _savedName, _notice;
  @override
  void initState() {
    super.initState();
    _syncName();
    widget.controller.addListener(_syncName);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.user != null) {
        unawaited(widget.controller.restore());
      }
    });
  }

  void _syncName() {
    final user = widget.controller.user;
    if (_nameAccount != user?.id || _name.text == (_savedName ?? '')) {
      _name.text = user?.fullName ?? '';
    }
    if (_nameAccount != user?.id) _notice = null;
    _nameAccount = user?.id;
    _savedName = user?.fullName;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncName);
    _name.dispose();
    super.dispose();
  }

  Future<void> _signIn(bool register) async {
    widget.controller.clearError();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AuthScreen(
          controller: widget.controller,
          initialRegister: register,
          returnToJourney: true,
        ),
      ),
    );
  }

  Future<void> _security(bool deleting) async {
    setState(() => _notice = null);
    widget.controller.clearError();
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AccountSecurityDialog(
        controller: widget.controller,
        deleting: deleting,
      ),
    );
    if (!mounted || done != true) return;
    setState(
      () => _notice = deleting
          ? 'Your account and saved favorites have been deleted. You can continue as a guest.'
          : 'Password changed. Other sessions have been signed out.',
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) =>
      GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: JeepLinkColors.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final auth = widget.controller;
      final user = auth.user;
      return GlassBackdrop(
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: MediaQuery.textScalerOf(context).scale(1) > 1.5
                ? 104
                : 64,
            title: const Text('Your profile'),
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
                      if (auth.error != null) ...[
                        _AuthError(auth.error!),
                        TextButton(
                          onPressed: auth.busy ? null : auth.restore,
                          child: const Text('Retry account check'),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (auth.busy)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(
                            semanticsLabel: 'Updating account',
                          ),
                        ),
                      if (_notice != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(_notice!),
                          ),
                        ),
                      if (user == null)
                        _section(
                          'Travelling as a guest',
                          Icons.account_circle_outlined,
                          [
                            const Text(
                              'Route selection and transport information do not require an account. Favorites require sign-in.',
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: auth.busy || !auth.enabled
                                  ? null
                                  : () => _signIn(false),
                              child: const Text('Log In'),
                            ),
                            OutlinedButton(
                              onPressed: auth.busy || !auth.enabled
                                  ? null
                                  : () => _signIn(true),
                              child: const Text('Create Account'),
                            ),
                            if (!auth.enabled)
                              const Text(
                                'Accounts are available in API mode. This mode remains guest-only.',
                              ),
                          ],
                        )
                      else ...[
                        _section(
                          'Account information',
                          Icons.person_outline_rounded,
                          [
                            Text(
                              user.fullName,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(user.email),
                            const SizedBox(height: 8),
                            const Text(
                              'Registered email · Read-only. Email changes and password reset are not available yet.',
                              style: TextStyle(
                                fontSize: 12,
                                color: JeepLinkColors.muted,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Form(
                              key: _form,
                              child: TextFormField(
                                key: const ValueKey('profile-name'),
                                controller: _name,
                                enabled: !auth.busy,
                                validator: nameError,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  labelText: 'Full name',
                                  errorMaxLines: 3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            PassengerButton(
                              onPressed: auth.busy
                                  ? null
                                  : () async {
                                      if (!_form.currentState!.validate()) {
                                        return;
                                      }
                                      FocusScope.of(context).unfocus();
                                      setState(() => _notice = null);
                                      final saved = await auth.updateName(
                                        _name.text,
                                      );
                                      if (mounted && saved) {
                                        setState(
                                          () => _notice = 'Profile updated.',
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Save profile'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _section('Security', Icons.lock_outline_rounded, [
                          const Text(
                            'Use your current password to set a new passphrase. Other sessions will be signed out.',
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: auth.busy
                                ? null
                                : () => _security(false),
                            child: const Text('Change password'),
                          ),
                        ]),
                      ],
                      const SizedBox(height: 16),
                      _section('Privacy', Icons.shield_outlined, [
                        const Text(
                          'Understand your account, location permission and offline information.',
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const PrivacyDataScreen(),
                            ),
                          ),
                          child: const Text('Privacy & Data'),
                        ),
                      ]),
                      if (user != null) ...[
                        const SizedBox(height: 16),
                        _section(
                          'Account actions',
                          Icons.manage_accounts_outlined,
                          [
                            OutlinedButton(
                              onPressed: auth.busy
                                  ? null
                                  : () async {
                                      await auth.logout();
                                      if (context.mounted &&
                                          auth.user == null &&
                                          auth.error == null) {
                                        Navigator.pop(context);
                                      }
                                    },
                              child: const Text('Sign out'),
                            ),
                            const SizedBox(height: 20),
                            const Divider(),
                            const SizedBox(height: 12),
                            const Text(
                              'Permanently remove your account and Favorite Routes. Public routes and jeepney reports remain available.',
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              key: const ValueKey('delete-account'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Theme.of(context)
                                    .colorScheme
                                    .error,
                              ),
                              onPressed: auth.busy
                                  ? null
                                  : () => _security(true),
                              child: const Text('Delete account'),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _AuthError extends StatelessWidget {
  const _AuthError(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JeepLinkColors.paleAmber,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(message, style: const TextStyle(color: JeepLinkColors.amber)),
    ),
  );
}

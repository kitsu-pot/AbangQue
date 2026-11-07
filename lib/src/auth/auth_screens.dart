import 'dart:async';

import 'package:flutter/material.dart';

import '../presentation/widgets/common.dart';
import '../presentation/widgets/glass.dart';
import '../theme.dart';
import 'auth_controller.dart';

String? nameError(String? value) {
  final name = value?.trim() ?? '';
  return name.isEmpty ||
          name.length > 120 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)
      ? 'Enter your full name (up to 120 characters).'
      : null;
}

String? emailError(String? value) =>
    value == null ||
        value.trim().length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
    ? 'Enter a valid email address.'
    : null;
String? passwordError(String? value) {
  final password = value ?? '';
  if (password.length < 15 ||
      password.length > 128 ||
      password.trim().isEmpty ||
      RegExp(r'^(.)\1+$').hasMatch(password) ||
      [
        'passwordpassword',
        '123456789012345',
        '12345678901234567890',
      ].contains(password.toLowerCase())) {
    return 'Use 15–128 characters. Choose a long, unique passphrase.';
  }
  return null;
}

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
  late final _name = TextEditingController(
    text: widget.controller.user?.fullName ?? '',
  );
  String? _notice;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.user != null) {
        unawaited(widget.controller.restore());
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

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
                  child: GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.account_circle_outlined,
                          size: 54,
                          color: JeepLinkColors.green,
                        ),
                        const SizedBox(height: 18),
                        if (auth.error != null) ...[
                          _AuthError(auth.error!),
                          const SizedBox(height: 14),
                        ],
                        if (auth.busy)
                          const LinearProgressIndicator(
                            semanticsLabel: 'Updating account',
                          ),
                        if (user == null) ...[
                          Text(
                            'Travelling as a guest',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Route selection and transport information do not require an account.',
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: auth.busy
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    auth.openSignIn();
                                  },
                            child: const Text('Sign in or register'),
                          ),
                        ] else ...[
                          const DemoBadge(label: 'PASSENGER'),
                          const SizedBox(height: 18),
                          Text(
                            user.email,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Email is your sign-in address. Email changes and password reset are not available yet.',
                            style: TextStyle(
                              fontSize: 12,
                              color: JeepLinkColors.muted,
                            ),
                          ),
                          const SizedBox(height: 22),
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
                          const SizedBox(height: 20),
                          if (_notice != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(_notice!),
                            ),
                          PassengerButton(
                            onPressed: auth.busy
                                ? null
                                : () async {
                                    if (!_form.currentState!.validate()) return;
                                    FocusScope.of(context).unfocus();
                                    setState(() => _notice = null);
                                    await auth.updateName(_name.text);
                                    if (mounted && auth.error == null) {
                                      setState(
                                        () => _notice = 'Profile updated.',
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Save profile'),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: auth.busy
                                ? null
                                : () async {
                                    await auth.logout();
                                    if (context.mounted && auth.user == null) {
                                      Navigator.pop(context);
                                    }
                                  },
                            child: const Text('Sign out'),
                          ),
                        ],
                      ],
                    ),
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

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

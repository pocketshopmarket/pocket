/// Zambian mobile: prefixes 097, 096, 095, 077, 076, 075, 057 (after leading 0).
class PhoneFormat {
  PhoneFormat._();

  static const supportedPrefixes = [
    '097',
    '096',
    '095',
    '077',
    '076',
    '075',
    '057',
  ];

  /// Digits only.
  static String digitsOnly(String s) =>
      s.replaceAll(RegExp(r'\D'), '');

  /// Returns local 10-digit form starting with 0, or null if invalid shape.
  static String? toLocalTenDigits(String input) {
    final d = digitsOnly(input);
    if (d.isEmpty) return null;

    if (d.startsWith('260') && d.length >= 12) {
      final rest = d.substring(3);
      if (rest.length == 9) {
        return '0$rest';
      }
      return null;
    }
    if (d.length == 10 && d.startsWith('0')) {
      return d;
    }
    if (d.length == 9 && '957'.contains(d[0])) {
      return '0$d';
    }
    return null;
  }

  /// E.164 e.g. +260971234567
  static String? toE164(String input) {
    final local = toLocalTenDigits(input);
    if (local == null || local.length != 10) return null;
    final prefix = local.substring(0, 3);
    if (!supportedPrefixes.contains(prefix)) return null;
    return '+260${local.substring(1)}';
  }

  static String? validateZambiaMobile(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    final local = toLocalTenDigits(value);
    if (local == null || local.length != 10) {
      return 'Enter a valid Zambian mobile (e.g. 097xxxxxxx or +26097xxxxxxx).';
    }
    final prefix = local.substring(0, 3);
    if (!supportedPrefixes.contains(prefix)) {
      return 'Use a supported prefix: 097, 096, 095, 077, 076, 075, or 057.';
    }
    return null;
  }
}

import 'package:dio/dio.dart';

import 'api_service.dart';

class Bank {
  final String id;
  final String name;
  const Bank({required this.id, required this.name});

  factory Bank.fromJson(Map<String, dynamic> json) =>
      Bank(id: json['id']?.toString() ?? '', name: json['name']?.toString() ?? '');
}

/// A saved payout account. The number is always masked — the full number never
/// comes back from the server after it is saved.
class BankAccount {
  final int id;
  final String bankName;
  final String maskedNumber;
  final String accountName;
  final bool nameMatches;
  final bool isDefault;

  const BankAccount({
    required this.id,
    required this.bankName,
    required this.maskedNumber,
    required this.accountName,
    required this.nameMatches,
    required this.isDefault,
  });

  factory BankAccount.fromJson(Map<String, dynamic> json) => BankAccount(
        id: (json['id'] as num).toInt(),
        bankName: json['bank_name']?.toString() ?? '',
        maskedNumber: json['account_number_masked']?.toString() ?? '',
        accountName: json['account_name']?.toString() ?? '',
        // Older responses (e.g. the payout summary) don't carry this; assume fine.
        nameMatches: json['name_matches'] != false,
        isDefault: json['is_default'] == true,
      );
}

/// The holder name the bank reports for an account number, before saving.
class ResolvedBankAccount {
  final String accountName;
  final String bankName;
  const ResolvedBankAccount({required this.accountName, required this.bankName});
}

class BankAccountException implements Exception {
  final String message;
  const BankAccountException(this.message);

  @override
  String toString() => message;
}

class BankAccountService {
  final ApiService _api = ApiService();

  Future<List<Bank>> getBanks() async {
    try {
      final res = await _api.get('payments/banks/');
      return (res.data as List).map((b) => Bank.fromJson(Map<String, dynamic>.from(b as Map))).toList();
    } on DioException catch (e) {
      throw BankAccountException(_message(e, 'Could not load the list of banks. Please try again.'));
    }
  }

  Future<List<BankAccount>> getAccounts() async {
    try {
      final res = await _api.get('payments/bank-accounts/');
      return (res.data as List).map((a) => BankAccount.fromJson(Map<String, dynamic>.from(a as Map))).toList();
    } on DioException catch (e) {
      throw BankAccountException(_message(e, 'Could not load your bank accounts.'));
    }
  }

  Future<ResolvedBankAccount> resolve({required String bankId, required String accountNumber}) async {
    try {
      final res = await _api.post('payments/bank-accounts/resolve/', data: {
        'bank_id': bankId,
        'account_number': accountNumber,
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      return ResolvedBankAccount(
        accountName: data['account_name']?.toString() ?? '',
        bankName: data['bank_name']?.toString() ?? '',
      );
    } on DioException catch (e) {
      throw BankAccountException(_message(e, 'Could not check that account. Please try again.'));
    }
  }

  Future<BankAccount> save({required String bankId, required String accountNumber}) async {
    try {
      final res = await _api.post('payments/bank-accounts/', data: {
        'bank_id': bankId,
        'account_number': accountNumber,
      });
      return BankAccount.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw BankAccountException(_message(e, 'Could not save the bank account. Please try again.'));
    }
  }

  Future<void> makeDefault(int id) async {
    try {
      await _api.post('payments/bank-accounts/$id/default/');
    } on DioException catch (e) {
      throw BankAccountException(_message(e, 'Could not change the default account.'));
    }
  }

  Future<void> delete(int id) async {
    try {
      await _api.delete('payments/bank-accounts/$id/');
    } on DioException catch (e) {
      throw BankAccountException(_message(e, 'Could not remove the bank account.'));
    }
  }

  static String _message(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    return fallback;
  }
}

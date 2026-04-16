import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/phone_format.dart';
import 'api_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final ApiService _apiService = ApiService();
  SharedPreferences? _storage;
  bool _initialized = false;

  // Initialize storage
  Future<void> initialize() async {
    if (_initialized) return;
    _storage = await SharedPreferences.getInstance();
    _initialized = true;
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized || _storage == null) {
      await initialize();
    }
  }
  String? _formatPhoneOrNull(String phone) => PhoneFormat.toE164(phone);

  /// Fallback when [PhoneFormat.toE164] fails (should be rare if UI validates).
  String _formatPhone(String phone) {
    final e164 = PhoneFormat.toE164(phone);
    if (e164 != null) return e164;
    var d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('260')) {
      return '+${d}';
    }
    if (d.startsWith('0')) {
      d = d.substring(1);
    }
    return '+260$d';
  }

  String _extractErrorMessage(DioException e, String defaultMessage) {
    if (e.response?.data is Map) {
      final data = e.response?.data as Map;
      if (data.containsKey('message')) {
        return data['message'].toString();
      }
      if (data.containsKey('errors') && data['errors'] is Map) {
        final errs = data['errors'] as Map;
        for (final v in errs.values) {
          if (v is List && v.isNotEmpty) {
            return v.first.toString();
          }
          if (v is String && v.isNotEmpty) {
            return v;
          }
        }
      }
      if (data.containsKey('non_field_errors') &&
          data['non_field_errors'] is List &&
          (data['non_field_errors'] as List).isNotEmpty) {
        return (data['non_field_errors'] as List).first.toString();
      }
      if (data.isNotEmpty) {
        final firstError = data.values.first;
        if (firstError is List && firstError.isNotEmpty) {
          return firstError[0].toString();
        }
        return firstError.toString();
      }
    }
    return defaultMessage;
  }

  // Send OTP
  Future<Map<String, dynamic>> sendOtp(String phoneNumber) async {
    final formattedPhone = _formatPhoneOrNull(phoneNumber) ?? _formatPhone(phoneNumber);
    await _ensureInitialized();
    try {
      final response = await _apiService.post(
        AppConstants.sendOtpEndpoint,
        data: {'phone_number': formattedPhone},
      );
      
      return {
        'success': true,
        'message': response.data['message'] ?? 'OTP sent successfully',
      };
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      if (status == 400 && body is Map && body['message'] != null) {
        return {
          'success': false,
          'message': body['message'].toString(),
          'errors': body['errors'],
        };
      }
      return {
        'success': false,
        'message': _extractErrorMessage(e, 'Failed to send OTP'),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An unexpected error occurred',
      };
    }
  }

  // Verify OTP
  Future<Map<String, dynamic>> verifyOtp(
    String phoneNumber, 
    String otp, {
    String? role,
    String? password,
    String? fullName,
    String? gender,
    String? dateOfBirth,
  }) async {
    final formattedPhone = _formatPhoneOrNull(phoneNumber) ?? _formatPhone(phoneNumber);
    await _ensureInitialized();
    final data = {
      'phone_number': formattedPhone,
      'otp_code': otp,
    };
    
    // Add optional fields for new user registration
    if (role != null) data['role'] = role;
    if (password != null) data['password'] = password;
    if (fullName != null) data['full_name'] = fullName;
    if (gender != null && gender.isNotEmpty) data['gender'] = gender;
    if (dateOfBirth != null && dateOfBirth.isNotEmpty) {
      data['date_of_birth'] = dateOfBirth;
    }

    try {
      final response = await _apiService.post(
        AppConstants.verifyOtpEndpoint,
        data: data,
      );

      final responseData = response.data;
      
      if (responseData['success'] == true) {
        // Save tokens
        await _apiService.saveTokens(
          responseData['data']['access_token'],
          responseData['data']['refresh_token'],
        );
        
        // Save user data
        await _storage?.setString(
          AppConstants.userKey,
          jsonEncode(responseData['data']['user']),
        );
        
        return {
          'success': true,
          'message': responseData['message'] ?? 'Account created successfully',
          'user': responseData['data']['user'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'OTP verification failed',
        };
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      if (status == 400 && body is Map && body['message'] != null) {
        return {
          'success': false,
          'message': body['message'].toString(),
          'errors': body['errors'],
        };
      }
      return {
        'success': false,
        'message': _extractErrorMessage(e, 'Failed to verify OTP'),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An unexpected error occurred',
      };
    }
  }
  
  // Login with Password
  Future<Map<String, dynamic>> login(String phoneNumber, String password) async {
    final formattedPhone = _formatPhoneOrNull(phoneNumber) ?? _formatPhone(phoneNumber);
    await _ensureInitialized();
    try {
      final response = await _apiService.post(
        '/auth/login/',
        data: {
          'phone_number': formattedPhone,
          'password': password,
        },
      );

      final data = response.data;
      if (data['success'] == true) {
        // Save tokens
        await _apiService.saveTokens(
          data['data']['access_token'],
          data['data']['refresh_token'],
        );
        
        // Save user data
        await _storage?.setString(
          AppConstants.userKey,
          jsonEncode(data['data']['user']),
        );
        
        return {
          'success': true,
          'message': data['message'] ?? 'Login successful',
          'user': data['data']['user'],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Login failed',
        };
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      if (status == 400 && data is Map && data['message'] != null) {
        return {
          'success': false,
          'message': data['message'].toString(),
          'errors': data['errors'],
        };
      }
      return {
        'success': false,
        'message': _extractErrorMessage(e, 'Failed to login'),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An unexpected error occurred',
      };
    }
  }

  Future<Map<String, dynamic>> sendPasswordResetOtp(String phoneNumber) async {
    final formattedPhone = _formatPhoneOrNull(phoneNumber) ?? _formatPhone(phoneNumber);
    await _ensureInitialized();
    try {
      final response = await _apiService.post(
        AppConstants.passwordResetSendOtpEndpoint,
        data: {'phone_number': formattedPhone},
      );
      return {
        'success': response.data['success'] == true,
        'message': response.data['message']?.toString() ??
            'If this number is registered, we sent a verification code.',
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _extractErrorMessage(e, 'Could not send reset code'),
      };
    } catch (e) {
      return {'success': false, 'message': 'An unexpected error occurred'};
    }
  }

  Future<Map<String, dynamic>> confirmPasswordReset({
    required String phoneNumber,
    required String otpCode,
    required String newPassword,
  }) async {
    final formattedPhone = _formatPhoneOrNull(phoneNumber) ?? _formatPhone(phoneNumber);
    await _ensureInitialized();
    try {
      final response = await _apiService.post(
        AppConstants.passwordResetConfirmEndpoint,
        data: {
          'phone_number': formattedPhone,
          'otp_code': otpCode,
          'new_password': newPassword,
        },
      );
      if (response.data['success'] == true) {
        return {
          'success': true,
          'message': response.data['message']?.toString() ??
              'Password updated. You can sign in.',
        };
      }
      return {
        'success': false,
        'message': response.data['message']?.toString() ?? 'Reset failed',
      };
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      if (status == 400 && data is Map && data['message'] != null) {
        return {
          'success': false,
          'message': data['message'].toString(),
          'errors': data['errors'],
        };
      }
      return {
        'success': false,
        'message': _extractErrorMessage(e, 'Could not reset password'),
      };
    } catch (e) {
      return {'success': false, 'message': 'An unexpected error occurred'};
    }
  }

  Future<Map<String, dynamic>> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _ensureInitialized();
    try {
      final response = await _apiService.post(
        AppConstants.changePasswordEndpoint,
        data: {
          'old_password': oldPassword,
          'new_password': newPassword,
        },
      );
      if (response.data['success'] == true) {
        return {
          'success': true,
          'message':
              response.data['message']?.toString() ?? 'Password changed.',
        };
      }
      return {
        'success': false,
        'message': response.data['message']?.toString() ?? 'Change failed',
      };
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      if (status == 400 && data is Map && data['message'] != null) {
        return {
          'success': false,
          'message': data['message'].toString(),
          'errors': data['errors'],
        };
      }
      return {
        'success': false,
        'message': _extractErrorMessage(e, 'Could not change password'),
      };
    } catch (e) {
      return {'success': false, 'message': 'An unexpected error occurred'};
    }
  }

  // Get current user
  Future<Map<String, dynamic>?> getCurrentUser() async {
    await _ensureInitialized();
    try {
      final response = await _apiService.get(AppConstants.profileEndpoint);
      return response.data['data'];
    } catch (e) {
      return null;
    }
  }

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    await _ensureInitialized();
    return await _apiService.hasValidToken();
  }

  // Logout
  Future<void> logout() async {
    await _ensureInitialized();
    final refresh = _storage?.getString(AppConstants.refreshTokenKey);
    if (refresh != null && refresh.isNotEmpty) {
      try {
        await _apiService.post(
          AppConstants.logoutEndpoint,
          data: {'refresh_token': refresh},
        );
      } catch (_) {
        // Access token may be expired; still clear local session.
      }
    }
    await _storage?.remove(AppConstants.accessTokenKey);
    await _storage?.remove(AppConstants.refreshTokenKey);
    await _storage?.remove(AppConstants.userKey);
  }

  // Get stored user data
  Future<Map<String, dynamic>?> getStoredUser() async {
    await _ensureInitialized();
    try {
      final userData = _storage?.getString(AppConstants.userKey);
      if (userData != null) {
        return jsonDecode(userData) as Map<String, dynamic>;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// Persist merged user map (including `seller_profile` / role profiles from GET profile).
  Future<void> saveStoredUserMap(Map<String, dynamic> userMap) async {
    await _ensureInitialized();
    await _storage?.setString(AppConstants.userKey, jsonEncode(userMap));
  }
}

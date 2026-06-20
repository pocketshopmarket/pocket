import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/phone_format.dart';
import 'api_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final ApiService _apiService = ApiService();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // No-op: kept so main.dart call site doesn't need to change.
  Future<void> initialize() async {}

  Future<void> _ensureInitialized() async {}
  String? _formatPhoneOrNull(String phone) => PhoneFormat.toE164(phone);

  /// Fallback when [PhoneFormat.toE164] fails (should be rare if UI validates).
  String _formatPhone(String phone) {
    final e164 = PhoneFormat.toE164(phone);
    if (e164 != null) return e164;
    var d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('260')) {
      return '+$d';
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
    // Network-level errors (no HTTP response received).
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown) {
      return "Can't connect to the server. Please check your internet connection and try again.";
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Request timed out. Please try again.';
    }
    final status = e.response?.statusCode;
    if (status == 401) {
      return 'Your session has expired. Please sign in again.';
    }
    if (status == 403) {
      return 'You do not have permission to perform this action.';
    }
    if (status == 404) {
      return 'We could not find what you requested.';
    }
    if (status == 429) {
      return 'Too many attempts. Please wait and try again.';
    }
    if (status != null && status >= 500) {
      return 'Something went wrong on our side. Please try again shortly.';
    }
    return defaultMessage;
  }

  String extractFriendlyMessage(
    Object error, {
    String defaultMessage = 'Something went wrong. Please try again.',
  }) {
    if (error is DioException) {
      return _extractErrorMessage(error, defaultMessage);
    }
    final raw = error.toString().replaceAll('Exception: ', '').trim();
    return raw.isEmpty ? defaultMessage : raw;
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
        await _storage.write(
          key: AppConstants.userKey,
          value: jsonEncode(responseData['data']['user']),
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
          'error_code': body['error_code']?.toString() ?? '',
          'errors': body['errors'],
        };
      }
      return {
        'success': false,
        'message': _extractErrorMessage(e, 'Failed to verify OTP'),
        'error_code': 'network_error',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An unexpected error occurred',
        'error_code': 'unknown',
      };
    }
  }
  
  // Login with Password
  Future<Map<String, dynamic>> login(String phoneNumber, String password) async {
    final formattedPhone = _formatPhoneOrNull(phoneNumber) ?? _formatPhone(phoneNumber);
    await _ensureInitialized();
    try {
      final response = await _apiService.post(
        AppConstants.loginEndpoint,
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
        await _storage.write(
          key: AppConstants.userKey,
          value: jsonEncode(data['data']['user']),
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

  Future<Map<String, dynamic>> submitSellerVerification({
    required String shopName,
    required String shopLocation,
    required String nrcNumber,
    required String nrcFrontPath,
    required String nrcBackPath,
    required String livePhotoPath,
    String tier = 'tier1',
    String? businessLicensePath,
    String? businessName,
    String? businessRegistrationNumber,
  }) async {
    await _ensureInitialized();
    try {
      final data = FormData.fromMap({
        'tier': tier,
        'shop_name': shopName,
        'shop_location': shopLocation,
        'nrc_number': nrcNumber,
        'nrc_front_image': await MultipartFile.fromFile(nrcFrontPath),
        'nrc_back_image': await MultipartFile.fromFile(nrcBackPath),
        'live_verification_photo': await MultipartFile.fromFile(livePhotoPath),
        if (businessLicensePath != null && businessLicensePath.isNotEmpty)
          'business_license': await MultipartFile.fromFile(businessLicensePath),
        if (businessName != null && businessName.trim().isNotEmpty)
          'business_name': businessName.trim(),
        if (businessRegistrationNumber != null &&
            businessRegistrationNumber.trim().isNotEmpty)
          'business_registration_number': businessRegistrationNumber.trim(),
      });
      final response = await _apiService.post(
        AppConstants.sellerApplyEndpoint,
        data: data,
      );
      return {
        'success': response.data['success'] == true,
        'message': response.data['message']?.toString() ??
            'Seller verification submitted.',
        'data': response.data['data'],
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _extractErrorMessage(e, 'Could not submit verification'),
      };
    } catch (e) {
      return {'success': false, 'message': 'An unexpected error occurred'};
    }
  }

  Future<Map<String, dynamic>> submitDeliveryVerification({
    required String vehicleType,
    required String licenseNumber,
    required String licenseFrontPath,
    required String licenseBackPath,
    required String province,
    required String town,
    required String area,
    required String livePhotoPath,
    String? profilePhotoPath,
  }) async {
    await _ensureInitialized();
    try {
      final data = FormData.fromMap({
        'vehicle_type': vehicleType,
        'license_number': licenseNumber,
        'license_front_image': await MultipartFile.fromFile(licenseFrontPath),
        'license_back_image': await MultipartFile.fromFile(licenseBackPath),
        'province': province,
        'town': town,
        'area': area,
        'live_verification_photo': await MultipartFile.fromFile(livePhotoPath),
        if (profilePhotoPath != null && profilePhotoPath.isNotEmpty)
          'profile_photo': await MultipartFile.fromFile(profilePhotoPath),
      });
      final response = await _apiService.post(
        AppConstants.deliveryApplyEndpoint,
        data: data,
      );
      return {
        'success': response.data['success'] == true,
        'message': response.data['message']?.toString() ??
            'Delivery verification submitted.',
        'data': response.data['data'],
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _extractErrorMessage(e, 'Could not submit verification'),
      };
    } catch (e) {
      return {'success': false, 'message': 'An unexpected error occurred'};
    }
  }

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    await _ensureInitialized();
    return await _apiService.hasValidToken();
  }

  // Logout
  Future<void> logout() async {
    final refresh = await _storage.read(key: AppConstants.refreshTokenKey);
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
    await _storage.delete(key: AppConstants.accessTokenKey);
    await _storage.delete(key: AppConstants.refreshTokenKey);
    await _storage.delete(key: AppConstants.userKey);
  }

  // Get stored user data
  Future<Map<String, dynamic>?> getStoredUser() async {
    try {
      final userData = await _storage.read(key: AppConstants.userKey);
      if (userData != null) {
        return jsonDecode(userData) as Map<String, dynamic>;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  Future<Map<String, dynamic>> updateProfile({
    String? fullName,
    String? defaultAddress,
  }) async {
    await _ensureInitialized();
    try {
      final body = <String, dynamic>{
        if (fullName != null) 'full_name': fullName.trim(),
        if (defaultAddress != null) 'default_address': defaultAddress.trim(),
      };
      final response = await _apiService.put(
        AppConstants.profileEndpoint,
        data: body,
      );
      final respBody = response.data;
      final rawData = respBody['data'];
      final userMap = rawData is Map
          ? Map<String, dynamic>.from(
              (rawData['user'] is Map ? rawData['user'] : rawData) as Map)
          : null;
      return {
        'success': respBody['success'] == true,
        'message': respBody['message']?.toString() ?? 'Profile updated.',
        ?'user': userMap,
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _extractErrorMessage(e, 'Could not update profile'),
      };
    } catch (_) {
      return {'success': false, 'message': 'An unexpected error occurred'};
    }
  }

  Future<Map<String, dynamic>> uploadProfilePhoto(String imagePath) async {
    await _ensureInitialized();
    try {
      final data = FormData.fromMap({
        'profile_photo': await MultipartFile.fromFile(imagePath),
      });
      final response = await _apiService.put(
        AppConstants.profileEndpoint,
        data: data,
      );
      final body = response.data;
      final rawData = body['data'];
      final userMap = rawData is Map
          ? Map<String, dynamic>.from(
              (rawData['user'] is Map ? rawData['user'] : rawData) as Map,
            )
          : null;
      return {
        'success': body['success'] == true,
        'message': body['message']?.toString() ?? 'Profile photo updated.',
        ?'user': userMap,
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _extractErrorMessage(e, 'Could not upload photo'),
      };
    } catch (e) {
      return {'success': false, 'message': 'An unexpected error occurred'};
    }
  }

  /// Persist merged user map (including `seller_profile` / role profiles from GET profile).
  Future<void> saveStoredUserMap(Map<String, dynamic> userMap) async {
    await _storage.write(
        key: AppConstants.userKey, value: jsonEncode(userMap));
  }
}

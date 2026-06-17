import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/constants/app_constants.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  late Dio _dio;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Emits when the session is force-cleared (refresh token expired / revoked).
  static final _sessionExpiredController = StreamController<void>.broadcast();
  static Stream<void> get onSessionExpired => _sessionExpiredController.stream;

  Future<void> initialize() async {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: Duration(milliseconds: AppConstants.connectTimeout),
      receiveTimeout: Duration(milliseconds: AppConstants.receiveTimeout),
      contentType: Headers.jsonContentType,
      headers: {
        'Accept': 'application/json',
      },
    ));
    if (kDebugMode) {
      debugPrint('[API] Base URL: ${_dio.options.baseUrl}');
    }

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (kDebugMode) {
            debugPrint('[API] ${options.method} ${options.uri}');
          }
          if (options.data is FormData) {
            options.contentType = null;
          }
          final token = await _storage.read(key: AppConstants.accessTokenKey);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (kDebugMode) {
            final response = error.response;
            debugPrint(
              '[API][ERROR] ${error.requestOptions.method} ${error.requestOptions.uri} '
              'status=${response?.statusCode} data=${response?.data}',
            );
          }
          final path = error.requestOptions.path;
          final isRefreshCall = path.endsWith(AppConstants.refreshEndpoint);

          if (error.response?.statusCode == 401 && !isRefreshCall) {
            try {
              final refreshToken =
                  await _storage.read(key: AppConstants.refreshTokenKey);
              if (refreshToken != null && refreshToken.isNotEmpty) {
                final response = await _dio.post(
                  AppConstants.refreshEndpoint,
                  data: {'refresh': refreshToken},
                );

                final data = response.data;
                final newAccess = data['access'] as String?;
                if (newAccess == null) {
                  await _clearTokens(expired: true);
                  handler.next(error);
                  return;
                }

                await _storage.write(
                    key: AppConstants.accessTokenKey, value: newAccess);

                final newRefresh = data['refresh'] as String?;
                if (newRefresh != null && newRefresh.isNotEmpty) {
                  await _storage.write(
                      key: AppConstants.refreshTokenKey, value: newRefresh);
                }

                final originalRequest = error.requestOptions;
                originalRequest.headers['Authorization'] = 'Bearer $newAccess';

                final retryResponse = await _dio.fetch(originalRequest);
                handler.resolve(retryResponse);
                return;
              }
            } catch (_) {
              await _clearTokens(expired: true);
            }
          }

          if (isRefreshCall && error.response?.statusCode == 401) {
            await _clearTokens(expired: true);
          }

          handler.next(error);
        },
      ),
    );
  }

  Dio get dio => _dio;

  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: AppConstants.accessTokenKey, value: accessToken);
    await _storage.write(
        key: AppConstants.refreshTokenKey, value: refreshToken);
  }

  Future<void> _clearTokens({bool expired = false}) async {
    await _storage.delete(key: AppConstants.accessTokenKey);
    await _storage.delete(key: AppConstants.refreshTokenKey);
    await _storage.delete(key: AppConstants.userKey);
    if (expired) _sessionExpiredController.add(null);
  }

  Future<String?> getAccessToken() async {
    return _storage.read(key: AppConstants.accessTokenKey);
  }

  Future<bool> hasValidToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return await _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return await _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return await _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return await _dio.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return await _dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }
}

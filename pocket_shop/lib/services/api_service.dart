import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  late Dio _dio;
  SharedPreferences? _storage;

  Future<void> initialize() async {
    _storage = await SharedPreferences.getInstance();
    
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: Duration(milliseconds: AppConstants.connectTimeout),
      receiveTimeout: Duration(milliseconds: AppConstants.receiveTimeout),
      contentType: Headers.jsonContentType,
      headers: {
        'Accept': 'application/json',
      },
    ));

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.data is FormData) {
            options.contentType = null;
          }
          final token = _storage?.getString(AppConstants.accessTokenKey);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final path = error.requestOptions.path;
          final isRefreshCall = path.endsWith(AppConstants.refreshEndpoint);

          if (error.response?.statusCode == 401 && !isRefreshCall) {
            try {
              final refreshToken = _storage?.getString(AppConstants.refreshTokenKey);
              if (refreshToken != null && refreshToken.isNotEmpty) {
                final response = await _dio.post(
                  AppConstants.refreshEndpoint,
                  data: {'refresh': refreshToken},
                );

                final data = response.data;
                final newAccess = data['access'] as String?;
                if (newAccess == null) {
                  await _clearTokens();
                  handler.next(error);
                  return;
                }

                await _storage?.setString(AppConstants.accessTokenKey, newAccess);

                final newRefresh = data['refresh'] as String?;
                if (newRefresh != null && newRefresh.isNotEmpty) {
                  await _storage?.setString(AppConstants.refreshTokenKey, newRefresh);
                }

                final originalRequest = error.requestOptions;
                originalRequest.headers['Authorization'] = 'Bearer $newAccess';

                final retryResponse = await _dio.fetch(originalRequest);
                handler.resolve(retryResponse);
                return;
              }
            } catch (_) {
              await _clearTokens();
            }
          }

          if (isRefreshCall && error.response?.statusCode == 401) {
            await _clearTokens();
          }

          handler.next(error);
        },
      ),
    );
  }

  Dio get dio => _dio;

  // Auth methods
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage?.setString(AppConstants.accessTokenKey, accessToken);
    await _storage?.setString(AppConstants.refreshTokenKey, refreshToken);
  }

  Future<void> _clearTokens() async {
    await _storage?.remove(AppConstants.accessTokenKey);
    await _storage?.remove(AppConstants.refreshTokenKey);
    await _storage?.remove(AppConstants.userKey);
  }

  Future<String?> getAccessToken() async {
    return _storage?.getString(AppConstants.accessTokenKey);
  }

  Future<bool> hasValidToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  // Generic API methods
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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

/// [getCurrentUser] returns `{ user, profile }`; stored session is flat `user`.
Map<String, dynamic> _sessionUserMapForModel(Map<String, dynamic> raw) {
  if (raw['user'] is Map) {
    final u = Map<String, dynamic>.from(raw['user'] as Map);
    final role = u['role']?.toString();
    final p = raw['profile'];
    if (p is Map) {
      final pm = Map<String, dynamic>.from(p);
      if (role == 'delivery' && u['delivery_profile'] == null) {
        u['delivery_profile'] = pm;
      } else if (role == 'buyer' && u['buyer_profile'] == null) {
        u['buyer_profile'] = pm;
      } else if (role == 'seller' && u['seller_profile'] == null) {
        u['seller_profile'] = pm;
      }
    }
    return u;
  }
  return Map<String, dynamic>.from(raw);
}

// Auth state
class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;
  final bool isAuthenticated;
  final bool isInitialized;

  AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.isAuthenticated = false,
    this.isInitialized = false,
  });

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? error,
    bool? isAuthenticated,
    bool? isInitialized,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

// Auth service provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

// Auth provider
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(AuthState());

  // Set authenticated user (for initialization)
  void setAuthenticatedUser(User user) {
    state = state.copyWith(
      user: user,
      isAuthenticated: true,
      isLoading: false,
      error: null,
      isInitialized: true,
    );
  }

  /// Fetches GET /auth/profile/ and updates [user] + local storage (seller approval, etc.).
  /// Returns the API `{ user, profile }` payload when successful.
  Future<Map<String, dynamic>?> refreshUser() async {
    try {
      final raw = await _authService.getCurrentUser();
      if (raw == null) return null;
      final userMap = _sessionUserMapForModel(raw);
      setAuthenticatedUser(User.fromJson(userMap));
      await _authService.saveStoredUserMap(userMap);
      return raw;
    } catch (_) {
      return null;
    }
  }

  // Clear auth state
  void clearAuth() {
    state = state.copyWith(
      user: null,
      isAuthenticated: false,
      isLoading: false,
      error: null,
      isInitialized: true,
    );
  }

  // Set error
  void setError(String error) {
    state = state.copyWith(
      error: error,
      isLoading: false,
      isInitialized: true,
    );
  }

  // Send OTP
  Future<void> sendOtp(String phoneNumber) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final result = await _authService.sendOtp(phoneNumber);
      
      if (result['success']) {
        state = state.copyWith(isLoading: false);
      } else {
        state = state.copyWith(
          error: result['message'],
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
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
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final result = await _authService.verifyOtp(
        phoneNumber, 
        otp, 
        role: role, 
        password: password, 
        fullName: fullName,
        gender: gender,
        dateOfBirth: dateOfBirth,
      );
      
      if (result['success']) {
        state = state.copyWith(
          user: User.fromJson(result['user']),
          isAuthenticated: true,
          isLoading: false,
          isInitialized: true,
        );
        await refreshUser();
      } else {
        state = state.copyWith(
          error: result['message'],
          isLoading: false,
        );
      }
      return result;
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
      return {'success': false, 'message': e.toString()};
    }
  }

  // Login
  Future<Map<String, dynamic>> login(String phoneNumber, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final result = await _authService.login(phoneNumber, password);
      
      if (result['success']) {
        state = state.copyWith(
          user: User.fromJson(result['user']),
          isAuthenticated: true,
          isLoading: false,
          isInitialized: true,
        );
        await refreshUser();
      } else {
        state = state.copyWith(
          error: result['message'],
          isLoading: false,
        );
      }
      return result;
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
      return {'success': false, 'message': e.toString()};
    }
  }

  // Logout
  Future<void> logout() async {
    state = state.copyWith(isLoading: true);

    try {
      await _authService.logout();
      clearAuth();
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
        isInitialized: true,
      );
    }
  }

  // Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Provider instances
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});

// Auth initialization future provider
final authInitializationProvider = FutureProvider<void>((ref) async {
  final authService = ref.watch(authServiceProvider);
  final authNotifier = ref.watch(authProvider.notifier);
  
    try {
      final isLoggedIn = await authService.isLoggedIn();
      if (isLoggedIn) {
        final raw = await authService.getCurrentUser() ??
            await authService.getStoredUser();
        if (raw != null) {
          final userMap = raw['user'] is Map
              ? _sessionUserMapForModel(raw)
              : Map<String, dynamic>.from(raw);
          authNotifier.setAuthenticatedUser(User.fromJson(userMap));
          if (raw['user'] is Map) {
            await authService.saveStoredUserMap(userMap);
          }
        } else {
          authNotifier.clearAuth();
        }
      } else {
        authNotifier.clearAuth();
      }
  } catch (e) {
    authNotifier.setError(e.toString());
  }
});

// Convenience providers
final userProvider = Provider<User?>((ref) {
  return ref.watch(authProvider).user;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

final authLoadingProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isLoading;
});

final authErrorProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).error;
});

class AppConstants {
  // API base — MUST end with "/" so Dio resolves relative paths under /api/.
  // Without trailing slash: "http://host/api" + "auth/login/" → "http://host/auth/login/" (WRONG)
  // With trailing slash:    "http://host/api/" + "auth/login/" → "http://host/api/auth/login/" (correct)
  static const String _rawBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://13.222.154.44/api/',
  );
  static String get baseUrl => _rawBaseUrl.endsWith('/') ? _rawBaseUrl : '$_rawBaseUrl/';
  static const String sendOtpEndpoint = 'auth/send-otp/';
  static const String verifyOtpEndpoint = 'auth/verify-otp/';
  static const String profileEndpoint = 'auth/profile/';
  static const String productsEndpoint = 'products/';
  static const String reviewsEndpoint = 'reviews/products/';
  static const String ordersCartEndpoint = 'orders/cart/';
  static const String ordersCreateEndpoint = 'orders/orders/create/';
  static const String ordersListEndpoint = 'orders/orders/';
  static const String sellerDashboardStatsEndpoint = 'orders/seller/dashboard-stats/';
  static const String deliveryTrackPrefix = 'delivery/track/';
  static const String deliveryAvailableEndpoint = 'delivery/orders/available/';
  static const String deliveryAcceptEndpoint = 'delivery/orders/accept/';
  static const String deliveryLocationEndpoint = 'delivery/location/update/';
  static const String deliveryAssignmentStatusPrefix = 'delivery/assignment/';
  static const String deliveryActiveAssignmentEndpoint =
      'delivery/assignments/active/';
  static const String deliveryZonesEndpoint = 'delivery/zones/';
  static const String deliveryQuoteEndpoint = 'delivery/quote/';
  static const String deliveryReverseGeocodeEndpoint = 'delivery/geocode/reverse/';
  static const String deliveryAddressSearchEndpoint = 'delivery/geocode/search/';
  static const String deliveryStatsEndpoint = 'delivery/stats/';
  static const String refreshEndpoint = 'auth/refresh/';
  static const String loginEndpoint = 'auth/login/';
  static const String logoutEndpoint = 'auth/logout/';
  static const String sellerApplyEndpoint = 'auth/seller-apply/';
  static const String deliveryApplyEndpoint = 'auth/delivery-apply/';
  static const String passwordResetSendOtpEndpoint = 'auth/password-reset/send-otp/';
  static const String passwordResetConfirmEndpoint = 'auth/password-reset/confirm/';
  static const String changePasswordEndpoint = 'auth/change-password/';
  static const String buyerPaymentMethodsEndpoint = 'auth/buyer/payment-methods/';

  // Storage Keys
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userKey = 'user';
  
  // App Info
  static const String appName = 'Pocket Shop';
  static const String appVersion = '1.0.0';
  
  // Backend uses a random OTP; check Django runserver logs in development.
  static const String testOtp = '123456';
  
  // User Roles
  static const String buyerRole = 'buyer';
  static const String sellerRole = 'seller';
  static const String deliveryRole = 'delivery';
  static const String adminRole = 'admin';
  
  // Timeouts
  static const int connectTimeout = 30000;
  static const int receiveTimeout = 30000;
  
}

class AppConstants {
  // API base (Django mounts apps under /api/...). No trailing slash required.
  // Paths below must NOT start with "/" — Dio uses Uri.resolve(); a leading "/"
  // would drop the "/api" segment and cause 404s on the server.
  // Local: flutter run (default). EC2 / CI: --dart-define=API_BASE_URL=http://HOST/api
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api',
  );
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

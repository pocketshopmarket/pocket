class User {
  final int id;
  final String phoneNumber;
  final String? email;
  final String? gender;
  final String? dateOfBirth;
  final String role;
  final bool isVerified;
  final bool isPhoneVerified;
  final DateTime dateJoined;
  final String? firstName;
  final String? lastName;
  final BuyerProfile? buyerProfile;
  final SellerProfile? sellerProfile;
  final DeliveryProfile? deliveryProfile;

  User({
    required this.id,
    required this.phoneNumber,
    this.email,
    this.gender,
    this.dateOfBirth,
    required this.role,
    required this.isVerified,
    required this.isPhoneVerified,
    required this.dateJoined,
    this.firstName,
    this.lastName,
    this.buyerProfile,
    this.sellerProfile,
    this.deliveryProfile,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      phoneNumber: json['phone_number'],
      email: json['email'],
      gender: json['gender'] as String?,
      dateOfBirth: json['date_of_birth'] as String?,
      role: json['role'],
      isVerified: json['is_verified'] ?? false,
      isPhoneVerified: json['is_phone_verified'] ?? false,
      dateJoined: DateTime.parse(json['date_joined']),
      firstName: json['full_name'] ?? json['first_name'],
      lastName: json['last_name'],
      buyerProfile: json['buyer_profile'] != null 
          ? BuyerProfile.fromJson(json['buyer_profile']) 
          : null,
      sellerProfile: json['seller_profile'] != null 
          ? SellerProfile.fromJson(json['seller_profile']) 
          : null,
      deliveryProfile: json['delivery_profile'] != null 
          ? DeliveryProfile.fromJson(json['delivery_profile']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone_number': phoneNumber,
      'email': email,
      'gender': gender,
      'date_of_birth': dateOfBirth,
      'role': role,
      'is_verified': isVerified,
      'is_phone_verified': isPhoneVerified,
      'date_joined': dateJoined.toIso8601String(),
      'full_name': firstName,
      'first_name': firstName,
      'last_name': lastName,
      'buyer_profile': buyerProfile?.toJson(),
      'seller_profile': sellerProfile?.toJson(),
      'delivery_profile': deliveryProfile?.toJson(),
    };
  }

  User copyWith({
    int? id,
    String? phoneNumber,
    String? email,
    String? gender,
    String? dateOfBirth,
    String? role,
    bool? isVerified,
    bool? isPhoneVerified,
    DateTime? dateJoined,
    String? firstName,
    String? lastName,
    BuyerProfile? buyerProfile,
    SellerProfile? sellerProfile,
    DeliveryProfile? deliveryProfile,
  }) {
    return User(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      role: role ?? this.role,
      isVerified: isVerified ?? this.isVerified,
      isPhoneVerified: isPhoneVerified ?? this.isPhoneVerified,
      dateJoined: dateJoined ?? this.dateJoined,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      buyerProfile: buyerProfile ?? this.buyerProfile,
      sellerProfile: sellerProfile ?? this.sellerProfile,
      deliveryProfile: deliveryProfile ?? this.deliveryProfile,
    );
  }

  String get displayName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    } else if (firstName != null) {
      return firstName!;
    } else {
      return phoneNumber;
    }
  }

  bool get isBuyer => role == 'buyer';
  bool get isSeller => role == 'seller';
  bool get isDelivery => role == 'delivery';
  bool get isAdmin => role == 'admin';
}

class BuyerProfile {
  final String? defaultAddress;
  final String preferredPaymentMethod;

  BuyerProfile({
    this.defaultAddress,
    required this.preferredPaymentMethod,
  });

  factory BuyerProfile.fromJson(Map<String, dynamic> json) {
    return BuyerProfile(
      defaultAddress: json['default_address'],
      preferredPaymentMethod: json['preferred_payment_method'] ?? 'cash',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'default_address': defaultAddress,
      'preferred_payment_method': preferredPaymentMethod,
    };
  }
}

class SellerProfile {
  final String shopName;
  final String shopLocation;
  final String? businessLicense;
  final bool isApproved;
  final DateTime? approvalDate;

  SellerProfile({
    required this.shopName,
    required this.shopLocation,
    this.businessLicense,
    required this.isApproved,
    this.approvalDate,
  });

  factory SellerProfile.fromJson(Map<String, dynamic> json) {
    return SellerProfile(
      shopName: json['shop_name'],
      shopLocation: json['shop_location'],
      businessLicense: json['business_license'],
      isApproved: json['is_approved'] ?? false,
      approvalDate: json['approval_date'] != null 
          ? DateTime.parse(json['approval_date']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shop_name': shopName,
      'shop_location': shopLocation,
      'business_license': businessLicense,
      'is_approved': isApproved,
      'approval_date': approvalDate?.toIso8601String(),
    };
  }
}

class DeliveryProfile {
  final String vehicleType;
  final String licenseNumber;
  final bool isAvailable;
  final bool isApproved;
  final String? currentLocation;

  DeliveryProfile({
    required this.vehicleType,
    required this.licenseNumber,
    required this.isAvailable,
    required this.isApproved,
    this.currentLocation,
  });

  factory DeliveryProfile.fromJson(Map<String, dynamic> json) {
    return DeliveryProfile(
      vehicleType: json['vehicle_type'],
      licenseNumber: json['license_number'],
      isAvailable: json['is_available'] ?? true,
      isApproved: json['is_approved'] ?? false,
      currentLocation: json['current_location'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vehicle_type': vehicleType,
      'license_number': licenseNumber,
      'is_available': isAvailable,
      'is_approved': isApproved,
      'current_location': currentLocation,
    };
  }
}

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
  final String? profilePhoto;
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
    this.profilePhoto,
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
      profilePhoto: json['profile_photo'] as String?,
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
      'profile_photo': profilePhoto,
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
    String? profilePhoto,
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
      profilePhoto: profilePhoto ?? this.profilePhoto,
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
  final String? businessName;
  final String? businessRegistrationNumber;
  final String? nrcNumber;
  final String? nrcFrontImage;
  final String? nrcBackImage;
  final String? liveVerificationPhoto;
  final String tier1Status;
  final String tier2Status;
  final String? verificationRejectionReason;
  final bool isApproved;
  final DateTime? approvalDate;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  SellerProfile({
    required this.shopName,
    required this.shopLocation,
    this.businessLicense,
    this.businessName,
    this.businessRegistrationNumber,
    this.nrcNumber,
    this.nrcFrontImage,
    this.nrcBackImage,
    this.liveVerificationPhoto,
    this.tier1Status = 'not_started',
    this.tier2Status = 'not_started',
    this.verificationRejectionReason,
    required this.isApproved,
    this.approvalDate,
    this.submittedAt,
    this.reviewedAt,
  });

  factory SellerProfile.fromJson(Map<String, dynamic> json) {
    return SellerProfile(
      shopName: json['shop_name'],
      shopLocation: json['shop_location'],
      businessLicense: json['business_license'],
      businessName: json['business_name'],
      businessRegistrationNumber: json['business_registration_number'],
      nrcNumber: json['nrc_number'],
      nrcFrontImage: json['nrc_front_image'],
      nrcBackImage: json['nrc_back_image'],
      liveVerificationPhoto: json['live_verification_photo'],
      tier1Status: json['tier1_status'] ?? 'not_started',
      tier2Status: json['tier2_status'] ?? 'not_started',
      verificationRejectionReason: json['verification_rejection_reason'],
      isApproved: json['is_approved'] ?? false,
      approvalDate: json['approval_date'] != null
          ? DateTime.tryParse(json['approval_date'])
          : null,
      submittedAt: json['submitted_at'] != null
          ? DateTime.tryParse(json['submitted_at'])
          : null,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.tryParse(json['reviewed_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shop_name': shopName,
      'shop_location': shopLocation,
      'business_license': businessLicense,
      'business_name': businessName,
      'business_registration_number': businessRegistrationNumber,
      'nrc_number': nrcNumber,
      'nrc_front_image': nrcFrontImage,
      'nrc_back_image': nrcBackImage,
      'live_verification_photo': liveVerificationPhoto,
      'tier1_status': tier1Status,
      'tier2_status': tier2Status,
      'verification_rejection_reason': verificationRejectionReason,
      'is_approved': isApproved,
      'approval_date': approvalDate?.toIso8601String(),
      'submitted_at': submittedAt?.toIso8601String(),
      'reviewed_at': reviewedAt?.toIso8601String(),
    };
  }

  bool get canSell => isApproved || tier1Status == 'approved';
}

class DeliveryProfile {
  final String vehicleType;
  final String licenseNumber;
  final String? licenseFrontImage;
  final String? licenseBackImage;
  final String? province;
  final String? town;
  final String? area;
  final String? liveVerificationPhoto;
  final String? profilePhoto;
  final String verificationStatus;
  final String? verificationRejectionReason;
  final bool isAvailable;
  final bool isApproved;
  final String? currentLocation;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  DeliveryProfile({
    required this.vehicleType,
    required this.licenseNumber,
    this.licenseFrontImage,
    this.licenseBackImage,
    this.province,
    this.town,
    this.area,
    this.liveVerificationPhoto,
    this.profilePhoto,
    this.verificationStatus = 'not_started',
    this.verificationRejectionReason,
    required this.isAvailable,
    required this.isApproved,
    this.currentLocation,
    this.submittedAt,
    this.reviewedAt,
  });

  factory DeliveryProfile.fromJson(Map<String, dynamic> json) {
    return DeliveryProfile(
      vehicleType: json['vehicle_type'],
      licenseNumber: json['license_number'],
      licenseFrontImage: json['license_front_image'],
      licenseBackImage: json['license_back_image'],
      province: json['province'],
      town: json['town'],
      area: json['area'],
      liveVerificationPhoto: json['live_verification_photo'],
      profilePhoto: json['profile_photo'],
      verificationStatus: json['verification_status'] ?? 'not_started',
      verificationRejectionReason: json['verification_rejection_reason'],
      isAvailable: json['is_available'] ?? true,
      isApproved: json['is_approved'] ?? false,
      currentLocation: json['current_location'],
      submittedAt: json['submitted_at'] != null
          ? DateTime.tryParse(json['submitted_at'])
          : null,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.tryParse(json['reviewed_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vehicle_type': vehicleType,
      'license_number': licenseNumber,
      'license_front_image': licenseFrontImage,
      'license_back_image': licenseBackImage,
      'province': province,
      'town': town,
      'area': area,
      'live_verification_photo': liveVerificationPhoto,
      'profile_photo': profilePhoto,
      'verification_status': verificationStatus,
      'verification_rejection_reason': verificationRejectionReason,
      'is_available': isAvailable,
      'is_approved': isApproved,
      'current_location': currentLocation,
      'submitted_at': submittedAt?.toIso8601String(),
      'reviewed_at': reviewedAt?.toIso8601String(),
    };
  }
}

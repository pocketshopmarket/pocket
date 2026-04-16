from rest_framework import status, permissions
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from .models import (
    BuyerProfile,
    DeliveryProfile,
    PhoneOTP,
    SellerProfile,
    User,
)
from .serializers import (
    SendOTPSerializer, VerifyOTPSerializer, UserProfileSerializer,
    BuyerProfileSerializer, SellerProfileSerializer, DeliveryProfileSerializer,
    SellerApplicationSerializer, DeliveryApplicationSerializer, LoginSerializer,
    PasswordResetSendSerializer, PasswordResetConfirmSerializer,
    ChangePasswordSerializer,
)

class LoginView(APIView):
    permission_classes = [permissions.AllowAny]
    
    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        if serializer.is_valid():
            user = serializer.validated_data['user']
            refresh = RefreshToken.for_user(user)
            
            return Response({
                'success': True,
                'message': 'Login successful',
                'data': {
                    'access_token': str(refresh.access_token),
                    'refresh_token': str(refresh),
                    'user': UserProfileSerializer(user).data
                }
            }, status=status.HTTP_200_OK)

        errors = serializer.errors
        message = 'Invalid credentials'
        if errors.get('non_field_errors'):
            message = str(errors['non_field_errors'][0])
        elif errors.get('phone_number'):
            message = str(errors['phone_number'][0])

        return Response({
            'success': False,
            'message': message,
            'errors': errors,
        }, status=status.HTTP_400_BAD_REQUEST)


class SendOTPView(APIView):
    permission_classes = [permissions.AllowAny]
    
    def post(self, request):
        serializer = SendOTPSerializer(data=request.data)
        if serializer.is_valid():
            phone_number = serializer.validated_data['phone_number']
            
            # Generate OTP
            phone_otp = PhoneOTP.generate_otp(phone_number)
            
            # For development, print OTP to backend terminal.
            print(f"[DEV OTP] {phone_number} -> {phone_otp.otp_code}", flush=True)
            
            return Response({
                'success': True,
                'message': 'OTP sent successfully',
                'phone_number': str(phone_number)
            }, status=status.HTTP_200_OK)

        return Response({
            'success': False,
            'message': 'Invalid phone number.',
            'errors': serializer.errors,
        }, status=status.HTTP_400_BAD_REQUEST)


class VerifyOTPView(APIView):
    permission_classes = [permissions.AllowAny]
    
    def post(self, request):
        serializer = VerifyOTPSerializer(data=request.data)
        if serializer.is_valid():
            phone_number = serializer.validated_data['phone_number']
            role = serializer.validated_data.get('role', request.data.get('role', 'buyer'))
            full_name = serializer.validated_data.get('full_name') or request.data.get('full_name')
            gender = serializer.validated_data.get('gender') or request.data.get('gender')
            date_of_birth = serializer.validated_data.get('date_of_birth')
            if date_of_birth is None and request.data.get('date_of_birth') not in (None, ''):
                from django.utils.dateparse import parse_date
                date_of_birth = parse_date(str(request.data.get('date_of_birth')))

            phone_otp = serializer.validated_data.pop('_otp_instance')
            phone_otp.is_verified = True
            phone_otp.save()
            
            # Check if user exists
            user = User.objects.filter(phone_number=phone_number).first()
            
            if user:
                # Existing user - login
                user.is_phone_verified = True
                user.save()
                
                # Generate tokens
                refresh = RefreshToken.for_user(user)
                
                return Response({
                    'success': True,
                    'message': 'Login successful',
                    'data': {
                        'access_token': str(refresh.access_token),
                        'refresh_token': str(refresh),
                        'user': UserProfileSerializer(user).data,
                        'is_new_user': False
                    }
                }, status=status.HTTP_200_OK)
            else:
                # New user - create account
                if not role:
                    return Response({
                        'success': False,
                        'message': 'Role is required for new user registration'
                    }, status=status.HTTP_400_BAD_REQUEST)

                password = serializer.validated_data['password']

                # Create new user
                user_data = {
                    'phone_number': phone_number,
                    'password': password,
                    'role': role,
                    'is_phone_verified': True
                }
                
                # Add optional fields if provided
                if full_name:
                    user_data['full_name'] = full_name
                else:
                    user_data['full_name'] = 'User'  # Default name
                
                if gender:
                    user_data['gender'] = gender
                if date_of_birth is not None:
                    user_data['date_of_birth'] = date_of_birth
                
                user = User.objects.create_user(**user_data)
                
                # Create appropriate profile
                if role == 'buyer':
                    BuyerProfile.objects.create(user=user)
                elif role == 'seller':
                    SellerProfile.objects.create(
                        user=user,
                        shop_name='Pending setup',
                        shop_location='Pending setup',
                    )
                elif role == 'delivery':
                    DeliveryProfile.objects.create(user=user)
                
                # Generate tokens
                refresh = RefreshToken.for_user(user)
                
                return Response({
                    'success': True,
                    'message': 'Registration successful',
                    'data': {
                        'access_token': str(refresh.access_token),
                        'refresh_token': str(refresh),
                        'user': UserProfileSerializer(user).data,
                        'is_new_user': True
                    }
                }, status=status.HTTP_201_CREATED)

        err = serializer.errors
        message = 'Verification failed.'
        if err.get('otp_code'):
            message = str(err['otp_code'][0])
        elif err.get('password'):
            message = str(err['password'][0])
        elif err.get('non_field_errors'):
            message = str(err['non_field_errors'][0])
        elif err.get('phone_number'):
            message = str(err['phone_number'][0])
        return Response({
            'success': False,
            'message': message,
            'errors': err,
        }, status=status.HTTP_400_BAD_REQUEST)


class PasswordResetSendOTPView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = PasswordResetSendSerializer(data=request.data)
        if not serializer.is_valid():
            return Response({
                'success': False,
                'message': 'Invalid phone number.',
                'errors': serializer.errors,
            }, status=status.HTTP_400_BAD_REQUEST)

        phone_number = serializer.validated_data['phone_number']
        if User.objects.filter(phone_number=phone_number).exists():
            phone_otp = PhoneOTP.generate_otp(phone_number)
            print(
                f"[DEV PASSWORD RESET OTP] {phone_number} -> {phone_otp.otp_code}",
                flush=True,
            )

        return Response({
            'success': True,
            'message': 'If this number is registered, we sent a verification code.',
        }, status=status.HTTP_200_OK)


class PasswordResetConfirmView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = PasswordResetConfirmSerializer(data=request.data)
        if not serializer.is_valid():
            err = serializer.errors
            message = 'Could not reset password.'
            if err.get('non_field_errors'):
                message = str(err['non_field_errors'][0])
            elif err.get('otp_code'):
                message = str(err['otp_code'][0])
            elif err.get('phone_number'):
                message = str(err['phone_number'][0])
            elif err.get('new_password'):
                message = str(err['new_password'][0])
            return Response({
                'success': False,
                'message': message,
                'errors': err,
            }, status=status.HTTP_400_BAD_REQUEST)

        otp_instance = serializer.validated_data.pop('_otp_instance')
        otp_instance.is_verified = True
        otp_instance.save()

        phone_number = serializer.validated_data['phone_number']
        new_password = serializer.validated_data['new_password']
        user = User.objects.get(phone_number=phone_number)
        user.set_password(new_password)
        user.save()

        return Response({
            'success': True,
            'message': 'Password updated. You can sign in with your new password.',
        }, status=status.HTTP_200_OK)


class ChangePasswordView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        serializer = ChangePasswordSerializer(
            data=request.data,
            context={'request': request},
        )
        if not serializer.is_valid():
            err = serializer.errors
            message = 'Could not change password.'
            if err.get('old_password'):
                message = str(err['old_password'][0])
            elif err.get('new_password'):
                message = str(err['new_password'][0])
            elif err.get('non_field_errors'):
                message = str(err['non_field_errors'][0])
            return Response({
                'success': False,
                'message': message,
                'errors': err,
            }, status=status.HTTP_400_BAD_REQUEST)

        request.user.set_password(serializer.validated_data['new_password'])
        request.user.save()

        return Response({
            'success': True,
            'message': 'Password changed successfully.',
        }, status=status.HTTP_200_OK)


class ProfileView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    def get(self, request):
        user = request.user
        
        # Get user's profile based on role
        if user.role == 'buyer':
            try:
                profile = user.buyer_profile
                profile_data = BuyerProfileSerializer(profile).data
            except BuyerProfile.DoesNotExist:
                profile_data = None
        elif user.role == 'seller':
            try:
                profile = user.seller_profile
                profile_data = SellerProfileSerializer(profile).data
            except SellerProfile.DoesNotExist:
                profile_data = None
        elif user.role == 'delivery':
            profile, _ = DeliveryProfile.objects.get_or_create(
                user=user,
                defaults={
                    'vehicle_type': 'motorcycle',
                    'license_number': 'PENDING',
                },
            )
            profile_data = DeliveryProfileSerializer(profile).data
        else:
            profile_data = None
        
        return Response({
            'success': True,
            'data': {
                'user': UserProfileSerializer(user).data,
                'profile': profile_data
            }
        }, status=status.HTTP_200_OK)
    
    def put(self, request):
        user = request.user
        
        # Update user fields
        if 'email' in request.data:
            user.email = request.data['email']
        if 'full_name' in request.data:
            user.full_name = request.data['full_name']
        if 'gender' in request.data:
            user.gender = request.data['gender']
        if 'date_of_birth' in request.data:
            from django.utils.dateparse import parse_date
            raw_dob = request.data.get('date_of_birth')
            if raw_dob in (None, ''):
                user.date_of_birth = None
            else:
                parsed = parse_date(str(raw_dob)) if isinstance(raw_dob, str) else raw_dob
                user.date_of_birth = parsed
        
        user.save()
        
        # Update profile based on role
        if user.role == 'buyer':
            try:
                profile = user.buyer_profile
                serializer = BuyerProfileSerializer(profile, data=request.data, partial=True)
                if serializer.is_valid():
                    serializer.save()
                    profile_data = serializer.data
                else:
                    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
            except BuyerProfile.DoesNotExist:
                profile_data = None
        
        elif user.role == 'seller':
            try:
                profile = user.seller_profile
                serializer = SellerProfileSerializer(profile, data=request.data, partial=True)
                if serializer.is_valid():
                    serializer.save()
                    profile.refresh_from_db()
                    if 'shop_location' in request.data:
                        profile.shop_lat = None
                        profile.shop_lng = None
                        profile.save(update_fields=['shop_lat', 'shop_lng'])
                        profile.refresh_from_db()
                    profile_data = SellerProfileSerializer(profile).data
                else:
                    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
            except SellerProfile.DoesNotExist:
                profile_data = None
        
        elif user.role == 'delivery':
            profile, _ = DeliveryProfile.objects.get_or_create(
                user=user,
                defaults={
                    'vehicle_type': 'motorcycle',
                    'license_number': 'PENDING',
                },
            )
            serializer = DeliveryProfileSerializer(
                profile, data=request.data, partial=True
            )
            if serializer.is_valid():
                serializer.save()
                profile_data = serializer.data
            else:
                return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        
        return Response({
            'success': True,
            'message': 'Profile updated successfully',
            'data': {
                'user': UserProfileSerializer(user).data,
                'profile': profile_data
            }
        }, status=status.HTTP_200_OK)


class SellerApplicationView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    def post(self, request):
        if request.user.role != 'seller':
            return Response({
                'success': False,
                'message': 'Only sellers can apply for shop verification'
            }, status=status.HTTP_403_FORBIDDEN)
        
        serializer = SellerApplicationSerializer(data=request.data, context={'request': request})
        if serializer.is_valid():
            seller_profile = serializer.save()
            return Response({
                'success': True,
                'message': 'Seller application submitted successfully',
                'data': SellerProfileSerializer(seller_profile).data
            }, status=status.HTTP_201_CREATED)
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class DeliveryApplicationView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    def post(self, request):
        if request.user.role != 'delivery':
            return Response({
                'success': False,
                'message': 'Only delivery personnel can apply for verification'
            }, status=status.HTTP_403_FORBIDDEN)
        
        serializer = DeliveryApplicationSerializer(data=request.data, context={'request': request})
        if serializer.is_valid():
            delivery_profile = serializer.save()
            return Response({
                'success': True,
                'message': 'Delivery application submitted successfully',
                'data': DeliveryProfileSerializer(delivery_profile).data
            }, status=status.HTTP_201_CREATED)
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


def _payment_feature_disabled_response():
    return Response(
        {'error': 'Payment methods are temporarily disabled.'},
        status=status.HTTP_503_SERVICE_UNAVAILABLE,
    )


class BuyerPaymentMethodsView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return _payment_feature_disabled_response()

    def post(self, request):
        return _payment_feature_disabled_response()


class BuyerPaymentMethodDetailView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, method_id):
        return _payment_feature_disabled_response()

    def delete(self, request, method_id):
        return _payment_feature_disabled_response()


class VerifyBuyerPaymentMethodView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, method_id):
        return _payment_feature_disabled_response()


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def logout_view(request):
    try:
        refresh_token = request.data.get('refresh_token')
        if refresh_token:
            token = RefreshToken(refresh_token)
            token.blacklist()
        
        return Response({
            'success': True,
            'message': 'Logout successful'
        }, status=status.HTTP_200_OK)
    except Exception as e:
        return Response({
            'success': False,
            'message': 'Logout failed'
        }, status=status.HTTP_400_BAD_REQUEST)

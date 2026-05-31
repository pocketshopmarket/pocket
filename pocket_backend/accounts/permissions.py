from rest_framework.permissions import BasePermission


class IsBuyer(BasePermission):
    message = 'Only buyers can access this endpoint.'

    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and request.user.role == 'buyer')


class IsSeller(BasePermission):
    message = 'Only sellers can access this endpoint.'

    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and request.user.role == 'seller')


class IsApprovedSeller(BasePermission):
    message = 'Seller approval is required.'

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated or user.role != 'seller':
            return False
        profile = getattr(user, 'seller_profile', None)
        return bool(profile and profile.can_sell)


class IsApprovedDelivery(BasePermission):
    message = 'Delivery verification is required.'

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated or user.role != 'delivery':
            return False
        profile = getattr(user, 'delivery_profile', None)
        return bool(profile and profile.is_approved)

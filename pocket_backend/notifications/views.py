from rest_framework import generics, permissions, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from .models import Notification
from .serializers import NotificationSerializer


class NotificationListView(generics.ListAPIView):
    """Paginated list of notifications for the authenticated user."""

    serializer_class = NotificationSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return Notification.objects.filter(recipient=self.request.user)


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def unread_count(request):
    """Return the count of unread notifications."""
    count = Notification.objects.filter(
        recipient=request.user,
        is_read=False,
    ).count()
    return Response({'count': count})


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def mark_read(request, pk):
    """Mark a single notification as read."""
    try:
        notification = Notification.objects.get(pk=pk, recipient=request.user)
    except Notification.DoesNotExist:
        return Response(
            {'detail': 'Notification not found.'},
            status=status.HTTP_404_NOT_FOUND,
        )
    notification.is_read = True
    notification.save(update_fields=['is_read'])
    return Response({'status': 'ok'})


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def mark_all_read(request):
    """Mark all notifications for the authenticated user as read."""
    updated = Notification.objects.filter(
        recipient=request.user,
        is_read=False,
    ).update(is_read=True)
    return Response({'status': 'ok', 'updated': updated})


@api_view(['DELETE'])
@permission_classes([permissions.IsAuthenticated])
def delete_notification(request, pk):
    """Delete a single notification owned by the requesting user."""
    try:
        notification = Notification.objects.get(pk=pk, recipient=request.user)
    except Notification.DoesNotExist:
        return Response(
            {'detail': 'Notification not found.'},
            status=status.HTTP_404_NOT_FOUND,
        )
    notification.delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(['DELETE'])
@permission_classes([permissions.IsAuthenticated])
def clear_all_notifications(request):
    """Delete all notifications for the authenticated user."""
    Notification.objects.filter(recipient=request.user).delete()
    return Response(status=status.HTTP_204_NO_CONTENT)

from django.urls import path
from . import views

urlpatterns = [
    path('', views.NotificationListView.as_view(), name='notification-list'),
    path('clear/', views.clear_all_notifications, name='notification-clear-all'),
    path('unread-count/', views.unread_count, name='notification-unread-count'),
    path('mark-all-read/', views.mark_all_read, name='notification-mark-all-read'),
    path('<int:pk>/read/', views.mark_read, name='notification-mark-read'),
    path('<int:pk>/', views.delete_notification, name='notification-delete'),
]

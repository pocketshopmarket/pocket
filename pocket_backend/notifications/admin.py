from django.contrib import admin
from .models import Announcement, Notification


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ['id', 'recipient', 'notification_type', 'title', 'is_read', 'created_at']
    list_filter = ['notification_type', 'is_read', 'created_at']
    search_fields = ['title', 'message', 'recipient__phone_number', 'recipient__full_name']
    readonly_fields = ['created_at']
    raw_id_fields = ['recipient']


@admin.register(Announcement)
class AnnouncementAdmin(admin.ModelAdmin):
    list_display = ['title', 'target_audience', 'is_sent', 'sent_count', 'created_by', 'created_at']
    list_filter = ['target_audience', 'is_sent', 'created_at']
    search_fields = ['title', 'message']
    readonly_fields = ['is_sent', 'sent_count', 'created_by', 'created_at']

    fieldsets = (
        (None, {
            'fields': ('title', 'message', 'target_audience'),
            'description': (
                'Write the notification title and message, choose who receives it, '
                'then save. It will be sent immediately and cannot be re-sent.'
            ),
        }),
        ('Status', {
            'fields': ('is_sent', 'sent_count', 'created_by', 'created_at'),
        }),
    )

    def save_model(self, request, obj, form, change):
        if not obj.pk:
            obj.created_by = request.user
        super().save_model(request, obj, form, change)

    def has_change_permission(self, request, obj=None):
        # Prevent edits after sending to avoid confusion
        if obj and obj.is_sent:
            return False
        return super().has_change_permission(request, obj)

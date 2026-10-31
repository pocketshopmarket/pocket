from django.apps import AppConfig


class PromotionsConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'promotions'
    verbose_name = 'Promos & partners'

    def ready(self):
        from . import signals  # noqa: F401

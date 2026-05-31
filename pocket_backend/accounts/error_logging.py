import traceback

from django.core.exceptions import PermissionDenied as DjangoPermissionDenied
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import DatabaseError, ProgrammingError
from rest_framework import status
from rest_framework.exceptions import (
    AuthenticationFailed,
    NotAuthenticated,
    NotFound,
    PermissionDenied,
    Throttled,
    ValidationError,
)
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler

from .models import ErrorLog

SENSITIVE_KEYS = {
    'password',
    'new_password',
    'old_password',
    'token',
    'access',
    'refresh',
    'refresh_token',
    'authorization',
}


def _sanitize(value):
    if isinstance(value, dict):
        return {
            str(key): ('***' if str(key).lower() in SENSITIVE_KEYS else _sanitize(val))
            for key, val in value.items()
        }
    if isinstance(value, (list, tuple)):
        return [_sanitize(item) for item in value]
    if hasattr(value, 'name') and hasattr(value, 'size'):
        return {
            'filename': getattr(value, 'name', ''),
            'size': getattr(value, 'size', None),
        }
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    return str(value)


def _extract_request_data(request):
    try:
        if hasattr(request, 'data'):
            return _sanitize(dict(request.data))
    except Exception:
        pass

    try:
        if request.method in {'POST', 'PUT', 'PATCH'}:
            return _sanitize(dict(request.POST))
    except Exception:
        pass

    return {}


def _extract_metadata(request):
    meta = {
        'query_params': _sanitize(dict(request.GET)),
        'ip_address': request.META.get('REMOTE_ADDR', ''),
        'user_agent': request.META.get('HTTP_USER_AGENT', ''),
    }
    forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR', '')
    if forwarded_for:
        meta['forwarded_for'] = forwarded_for
    referer = request.META.get('HTTP_REFERER', '')
    if referer:
        meta['referer'] = referer
    return meta


def _first_error_message(data):
    if isinstance(data, dict):
        message = data.get('message')
        if isinstance(message, str) and message.strip():
            return message.strip()
        for value in data.values():
            msg = _first_error_message(value)
            if msg:
                return msg
    elif isinstance(data, list):
        for item in data:
            msg = _first_error_message(item)
            if msg:
                return msg
    elif isinstance(data, str):
        stripped = data.strip()
        if stripped:
            return stripped
    return None


def _classify_exception(exc, status_code):
    if isinstance(exc, (ValidationError, DjangoValidationError)) or status_code == 400:
        return 'validation'
    if isinstance(exc, (AuthenticationFailed, NotAuthenticated)) or status_code == 401:
        return 'authentication'
    if isinstance(exc, (PermissionDenied, DjangoPermissionDenied)) or status_code == 403:
        return 'permission'
    if isinstance(exc, NotFound) or status_code == 404:
        return 'not_found'
    if isinstance(exc, Throttled) or status_code == 429:
        return 'throttled'
    if status_code and 500 <= status_code < 600:
        return 'server'
    return 'unknown'


def _user_message(exc, status_code, response_data=None):
    if status_code == 400:
        return _first_error_message(response_data) or 'Please check your details and try again.'
    if status_code == 401:
        return 'Your session has expired. Please sign in again.'
    if status_code == 403:
        return 'You do not have permission to perform this action.'
    if status_code == 404:
        return 'We could not find what you requested.'
    if status_code == 429:
        if isinstance(exc, Throttled) and getattr(exc, 'detail', None):
            return str(exc.detail)
        return 'Too many attempts. Please wait and try again.'
    return 'Something went wrong on our side. Please try again shortly.'


def record_error(exc, request, status_code, response_data=None):
    user = getattr(request, 'user', None)
    authenticated_user = user if getattr(user, 'is_authenticated', False) else None
    error_type = _classify_exception(exc, status_code)
    user_message = _user_message(exc, status_code, response_data=response_data)

    try:
        return ErrorLog.objects.create(
            user=authenticated_user,
            error_type=error_type,
            error_code=getattr(exc, 'default_code', '') or '',
            error_class=exc.__class__.__name__,
            message=str(exc)[:5000],
            user_message=user_message,
            status_code=status_code,
            method=getattr(request, 'method', '')[:10],
            path=getattr(request, 'path', '')[:255],
            request_data=_extract_request_data(request),
            metadata=_extract_metadata(request),
            traceback=''.join(traceback.format_exception(type(exc), exc, exc.__traceback__))[:20000],
        )
    except (DatabaseError, ProgrammingError):
        return None
    except Exception:
        return None


def api_exception_handler(exc, context):
    response = drf_exception_handler(exc, context)
    request = context.get('request')

    if request is None:
        return response

    if response is not None:
        log = record_error(exc, request, response.status_code, response.data)
        payload = {
            'success': False,
            'message': _user_message(exc, response.status_code, response.data),
            'error_code': getattr(exc, 'default_code', '') or _classify_exception(exc, response.status_code),
        }
        if log is not None:
            payload['error_id'] = log.reference_id
        if response.status_code < 500 and response.data:
            payload['errors'] = response.data
        response.data = payload
        return response

    log = record_error(
        exc,
        request,
        status.HTTP_500_INTERNAL_SERVER_ERROR,
        response_data=None,
    )
    payload = {
        'success': False,
        'message': 'Something went wrong on our side. Please try again shortly.',
        'error_code': 'server_error',
    }
    if log is not None:
        payload['error_id'] = log.reference_id
    return Response(payload, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

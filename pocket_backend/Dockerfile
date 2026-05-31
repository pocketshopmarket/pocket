# Django API for AWS App Runner, ECS/Fargate, Lightsail Containers, or EC2.
# Build from this directory:  docker build -t pocket-backend .
# Run locally:  docker run --rm -p 8000:8000 -e DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1 pocket-backend

FROM python:3.13-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg62-turbo \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN mkdir -p staticfiles && DJANGO_ENV=production DJANGO_SECRET_KEY=build-only python manage.py collectstatic --noinput --clear 2>/dev/null || true

ENV DJANGO_ENV=production
ENV PORT=8000
EXPOSE 8000

CMD sh -c "python manage.py migrate --noinput && exec gunicorn pocket_backend.wsgi:application --bind 0.0.0.0:${PORT} --workers 2 --threads 2 --timeout 120 --log-file -"

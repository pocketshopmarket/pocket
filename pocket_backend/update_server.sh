#!/bin/bash
# Update the live Pocket Shop server to the latest code, in one command:
#
#     cd /var/www/pocket/pocket_backend && bash update_server.sh
#
# Safe to run any time: it pulls, installs, migrates, collects static files
# and restarts gunicorn the same way it is already run on this droplet.
# It never touches .env (where the Lenco keys live).

set -e

APP_DIR="/var/www/pocket/pocket_backend"
cd "$APP_DIR"

echo "=== 1. Pulling latest code ==="
git pull

echo "=== 2. Installing Python packages ==="
source venv/bin/activate
pip install -q -r requirements.txt

echo "=== 3. Applying database migrations ==="
python manage.py migrate --noinput

echo "=== 4. Collecting static files ==="
python manage.py collectstatic --noinput

echo "=== 5. Checking the project ==="
python manage.py check
deactivate

echo "=== 6. Restarting gunicorn ==="
pkill -f 'gunicorn pocket_backend.wsgi' || true
sleep 1
venv/bin/gunicorn pocket_backend.wsgi:application \
    --workers 3 --bind 0.0.0.0:8000 --timeout 120 \
    --error-logfile /var/log/gunicorn-error.log \
    --access-logfile /var/log/gunicorn-access.log \
    --daemon
sleep 2

echo "=== 7. Confirming it came back ==="
if pgrep -f 'gunicorn pocket_backend.wsgi' > /dev/null; then
    echo "gunicorn is running:"
    pgrep -fc 'gunicorn pocket_backend.wsgi' | sed 's/^/  processes: /'
else
    echo "!! gunicorn did NOT start - check /var/log/gunicorn-error.log"
    exit 1
fi

echo ""
if grep -q '^LENCO_API_TOKEN=.\+' .env 2>/dev/null; then
    echo "Lenco keys: set (card/bank features still need switching on in the admin)."
else
    echo "Lenco keys: NOT set yet - add LENCO_API_TOKEN, LENCO_PUBLIC_KEY and LENCO_ACCOUNT_ID to .env, then run this script again."
fi
echo "Done."

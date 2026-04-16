#!/bin/bash
set -e

# ============================================================
# PocketShop Backend - EC2 Deployment Script
# Run this ON the EC2 instance after uploading the code
# ============================================================

APP_DIR="/home/ubuntu/pocket_backend"
VENV_DIR="$APP_DIR/venv"

echo "=== 1. Installing system packages ==="
sudo apt update
sudo apt install -y python3 python3-pip python3-venv nginx

echo "=== 2. Setting up virtual environment ==="
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

echo "=== 3. Installing Python dependencies ==="
pip install --upgrade pip
pip install -r "$APP_DIR/requirements.txt"

echo "=== 4. Setting environment variables ==="
export DJANGO_ENV=production
export DJANGO_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")
export DJANGO_ALLOWED_HOSTS=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4),localhost,127.0.0.1

# Save env vars for the systemd service
sudo tee /etc/pocket_backend.env > /dev/null <<ENVEOF
DJANGO_ENV=production
DJANGO_SECRET_KEY=$DJANGO_SECRET_KEY
DJANGO_ALLOWED_HOSTS=$DJANGO_ALLOWED_HOSTS
ENVEOF
sudo chmod 600 /etc/pocket_backend.env

echo "=== 5. Running migrations and collecting static files ==="
cd "$APP_DIR"
python manage.py migrate --no-input
python manage.py collectstatic --no-input

echo "=== 5b. Paths readable by Nginx (www-data) for /static/ and /media/ ==="
sudo chmod 755 /home/ubuntu
chmod 755 "$APP_DIR"

echo "=== 6. Creating Gunicorn log directory ==="
sudo mkdir -p /var/log/gunicorn
sudo chown ubuntu:ubuntu /var/log/gunicorn

echo "=== 7. Setting up Gunicorn systemd service ==="
sudo tee /etc/systemd/system/gunicorn.service > /dev/null <<EOF
[Unit]
Description=Gunicorn daemon for PocketShop Backend
After=network.target

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=$APP_DIR
EnvironmentFile=/etc/pocket_backend.env
ExecStart=$VENV_DIR/bin/gunicorn pocket_backend.wsgi:application -c $APP_DIR/gunicorn.conf.py

[Install]
WantedBy=multi-user.target
EOF

echo "=== 8. Setting up Nginx ==="
sudo cp "$APP_DIR/nginx.conf" /etc/nginx/sites-available/pocket_backend
sudo ln -sf /etc/nginx/sites-available/pocket_backend /etc/nginx/sites-enabled/pocket_backend
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t

echo "=== 9. Starting services ==="
sudo systemctl daemon-reload
sudo systemctl enable gunicorn
sudo systemctl start gunicorn
sudo systemctl restart nginx

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo ""
echo "============================================"
echo "  Deployment complete!"
echo "  API is live at: http://$PUBLIC_IP/api/"
echo "  Admin panel:    http://$PUBLIC_IP/admin/"
echo "============================================"

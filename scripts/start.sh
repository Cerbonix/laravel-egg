#!/bin/bash
# =============================================================================
# Laravel Egg — Main orchestrator
# Manages: Git, Composer, NPM, Artisan, PHP-FPM, Nginx, background services
# =============================================================================

set -euo pipefail

# --- Signal handling for clean shutdown ------------------------------------
CHILD_PIDS=()

cleanup() {
    echo "[laravel-egg] Shutting down..."
    for pid in "${CHILD_PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    # Stop PHP-FPM gracefully
    if [ -f "/home/container/tmp/php-fpm.pid" ]; then
        kill "$(cat /home/container/tmp/php-fpm.pid)" 2>/dev/null || true
    fi
    exit 0
}
trap cleanup SIGINT SIGTERM

# --- Utility functions ------------------------------------------------------

log() {
    echo "[laravel-egg] $1"
}

warn() {
    echo "[laravel-egg] WARNING: $1" >&2
}

error_exit() {
    echo "[laravel-egg] ERROR: $1" >&2
    exit 1
}

# =============================================================================
# Phase 0 : Setup
# =============================================================================

PHP_VERSION=$(cat /etc/php_version)
log "Detected PHP ${PHP_VERSION}"

# Create required directories
mkdir -p /home/container/{logs,tmp/sessions,tmp/nginx/{client_body,proxy,fastcgi,uwsgi,scgi},conf/nginx/conf.d,conf/php/pool.d,www/public}

# Copy default configs if absent (first run or reset)
if [ ! -f /home/container/conf/nginx/nginx.conf ]; then
    log "Copying default Nginx config..."
    cp /etc/laravel-egg/conf/nginx/nginx.conf /home/container/conf/nginx/nginx.conf
    cp /etc/laravel-egg/conf/nginx/conf.d/default.conf /home/container/conf/nginx/conf.d/default.conf
fi

if [ ! -f /home/container/conf/php/php-fpm.conf ]; then
    log "Copying default PHP-FPM config..."
    cp /etc/laravel-egg/conf/php/php-fpm.conf /home/container/conf/php/php-fpm.conf
    cp /etc/laravel-egg/conf/php/pool.d/*.conf /home/container/conf/php/pool.d/
fi

if [ ! -f /home/container/conf/php/php.ini ]; then
    log "Copying default php.ini..."
    cp /etc/laravel-egg/conf/php/php.ini /home/container/conf/php/php.ini
fi

# Auto-tune PHP-FPM pm.max_children based on SERVER_MEMORY (in MB)
if [ -n "${SERVER_MEMORY:-}" ] && [ "${SERVER_MEMORY}" -gt 0 ] 2>/dev/null; then
    # Each PHP worker uses ~30-50MB; reserve 128MB for Nginx + system
    AVAILABLE=$((SERVER_MEMORY - 128))
    if [ "$AVAILABLE" -lt 50 ]; then
        AVAILABLE=50
    fi
    MAX_CHILDREN=$((AVAILABLE / 40))
    if [ "$MAX_CHILDREN" -lt 2 ]; then
        MAX_CHILDREN=2
    fi
    if [ "$MAX_CHILDREN" -gt 50 ]; then
        MAX_CHILDREN=50
    fi

    START_SERVERS=$((MAX_CHILDREN / 4))
    [ "$START_SERVERS" -lt 1 ] && START_SERVERS=1
    MIN_SPARE=$((START_SERVERS))
    MAX_SPARE=$((START_SERVERS * 2))
    [ "$MAX_SPARE" -gt "$MAX_CHILDREN" ] && MAX_SPARE=$MAX_CHILDREN

    log "Auto-tuning PHP-FPM: max_children=${MAX_CHILDREN} (${SERVER_MEMORY}MB allocated)"
    sed -i "s/pm.max_children = .*/pm.max_children = ${MAX_CHILDREN}/" /home/container/conf/php/pool.d/www.conf
    sed -i "s/pm.start_servers = .*/pm.start_servers = ${START_SERVERS}/" /home/container/conf/php/pool.d/www.conf
    sed -i "s/pm.min_spare_servers = .*/pm.min_spare_servers = ${MIN_SPARE}/" /home/container/conf/php/pool.d/www.conf
    sed -i "s/pm.max_spare_servers = .*/pm.max_spare_servers = ${MAX_SPARE}/" /home/container/conf/php/pool.d/www.conf
fi

# =============================================================================
# Phase 1 : Git
# =============================================================================

if [ -n "${GIT_ADDRESS:-}" ]; then
    # Build authenticated URL if credentials are provided
    GIT_URL="${GIT_ADDRESS}"
    if [ -n "${GIT_USERNAME:-}" ] && [ -n "${GIT_ACCESS_TOKEN:-}" ]; then
        GIT_URL="https://${GIT_USERNAME}:${GIT_ACCESS_TOKEN}@$(echo "${GIT_ADDRESS}" | sed 's|https\?://||')"
    fi

    if [ -d /home/container/www/.git ]; then
        if [ "${AUTO_UPDATE:-0}" = "1" ]; then
            log "Pulling latest changes..."
            cd /home/container/www
            git pull --ff-only || warn "Git pull failed, continuing with existing code"
            cd /home/container
        else
            log "Git repo exists, AUTO_UPDATE disabled — skipping pull"
        fi
    elif [ ! "$(ls -A /home/container/www 2>/dev/null)" ]; then
        log "Cloning repository..."
        BRANCH_FLAG=""
        if [ -n "${GIT_BRANCH:-}" ]; then
            BRANCH_FLAG="--single-branch --branch ${GIT_BRANCH}"
        fi
        git clone ${BRANCH_FLAG} "${GIT_URL}" /home/container/www \
            || error_exit "Git clone failed"
    else
        log "www/ is not empty and has no .git — skipping clone"
    fi
else
    log "No GIT_ADDRESS set — skipping git operations"
fi

# =============================================================================
# Phase 2 : Dependencies
# =============================================================================

cd /home/container/www 2>/dev/null || true

# Composer
if [ -f /home/container/www/composer.json ]; then
    log "Installing Composer dependencies..."
    cd /home/container/www
    composer install --no-dev --optimize-autoloader --no-interaction --no-progress \
        || warn "Composer install failed"
fi

# NPM (optional — for building frontend assets)
if [ "${ENABLE_NPM:-0}" = "1" ] && [ -f /home/container/www/package.json ]; then
    log "Installing NPM dependencies and building assets..."
    cd /home/container/www
    npm ci --no-audit --no-fund 2>/dev/null || npm install --no-audit --no-fund
    NPM_CMD="${NPM_BUILD_CMD:-npm run build}"
    eval "${NPM_CMD}" || warn "NPM build failed"
    # Clean node_modules to save disk space
    rm -rf /home/container/www/node_modules
    log "NPM build complete, node_modules cleaned"
fi

cd /home/container

# =============================================================================
# Phase 3 : Laravel configuration
# =============================================================================

if [ -f /home/container/www/artisan ]; then
    cd /home/container/www

    # Generate .env from Pterodactyl panel variables
    log "Syncing .env file..."
    ENV_FILE="/home/container/www/.env"

    # Start from .env.example if .env doesn't exist
    if [ ! -f "${ENV_FILE}" ] && [ -f /home/container/www/.env.example ]; then
        cp /home/container/www/.env.example "${ENV_FILE}"
    fi
    # Create minimal .env if neither exists
    if [ ! -f "${ENV_FILE}" ]; then
        touch "${ENV_FILE}"
    fi

    # Sync panel variables into .env
    update_env() {
        local key="$1" value="$2"
        if [ -z "${value}" ]; then return; fi
        if grep -q "^${key}=" "${ENV_FILE}" 2>/dev/null; then
            sed -i "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}"
        else
            echo "${key}=${value}" >> "${ENV_FILE}"
        fi
    }

    update_env "APP_NAME" "\"${APP_NAME:-Laravel}\""
    update_env "APP_ENV" "${APP_ENV:-production}"
    update_env "APP_DEBUG" "${APP_DEBUG:-false}"
    update_env "APP_URL" "${APP_URL:-http://localhost}"
    [ -n "${APP_KEY:-}" ] && update_env "APP_KEY" "${APP_KEY}"

    update_env "DB_CONNECTION" "${DB_CONNECTION:-mysql}"
    update_env "DB_HOST" "${DB_HOST:-127.0.0.1}"
    update_env "DB_PORT" "${DB_PORT:-3306}"
    update_env "DB_DATABASE" "${DB_DATABASE:-laravel}"
    update_env "DB_USERNAME" "${DB_USERNAME:-root}"
    update_env "DB_PASSWORD" "\"${DB_PASSWORD:-}\""

    update_env "REDIS_HOST" "${REDIS_HOST:-127.0.0.1}"
    update_env "REDIS_PORT" "${REDIS_PORT:-6379}"
    update_env "REDIS_PASSWORD" "\"${REDIS_PASSWORD:-}\""

    update_env "QUEUE_CONNECTION" "${QUEUE_CONNECTION:-sync}"

    # Generate APP_KEY if not set
    CURRENT_KEY=$(grep "^APP_KEY=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2-)
    if [ -z "${CURRENT_KEY}" ] || [ "${CURRENT_KEY}" = "" ]; then
        log "Generating application key..."
        php artisan key:generate --force --no-interaction
    fi

    # Storage symlink
    php artisan storage:link --force --no-interaction 2>/dev/null || true

    # Database migrations (optional)
    if [ "${ENABLE_MIGRATE:-0}" = "1" ]; then
        log "Running database migrations..."
        php artisan migrate --force --no-interaction \
            || warn "Migration failed — check database connectivity"
    fi

    # Custom artisan commands
    if [ -n "${CUSTOM_ARTISAN:-}" ]; then
        log "Running custom artisan commands..."
        IFS=',' read -ra COMMANDS <<< "${CUSTOM_ARTISAN}"
        for cmd in "${COMMANDS[@]}"; do
            cmd=$(echo "${cmd}" | xargs) # Trim whitespace
            if [ -n "${cmd}" ]; then
                log "  → php artisan ${cmd}"
                php artisan ${cmd} --no-interaction || warn "Command failed: ${cmd}"
            fi
        done
    fi

    # Optimize for production
    log "Optimizing Laravel..."
    php artisan optimize --no-interaction 2>/dev/null || true

    cd /home/container
else
    log "No artisan file found — skipping Laravel configuration"
fi

# =============================================================================
# Phase 4 : Background services (optional)
# =============================================================================

# Queue worker
if [ "${ENABLE_QUEUE:-0}" = "1" ] && [ -f /home/container/www/artisan ]; then
    if [ "${ENABLE_HORIZON:-0}" = "1" ]; then
        log "Starting Laravel Horizon..."
        cd /home/container/www
        php artisan horizon &
        CHILD_PIDS+=($!)
    else
        log "Starting queue worker..."
        cd /home/container/www
        php artisan queue:work --sleep=3 --tries=3 --max-time=3600 &
        CHILD_PIDS+=($!)
    fi
    cd /home/container
fi

# Task scheduler (runs artisan schedule:run every 60 seconds)
if [ "${ENABLE_SCHEDULER:-0}" = "1" ] && [ -f /home/container/www/artisan ]; then
    log "Starting task scheduler..."
    (
        while true; do
            cd /home/container/www
            php artisan schedule:run --no-interaction >> /home/container/logs/scheduler.log 2>&1
            sleep 60
        done
    ) &
    CHILD_PIDS+=($!)
    cd /home/container
fi

# WebSockets (Laravel Reverb)
if [ "${ENABLE_WEBSOCKETS:-0}" = "1" ] && [ -f /home/container/www/artisan ]; then
    WS_PORT_NUM="${WS_PORT:-6001}"
    log "Starting WebSocket server on port ${WS_PORT_NUM}..."
    cd /home/container/www
    php artisan reverb:start --port="${WS_PORT_NUM}" &
    CHILD_PIDS+=($!)
    cd /home/container
fi

# =============================================================================
# Phase 5 : Network services (optional)
# =============================================================================

# Cloudflare Tunnel
if [ -n "${CLOUDFLARE_TOKEN:-}" ]; then
    log "Starting Cloudflare tunnel..."
    cloudflared tunnel --no-autoupdate run --token "${CLOUDFLARE_TOKEN}" &
    CHILD_PIDS+=($!)
fi

# =============================================================================
# Phase 6 : Start PHP-FPM and Nginx
# =============================================================================

log "Starting PHP-FPM ${PHP_VERSION}..."
php-fpm${PHP_VERSION} \
    --fpm-config /home/container/conf/php/php-fpm.conf \
    -c /home/container/conf/php/php.ini \
    || error_exit "PHP-FPM failed to start"

# Brief pause to let FPM create the socket
sleep 1

if [ ! -S /home/container/tmp/php-fpm.sock ]; then
    error_exit "PHP-FPM socket not found — check logs at /home/container/logs/"
fi

log "Starting Nginx..."
echo "Services successfully launched"

# Nginx runs in foreground (daemon off) — this blocks and keeps the container alive
exec nginx -c /home/container/conf/nginx/nginx.conf

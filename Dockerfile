# =============================================================================
# Pterodactyl Laravel Egg — PHP-FPM + Nginx (all-in-one)
# Base: Debian Bookworm Slim + Sury PHP repo
# Build: docker build --build-arg PHP_VERSION=8.4 -t laravel-egg:8.4 .
# =============================================================================

FROM debian:bookworm-slim

ARG PHP_VERSION=8.4
ARG TARGETARCH

LABEL maintainer="alex"
LABEL org.opencontainers.image.source="https://github.com/cerbonix/laravel-egg"
LABEL org.opencontainers.image.description="Pterodactyl Laravel Egg — PHP ${PHP_VERSION} + Nginx"

# Persist the PHP version so scripts can detect it at runtime
RUN echo "${PHP_VERSION}" > /etc/php_version

# --- System dependencies ---------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        git \
        unzip \
        tini \
        iproute2 \
        cron \
        nginx \
        sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# --- PHP via Sury ----------------------------------------------------------
RUN curl -sSLo /tmp/debsuryorg-archive-keyring.deb \
        https://packages.sury.org/debsuryorg-archive-keyring.deb \
    && dpkg -i /tmp/debsuryorg-archive-keyring.deb \
    && rm /tmp/debsuryorg-archive-keyring.deb \
    && echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
        > /etc/apt/sources.list.d/php.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-imagick \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-pgsql \
        php${PHP_VERSION}-sqlite3 \
        php${PHP_VERSION}-redis \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-opcache \
        php${PHP_VERSION}-common \
    && rm -rf /var/lib/apt/lists/*

# --- Composer (official installer) -----------------------------------------
RUN curl -sS https://getcomposer.org/installer | php -- \
        --install-dir=/usr/local/bin --filename=composer

# --- Node.js 22 LTS via NodeSource -----------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# --- Cloudflared (architecture-aware) --------------------------------------
RUN CFARCH=$([ "${TARGETARCH}" = "arm64" ] && echo "arm64" || echo "amd64") \
    && curl -fsSL -o /usr/local/bin/cloudflared \
        "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CFARCH}" \
    && chmod +x /usr/local/bin/cloudflared

# --- Pterodactyl user (UID 1000) -------------------------------------------
RUN useradd -m -d /home/container -s /bin/bash -u 1000 container

# --- Default config files (source of truth) ---------------------------------
COPY --chown=container:container conf/ /etc/laravel-egg/conf/

# --- Scripts ----------------------------------------------------------------
COPY --chown=container:container scripts/entrypoint.sh /entrypoint.sh
COPY --chown=container:container scripts/start.sh /start.sh
RUN chmod +x /entrypoint.sh /start.sh

# --- Nginx: allow non-root to bind and write --------------------------------
RUN chown -R container:container /var/lib/nginx /var/log/nginx /run

STOPSIGNAL SIGINT
WORKDIR /home/container
USER container

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]

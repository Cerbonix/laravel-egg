# Pterodactyl Laravel Egg

A Pterodactyl egg for deploying Laravel applications with **PHP-FPM + Nginx** in a single container.

## Features

- **PHP version selector** — Choose PHP 8.2, 8.3, or 8.4 from the panel dropdown
- **All-in-one container** — PHP-FPM and Nginx running together
- **Git integration** — Clone and auto-update from public or private repositories
- **Composer + NPM** — Automatic dependency installation and asset building
- **Laravel Artisan** — Key generation, migrations, storage link, custom commands
- **Background services** — Queue worker, Horizon, task scheduler, Reverb WebSockets
- **Cloudflare Tunnel** — Built-in cloudflared for secure exposure
- **Auto-tuning** — PHP-FPM worker count scaled to allocated memory
- **20+ PHP extensions** — bcmath, curl, gd, imagick, intl, mbstring, mysql, pgsql, sqlite3, redis, xml, zip, opcache, sodium, and more

## Prerequisites

- Pterodactyl Panel v1.x or v2.x (Pelican)
- At least one port allocation for HTTP
- (Optional) A MySQL/PostgreSQL database and Redis server via separate eggs

## Installation

1. Download `egg-laravel.json` from this repository
2. In Pterodactyl Panel, go to **Admin → Nests → Import Egg**
3. Upload the JSON file and save
4. Create a new server using the **Laravel** egg
5. Set the Git repository URL and other variables
6. Start the server

## Docker Images

| Tag | PHP Version | Status |
|-----|-------------|--------|
| `ghcr.io/cerbonix/laravel-egg:8.4` | PHP 8.4 | Recommended |
| `ghcr.io/cerbonix/laravel-egg:8.3` | PHP 8.3 | Supported |
| `ghcr.io/cerbonix/laravel-egg:8.2` | PHP 8.2 | Supported |

## Variables

### Git Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `GIT_ADDRESS` | — | HTTPS URL of the Git repository |
| `GIT_BRANCH` | — | Branch to clone (empty = default branch) |
| `GIT_USERNAME` | — | Username for private repos |
| `GIT_ACCESS_TOKEN` | — | Personal Access Token for private repos |
| `AUTO_UPDATE` | `0` | Pull latest changes on startup |

### Laravel Core

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_NAME` | `Laravel` | Application name |
| `APP_ENV` | `production` | Environment (production, staging, local) |
| `APP_DEBUG` | `false` | Debug mode |
| `APP_URL` | `http://localhost` | Public URL |
| `APP_KEY` | — | Encryption key (auto-generated if empty) |

### Database

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_CONNECTION` | `mysql` | Driver (mysql, pgsql, sqlite, sqlsrv) |
| `DB_HOST` | `127.0.0.1` | Database host |
| `DB_PORT` | `3306` | Database port |
| `DB_DATABASE` | `laravel` | Database name |
| `DB_USERNAME` | `root` | Database user |
| `DB_PASSWORD` | — | Database password |

### Redis

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_HOST` | `127.0.0.1` | Redis host |
| `REDIS_PORT` | `6379` | Redis port |
| `REDIS_PASSWORD` | — | Redis password |

### Build

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_NPM` | `0` | Run NPM install + build on startup |
| `NPM_BUILD_CMD` | `npm run build` | Custom build command |
| `ENABLE_MIGRATE` | `0` | Run migrations on startup |

### Background Services

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_QUEUE` | `0` | Start queue worker |
| `QUEUE_CONNECTION` | `sync` | Queue driver (sync, database, redis, sqs) |
| `ENABLE_HORIZON` | `0` | Use Horizon instead of default worker |
| `ENABLE_SCHEDULER` | `0` | Run task scheduler |
| `ENABLE_WEBSOCKETS` | `0` | Start Reverb WebSocket server |

### SSL / Cloudflare

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_SSL` | `0` | Enable Let's Encrypt SSL |
| `CERTBOT_EMAIL` | — | Email for certificate registration |
| `CERTBOT_DOMAIN` | — | Domain for the certificate |
| `CERTBOT_STAGING` | `0` | Use staging server for testing |
| `CLOUDFLARE_TOKEN` | — | Cloudflare Tunnel token |

### Advanced

| Variable | Default | Description |
|----------|---------|-------------|
| `USER_UPLOAD` | `0` | Skip git clone (upload files via SFTP) |
| `CUSTOM_ARTISAN` | — | Comma-separated artisan commands to run |
| `WS_PORT` | `6001` | WebSocket server port |

## Deployment Examples

### Basic Laravel Application

1. Set `GIT_ADDRESS` to `https://github.com/your-user/your-app`
2. Set database variables to point to your MySQL egg
3. Set `ENABLE_MIGRATE` to `1`
4. Start the server

### Laravel + Queue + Horizon

1. Configure as above
2. Set `ENABLE_QUEUE` to `1`
3. Set `QUEUE_CONNECTION` to `redis`
4. Set `ENABLE_HORIZON` to `1`
5. Set Redis variables to point to your Redis egg
6. Start the server

### Laravel + Scheduled Tasks

1. Configure as above
2. Set `ENABLE_SCHEDULER` to `1`
3. Define your scheduled tasks in `app/Console/Kernel.php`

## File Structure (inside container)

```
/home/container/
├── www/                    # Laravel application root
│   └── public/             # Web root (Nginx document root)
├── conf/                   # User-editable configuration
│   ├── nginx/
│   │   ├── nginx.conf
│   │   └── conf.d/
│   │       └── default.conf
│   └── php/
│       ├── php.ini
│       ├── php-fpm.conf
│       └── pool.d/
│           └── www.conf
├── logs/                   # Application and service logs
└── tmp/                    # Runtime files (sockets, PID, sessions)
```

## Troubleshooting

### Server shows "502 Bad Gateway"
- PHP-FPM may have failed to start. Check `logs/php-fpm-error.log`
- Verify the PHP-FPM socket exists: the startup log should show "Starting PHP-FPM"

### Composer install fails
- Check that `GIT_ADDRESS` is correct and the repo contains a `composer.json`
- For private repos, ensure `GIT_USERNAME` and `GIT_ACCESS_TOKEN` are set

### Migrations fail on startup
- Verify database variables (host, port, name, user, password)
- Ensure the database server is running and accessible from the container network
- Check `logs/php-error.log` for connection details

### Assets not loading (CSS/JS 404)
- Enable `ENABLE_NPM` and ensure `package.json` exists
- Check that the build command produces output in `public/build/`

### "Services successfully launched" but page is blank
- Check `www/public/index.php` exists
- Verify `APP_KEY` is set (check `.env` file via SFTP)
- Check `logs/nginx-error.log` for PHP errors

## Local Development

Build the image locally:

```bash
docker build --build-arg PHP_VERSION=8.4 -t laravel-egg:8.4 .
```

Test PHP and extensions:

```bash
docker run --rm laravel-egg:8.4 php -v
docker run --rm laravel-egg:8.4 php -m
```

Verify user:

```bash
docker run --rm laravel-egg:8.4 id
# Expected: uid=1000(container) gid=1000(container)
```

## License

MIT — See [LICENSE](LICENSE) for details.

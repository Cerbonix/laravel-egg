# Pterodactyl Laravel Egg

A Pterodactyl egg that runs a full Laravel application inside **a single container** with PHP-FPM + Nginx. Think of it as a ready-made server template: import the egg, create a server, point it at your Git repo, and your Laravel app is live.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Docker Images](#docker-images)
- [How It Works — The Big Picture](#how-it-works--the-big-picture)
  - [What Is Inside the Container](#what-is-inside-the-container)
  - [Project File Structure (this repository)](#project-file-structure-this-repository)
  - [Container File Structure (at runtime)](#container-file-structure-at-runtime)
- [Lifecycle — From Creation to Daily Use](#lifecycle--from-creation-to-daily-use)
  - [Step 1: Image Build (CI/CD)](#step-1-image-build-cicd)
  - [Step 2: Server Installation (one-time provisioning)](#step-2-server-installation-one-time-provisioning)
  - [Step 3: Every Startup (the 6-phase orchestrator)](#step-3-every-startup-the-6-phase-orchestrator)
  - [Step 4: Runtime (serving requests)](#step-4-runtime-serving-requests)
  - [Step 5: Shutdown](#step-5-shutdown)
- [Configuration Deep Dive](#configuration-deep-dive)
  - [Nginx Configuration](#nginx-configuration)
  - [PHP Configuration (php.ini)](#php-configuration-phpini)
  - [PHP-FPM Configuration](#php-fpm-configuration)
- [Variables Reference](#variables-reference)
  - [Git Configuration](#git-configuration)
  - [Laravel Core](#laravel-core)
  - [Database](#database)
  - [Redis](#redis)
  - [Build](#build)
  - [Background Services](#background-services)
  - [Cloudflare Tunnel](#cloudflare-tunnel)
  - [SSL (Let's Encrypt)](#ssl-lets-encrypt)
  - [Advanced](#advanced)
- [Deployment Examples](#deployment-examples)
- [Design Decisions and Good-to-Know](#design-decisions-and-good-to-know)
- [Troubleshooting](#troubleshooting)
- [Wings Security Recommendations](#wings-security-recommendations)
- [Local Development](#local-development)
- [License](#license)

## Features

- **PHP version selector** — Choose PHP 8.2, 8.3, or 8.4 from the panel dropdown
- **All-in-one container** — PHP-FPM and Nginx running together, no extra services to manage
- **Dynamic port binding** — Nginx automatically listens on the Pterodactyl allocated port
- **Git integration** — Clone and auto-update from public or private repositories
- **Composer + NPM** — Automatic dependency installation and frontend asset building
- **Laravel Artisan** — Key generation, migrations, storage link, custom commands
- **Background services** — Queue worker, Horizon, task scheduler, Reverb WebSockets
- **Cloudflare Tunnel** — Built-in cloudflared for secure public exposure without SSL management
- **Auto-tuning** — PHP-FPM worker count automatically scaled to allocated server memory
- **Production-hardened** — OPcache with JIT, gzip compression, dangerous PHP functions disabled, sensitive files blocked
- **20+ PHP extensions** — bcmath, curl, gd, imagick, intl, mbstring, mysql, pgsql, sqlite3, redis, xml, zip, opcache, and more

## Prerequisites

- Pterodactyl Panel v1.x or v2.x (Pelican)
- At least one port allocation for HTTP
- (Optional) A MySQL/PostgreSQL database and Redis server via separate eggs or external services

## Installation

1. Download `egg-laravel.json` from this repository
2. In Pterodactyl Panel, go to **Admin -> Nests -> Import Egg**
3. Upload the JSON file and save
4. Create a new server using the **Laravel** egg
5. Select the desired PHP version from the Docker image dropdown
6. Allocate a port (this is the port Nginx will listen on)
7. Set the Git repository URL and other variables
8. Start the server

## Docker Images

| Tag | PHP Version | Status |
|-----|-------------|--------|
| `ghcr.io/cerbonix/laravel-egg:8.4` | PHP 8.4 | Recommended |
| `ghcr.io/cerbonix/laravel-egg:8.3` | PHP 8.3 | Supported |
| `ghcr.io/cerbonix/laravel-egg:8.2` | PHP 8.2 | Supported |

Images are built for `linux/amd64` and `linux/arm64` and rebuilt weekly (Sunday 3:00 UTC) for security patches.

## How It Works — The Big Picture

### What Is Inside the Container

The Docker image is built from `debian:bookworm-slim` and bundles everything needed to serve a Laravel app:

| Component | Purpose |
|-----------|---------|
| **Nginx** | Web server, reverse proxies requests to PHP-FPM |
| **PHP-FPM + CLI** | Executes PHP code (the selected version: 8.2, 8.3, or 8.4) |
| **17 PHP extensions** | bcmath, curl, xml, gd, imagick, intl, mbstring, mysql, pgsql, sqlite3, redis, zip, opcache, common, and more |
| **Composer** | PHP dependency manager |
| **Node.js 22 LTS** | For building frontend assets (Vite, Mix, etc.) |
| **Git** | Clone and pull your application repository |
| **Cloudflared** | Cloudflare Tunnel client for secure public exposure |
| **SQLite3** | Lightweight database for simple apps |

Everything runs under a non-root user named `container` (UID 1000), as required by Pterodactyl.

### Project File Structure (this repository)

```
laravel-egg/
├── Dockerfile                      # Image build recipe
├── egg-laravel.json                # Egg definition for Pterodactyl (variables, install script)
├── scripts/
│   ├── entrypoint.sh               # Container entry point (Pterodactyl standard pattern)
│   └── start.sh                    # Main orchestrator (the brain of the egg)
├── conf/
│   ├── nginx/
│   │   ├── nginx.conf              # Nginx main configuration
│   │   └── conf.d/
│   │       └── default.conf        # Laravel virtual host
│   └── php/
│       ├── php.ini                 # PHP runtime configuration
│       ├── php-fpm.conf            # PHP-FPM global configuration
│       └── pool.d/
│           └── www.conf            # PHP-FPM worker pool configuration
├── .github/workflows/
│   └── build.yml                   # CI/CD: multi-arch build + push to GHCR
├── README.md
└── LICENSE
```

### Container File Structure (at runtime)

Once a server is running, the persistent volume inside the container looks like this:

```
/home/container/
├── www/                            # Your Laravel application
│   ├── public/                     # Web root (Nginx document root)
│   ├── artisan                     # Laravel CLI
│   ├── composer.json
│   ├── .env                        # Generated/synced from panel variables
│   └── ...                         # The rest of your Laravel app
├── conf/                           # User-editable configs (persistent across restarts)
│   ├── nginx/
│   │   ├── nginx.conf
│   │   └── conf.d/
│   │       └── default.conf
│   └── php/
│       ├── php.ini
│       ├── php-fpm.conf
│       └── pool.d/
│           └── www.conf
├── logs/                           # All log files
│   ├── nginx-access.log
│   ├── nginx-error.log
│   ├── php-error.log
│   ├── php-fpm-error.log
│   ├── php-fpm-slow.log
│   └── scheduler.log
└── tmp/                            # Runtime files (not persistent data)
    ├── php-fpm.pid
    ├── php-fpm.sock                # Unix socket for Nginx <-> PHP-FPM
    ├── sessions/                   # PHP session files
    └── nginx/                      # Nginx temp files (client_body, proxy, etc.)
```

Key point: `conf/` and `www/` persist across restarts because they live in the Pterodactyl volume. The `tmp/` directory is recreated every startup.

## Lifecycle — From Creation to Daily Use

### Step 1: Image Build (CI/CD)

This happens automatically via GitHub Actions — you don't need to do this yourself unless you're developing the egg.

The workflow in `.github/workflows/build.yml`:
1. Triggers on: push to `main`, Git tags (`v*`), weekly schedule (Sunday 3:00 UTC), or manual dispatch
2. Builds **3 images** in parallel (one per PHP version: 8.2, 8.3, 8.4)
3. Each image is built for **2 architectures** (amd64 + arm64) using Docker Buildx + QEMU
4. Pushes to `ghcr.io/cerbonix/laravel-egg:<version>`
5. The `latest` tag always points to PHP 8.4

The Dockerfile installs packages in layers:
- System packages (git, curl, nginx, cron, sqlite3...)
- PHP + extensions from the [Sury repository](https://packages.sury.org)
- Composer (official installer)
- Node.js 22 LTS (NodeSource)
- Cloudflared binary (architecture-aware download)
- Creates the `container` user (UID 1000)
- Copies default config files to `/etc/laravel-egg/conf/` (the "source of truth")

### Step 2: Server Installation (one-time provisioning)

When an admin creates a new server with this egg, Pterodactyl runs the **installation script** (defined inside `egg-laravel.json`) in a **throwaway container** (`ghcr.io/ptero-eggs/installers:debian`). This script writes to `/mnt/server/`, which becomes the persistent volume at `/home/container/`.

Here is what the installation script does:

1. **Creates the directory structure**: `logs/`, `tmp/`, `conf/nginx/`, `conf/php/`
2. **If `USER_UPLOAD=1`**: creates `www/public/` and exits — the user will upload files manually via SFTP
3. **Downloads default configs** from the GitHub repository (raw files): `nginx.conf`, `default.conf`, `php.ini`, `php-fpm.conf`, `www.conf`
4. **If `GIT_ADDRESS` is set**: clones the repository into `www/`
   - Appends `.git` to the URL if missing
   - Builds an authenticated URL if `GIT_USERNAME` + `GIT_ACCESS_TOKEN` are provided
   - Clones the branch specified by `GIT_BRANCH` (or the default branch)
   - Copies `.env.example` to `.env` if it exists
5. **If no `GIT_ADDRESS`**: creates a `www/public/index.php` with `phpinfo()` as a test page

After this step, the volume is ready. The server can now be started.

### Step 3: Every Startup (the 6-phase orchestrator)

Every time the server starts (first boot or restart), the full startup sequence runs. This is the core of the egg.

#### Entry point: `entrypoint.sh`

This script follows the **standard Pterodactyl yolks pattern**:

1. Sets the timezone (`TZ`, defaults to UTC)
2. Detects the container's internal IP address (via `ip route get 1`)
3. Changes to `/home/container`
4. Prints the PHP version to the console
5. Reads the `STARTUP` variable (set by Pterodactyl, value: `/bin/bash /start.sh`), replaces `{{VAR}}` placeholders with actual `${VAR}` values, evaluates them, and `exec`s the result

After substitution, the container runs `/bin/bash /start.sh`, replacing the entrypoint shell.

#### Orchestrator: `start.sh` — 6 phases

The orchestrator uses strict mode (`set -euo pipefail`) and registers a signal trap (`SIGINT`, `SIGTERM`) for clean shutdown of all child processes.

---

**Phase 0 — Setup**

- Reads `/etc/php_version` to detect the PHP version baked into the image
- Creates required directories: `logs/`, `tmp/sessions/`, `tmp/nginx/*`, `conf/`
- **Copies default configs** from `/etc/laravel-egg/conf/` into the volume **only if they don't already exist**. This means:
  - First startup: configs are copied from the image defaults
  - Subsequent restarts: your customized configs in `conf/` are preserved
  - To reset configs: delete `conf/` via the file manager, restart
- **Auto-tunes PHP-FPM** based on `SERVER_MEMORY` (the memory allocated to this server in the panel):
  - Formula: `max_children = (SERVER_MEMORY - 128 MB reserved) / 40 MB per worker`
  - Bounded between 2 and 50 workers
  - Also adjusts `start_servers`, `min_spare_servers`, `max_spare_servers` proportionally
  - Example: 512 MB allocated → `(512 - 128) / 40 = 9 workers`
  - Example: 2048 MB allocated → `(2048 - 128) / 40 = 48 workers`

---

**Phase 1 — Git**

Handles 4 scenarios:

| Scenario | Action |
|----------|--------|
| `www/.git` exists + `AUTO_UPDATE=1` | `git pull --ff-only` (fast-forward only, safe) |
| `www/.git` exists + `AUTO_UPDATE=0` | Skip (no changes to your code) |
| `www/` is empty + `GIT_ADDRESS` set | `git clone` (with optional branch and authentication) |
| `www/` is not empty, no `.git` | Skip (assumes manual upload) |
| No `GIT_ADDRESS` set | Skip entirely |

After this phase, ensures `www/public/` exists (needed by Nginx).

---

**Phase 2 — Dependencies**

- **Composer**: if `composer.json` exists in `www/`, runs:
  ```
  composer install --no-dev --optimize-autoloader --no-interaction
  ```
  This installs production dependencies only and optimizes the autoloader for performance.

- **NPM** (optional, only if `ENABLE_NPM=1`): if `package.json` exists:
  1. Runs `npm ci` (clean install from lock file) — falls back to `npm install` if `ci` fails
  2. Runs the build command (default: `npm run build`, customizable via `NPM_BUILD_CMD`)
  3. **Deletes `node_modules/`** after build to save disk space — only the compiled assets in `public/build/` are kept

---

**Phase 3 — Laravel Configuration**

Only runs if `www/artisan` exists (= this is a Laravel project).

1. **`.env` file sync**: the egg bridges Pterodactyl panel variables into Laravel's `.env` file:
   - If `.env` doesn't exist, copies from `.env.example` (or creates an empty one)
   - For each panel variable (APP_NAME, DB_HOST, REDIS_PORT, etc.): updates the matching line in `.env` if it exists, or appends it if it doesn't
   - This means: **if you change a variable in the Pterodactyl panel, it takes effect on the next restart**

2. **APP_KEY generation**: if the key is empty or missing, runs `php artisan key:generate`. This only happens on first boot — subsequent restarts keep the existing key.

3. **Storage symlink**: runs `php artisan storage:link` to create the `public/storage` symlink

4. **Database migrations** (optional, `ENABLE_MIGRATE=1`): runs `php artisan migrate --force`

5. **Custom Artisan commands** (optional, `CUSTOM_ARTISAN`): a comma-separated list of commands to run. Example: `db:seed, cache:clear, route:cache` — each command is run sequentially.

6. **Optimization**: runs `php artisan optimize` to cache configuration, routes, and views for production performance.

---

**Phase 4 — Background Services**

Each service is optional, launched in the background, and its PID is tracked for clean shutdown:

- **Queue worker** (`ENABLE_QUEUE=1`):
  - If `ENABLE_HORIZON=1`: starts `php artisan horizon` (Laravel Horizon dashboard + worker)
  - Otherwise: starts `php artisan queue:work --sleep=3 --tries=3 --max-time=3600`

- **Task scheduler** (`ENABLE_SCHEDULER=1`):
  - Runs a background loop that executes `php artisan schedule:run` every 60 seconds
  - This replaces the system cron entry that Laravel normally requires
  - Output goes to `logs/scheduler.log`

- **WebSocket server** (`ENABLE_WEBSOCKETS=1`):
  - Starts `php artisan reverb:start --port=<WS_PORT>` (default port: 6001)
  - Requires a secondary port allocation in Pterodactyl

---

**Phase 5 — Network Services**

- **Cloudflare Tunnel** (if `CLOUDFLARE_TOKEN` is set):
  - Starts `cloudflared tunnel run --token <TOKEN>` in the background
  - This creates a secure tunnel from Cloudflare's edge to your container
  - Cloudflare handles HTTPS publicly; the container stays on plain HTTP

---

**Phase 6 — Start Web Server**

This is the final phase — it brings the server online:

1. **PHP-FPM starts in daemon mode** (background):
   ```
   php-fpm8.4 --fpm-config /home/container/conf/php/php-fpm.conf -c /home/container/conf/php/php.ini
   ```
2. Waits 1 second, then checks that the Unix socket `/home/container/tmp/php-fpm.sock` exists
3. **Injects the Pterodactyl port** into the Nginx config: replaces `{{SERVER_PORT}}` with the actual value of `SERVER_PORT`
4. Prints **`Services successfully launched`** — this is the marker that Pterodactyl watches for (defined in `egg-laravel.json` → `config.startup.done`). When the panel sees this line, it marks the server as **Online**.
5. **Nginx starts in the foreground** with `exec nginx` (`daemon off;`). Nginx becomes PID 1 — this keeps the container alive. If Nginx stops, the container exits.

### Step 4: Runtime (serving requests)

Once online, here is how a request flows:

```
User's browser
  → Pterodactyl proxy (Wings)
    → Allocated port on the host
      → Nginx (inside container, listening on that port)
        → location / : try_files $uri $uri/ /index.php
          → location ~ \.php$ : fastcgi_pass unix socket
            → PHP-FPM (worker picks up the request)
              → Laravel (www/public/index.php → framework bootstrap → your app)
            ← PHP-FPM returns response
          ← Nginx forwards response
        ← Nginx sends response to client
```

Meanwhile, in the background:
- The **queue worker** processes queued jobs (emails, notifications, heavy tasks)
- The **scheduler** runs `artisan schedule:run` every 60 seconds for cron-like tasks
- **Reverb** handles real-time WebSocket connections
- **Cloudflared** tunnels traffic through Cloudflare's network

### Step 5: Shutdown

When the server is stopped (or receives SIGINT/SIGTERM):

1. The `cleanup()` trap in `start.sh` fires
2. Sends `kill` to all tracked background child PIDs (queue worker, scheduler, websockets, cloudflared)
3. Sends `kill` to PHP-FPM via its PID file
4. Nginx (PID 1) exits, which stops the container

On next start, the full Phase 0–6 sequence runs again. Persistent data (`www/`, `conf/`, `logs/`) is preserved in the Pterodactyl volume.

## Configuration Deep Dive

### Nginx Configuration

The Nginx setup is split into two files:

**`conf/nginx/nginx.conf`** — Main configuration:
- `daemon off;` — Nginx runs in the foreground as PID 1 (container supervisor)
- All temp/pid paths point to `/home/container/tmp/nginx/` (writable by non-root user)
- `worker_processes auto;` — Automatically matches the number of CPU cores
- `client_max_body_size 100M;` — Matches PHP's `upload_max_filesize`
- Gzip compression enabled for text, CSS, JS, JSON, XML, SVG, and WOFF2
- `server_tokens off;` — Hides the Nginx version in response headers
- Includes all vhost configs from `conf/nginx/conf.d/*.conf`

**`conf/nginx/conf.d/default.conf`** — Laravel virtual host:
- Listens on `{{SERVER_PORT}}` (replaced at startup with the Pterodactyl allocated port)
- Document root: `/home/container/www/public`
- Laravel front controller: `try_files $uri $uri/ /index.php?$query_string`
- PHP-FPM connection via **Unix socket** (`/home/container/tmp/php-fpm.sock`) — faster than TCP for same-host communication
- Static assets (CSS, JS, images, fonts) cached for 30 days with `Cache-Control: public, immutable`
- **Security rules**:
  - Blocks all dotfiles except `.well-known` (needed for ACME/SSL challenges)
  - Blocks access to `.env`, `composer.json`, `composer.lock`, `package.json`, `artisan`, `webpack.mix.js`
  - Blocks access to `storage/` and `vendor/` directories
- 404 errors are routed to `index.php` (Laravel handles its own error pages)

### PHP Configuration (php.ini)

Production-hardened settings:

| Setting | Value | Why |
|---------|-------|-----|
| `display_errors` | `Off` | Never leak error details to users in production |
| `expose_php` | `Off` | Hides `X-Powered-By: PHP` header |
| `log_errors` | `On` | Errors go to `logs/php-error.log` |
| `memory_limit` | `256M` | Per-request memory cap |
| `max_execution_time` | `60s` | Prevents runaway scripts |
| `upload_max_filesize` | `100M` | Matches Nginx `client_max_body_size` |
| `post_max_size` | `100M` | Matches upload limit |
| `open_basedir` | `/home/container:/tmp:/usr/share/php` | PHP can only access these directories (sandboxing) |
| `disable_functions` | `exec, passthru, shell_exec, system, proc_open, popen, ...` | Prevents PHP code from running system commands (multi-tenant security) |
| `session.save_path` | `/home/container/tmp/sessions` | Sessions stored in user-writable directory |

**OPcache** (bytecode cache for performance):

| Setting | Value | Why |
|---------|-------|-----|
| `opcache.enable` | `1` | Caches compiled PHP bytecode in memory |
| `opcache.validate_timestamps` | `0` | Never checks if files changed on disk — `artisan optimize` handles cache invalidation. **If you edit PHP files via SFTP, you must restart the server for changes to take effect.** |
| `opcache.jit_buffer_size` | `64M` | Enables the JIT compiler for additional performance |
| `opcache.memory_consumption` | `128M` | Memory allocated for cached bytecodes |
| `opcache.max_accelerated_files` | `10000` | Max number of PHP files to cache |
| `realpath_cache_size` | `4096K` | Speeds up Composer autoloader path resolution |

### PHP-FPM Configuration

Split into two files:

**`conf/php/php-fpm.conf`** — Global settings:
- `daemonize = yes` — PHP-FPM runs in the background (Nginx is the foreground process)
- PID file at `/home/container/tmp/php-fpm.pid`
- Error log at `logs/php-fpm-error.log`
- Includes pool configs from `conf/php/pool.d/*.conf`

**`conf/php/pool.d/www.conf`** — Worker pool:
- Runs as user `container`
- Unix socket at `/home/container/tmp/php-fpm.sock` with mode `0666`
- No `listen.owner`/`listen.group` — Pterodactyl drops `CAP_CHOWN` from containers, so these would cause a startup failure
- `pm = dynamic` — Workers scale up and down based on load
- `pm.max_children` — Auto-tuned by `start.sh` based on allocated memory (see Phase 0)
- `pm.max_requests = 500` — Each worker restarts after 500 requests to prevent memory leaks
- `clear_env = no` — **Critical**: passes Pterodactyl environment variables through to PHP workers (without this, `$_ENV` and `env()` would be empty)
- `request_terminate_timeout = 300s` — Kills requests that run longer than 5 minutes
- `request_slowlog_timeout = 10s` — Logs requests taking over 10 seconds to `logs/php-fpm-slow.log`
- Status endpoint at `/fpm-status` and health check at `/fpm-ping`

## Variables Reference

All variables are configurable from the Pterodactyl panel by the server owner.

### Git Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `GIT_ADDRESS` | — | HTTPS URL of the Git repository |
| `GIT_BRANCH` | — | Branch to clone (empty = default branch) |
| `GIT_USERNAME` | — | Username for private repos |
| `GIT_ACCESS_TOKEN` | — | Personal Access Token for private repos |
| `AUTO_UPDATE` | `0` | Pull latest changes on each startup (`1` = enabled) |

### Laravel Core

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_NAME` | `Laravel` | Application name |
| `APP_ENV` | `production` | Environment (production, staging, local) |
| `APP_DEBUG` | `false` | Debug mode — **never enable in production** |
| `APP_URL` | `http://localhost` | Public URL of the application |
| `APP_KEY` | — | Encryption key (auto-generated on first start if empty) |

### Database

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_CONNECTION` | `mysql` | Driver (mysql, pgsql, sqlite, sqlsrv) |
| `DB_HOST` | `127.0.0.1` | Database server hostname or IP |
| `DB_PORT` | `3306` | Database server port |
| `DB_DATABASE` | `laravel` | Database name |
| `DB_USERNAME` | `root` | Database user |
| `DB_PASSWORD` | — | Database password |

### Redis

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_HOST` | `127.0.0.1` | Redis server hostname or IP |
| `REDIS_PORT` | `6379` | Redis server port |
| `REDIS_PASSWORD` | — | Redis password (empty if no auth) |

### Build

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_NPM` | `0` | Run NPM install + build on startup (`1` = enabled) |
| `NPM_BUILD_CMD` | `npm run build` | Custom build command |
| `ENABLE_MIGRATE` | `0` | Run database migrations on startup (`1` = enabled) |

### Background Services

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_QUEUE` | `0` | Start a background queue worker (`1` = enabled) |
| `QUEUE_CONNECTION` | `sync` | Queue driver (sync, database, redis, sqs) |
| `ENABLE_HORIZON` | `0` | Use Laravel Horizon instead of default worker (requires `laravel/horizon`) |
| `ENABLE_SCHEDULER` | `0` | Run the task scheduler in background (`1` = enabled) |
| `ENABLE_WEBSOCKETS` | `0` | Start Laravel Reverb WebSocket server (requires `laravel/reverb`) |

### Cloudflare Tunnel

| Variable | Default | Description |
|----------|---------|-------------|
| `CLOUDFLARE_TOKEN` | — | Cloudflare Tunnel token (leave empty to disable) |

To use Cloudflare Tunnel:

1. Go to [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) -> Networks -> Tunnels
2. Create a tunnel and copy the token
3. Paste the token in `CLOUDFLARE_TOKEN`
4. In the tunnel config, set the service to `http://localhost:<your-allocated-port>`
5. Restart the server — cloudflared starts automatically in the background

This lets Cloudflare handle HTTPS publicly while the container stays on plain HTTP. No certificate management needed.

### SSL (Let's Encrypt)

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_SSL` | `0` | Enable Let's Encrypt SSL |
| `CERTBOT_EMAIL` | — | Email for certificate registration |
| `CERTBOT_DOMAIN` | — | Domain for the certificate |
| `CERTBOT_STAGING` | `0` | Use staging server for testing |

### Advanced

| Variable | Default | Description |
|----------|---------|-------------|
| `USER_UPLOAD` | `0` | Skip git clone during install (upload files via SFTP instead) |
| `CUSTOM_ARTISAN` | — | Comma-separated artisan commands to run on startup (e.g., `db:seed, cache:clear`) |
| `WS_PORT` | `6001` | WebSocket server port (needs a secondary port allocation in Pterodactyl) |

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

### Laravel + Cloudflare Tunnel (HTTPS)

1. Configure as above
2. Create a Cloudflare Tunnel in the Zero Trust dashboard
3. Set `CLOUDFLARE_TOKEN` to the tunnel token
4. Configure the tunnel service URL: `http://localhost:<allocated-port>`
5. Point your domain DNS to the tunnel
6. Start the server — accessible via HTTPS through Cloudflare

### Laravel + Scheduled Tasks

1. Configure as above
2. Set `ENABLE_SCHEDULER` to `1`
3. Define your scheduled tasks in `app/Console/Kernel.php` (or `routes/console.php` for Laravel 11+)

### Manual Upload (no Git)

1. Set `USER_UPLOAD` to `1`
2. Install the server (creates empty `www/public/`)
3. Upload your Laravel project via SFTP into `www/`
4. Start the server

## Design Decisions and Good-to-Know

1. **Nginx is PID 1, not PHP-FPM.** Nginx runs in the foreground (`daemon off;`) and keeps the container alive. PHP-FPM is daemonized in the background. If Nginx crashes, the container exits — Pterodactyl will detect this and mark the server as offline.

2. **`clear_env = no` in PHP-FPM is critical.** Without this, PHP workers would not see environment variables from Pterodactyl (DB_HOST, APP_KEY, etc.), and `env()` calls in Laravel would return null.

3. **OPcache does not check file timestamps.** `opcache.validate_timestamps = 0` means PHP never re-reads files from disk once they're cached. The `php artisan optimize` command handles cache warming. **If you edit PHP files via SFTP, you must restart the server for changes to take effect.**

4. **Configs persist across restarts but not reinstalls.** Config files in `conf/` are only copied from the image defaults if they don't already exist. If you customize them, your changes survive restarts. If the Docker image ships new defaults, your old configs won't be overwritten. To get fresh configs: delete the `conf/` directory and restart.

5. **The port is injected via `sed` at each startup.** The `{{SERVER_PORT}}` placeholder in `default.conf` is replaced with the actual port. If you change the port allocation in the panel, restart the server and it will pick up the new port automatically.

6. **`node_modules` is deleted after NPM build.** Only the compiled assets (typically `public/build/`) are kept. This saves significant disk space on the Pterodactyl volume.

7. **Dangerous PHP functions are disabled.** `exec`, `passthru`, `shell_exec`, `system`, `proc_open`, `popen` are all disabled in `php.ini`. This prevents user-uploaded PHP code from running system commands — important for multi-tenant Pterodactyl setups. If your app needs any of these functions, edit `conf/php/php.ini` and restart.

8. **The `.env` file is re-synced from panel variables on every startup.** If an admin changes a variable in the Pterodactyl panel (e.g., DB_HOST), the change is written to `.env` on the next restart. Variables already in `.env` are updated in-place; new variables are appended.

9. **APP_KEY is generated only once.** The key generation only runs if APP_KEY is empty or missing. Once generated, it persists in `.env` across restarts. Never change this key in production — it would invalidate all encrypted data.

10. **The scheduler replaces system cron.** Instead of requiring a cron entry (`* * * * * php artisan schedule:run`), the egg runs a background loop that calls `schedule:run` every 60 seconds. Same result, no cron needed.

## Troubleshooting

### Server shows "502 Bad Gateway"
- PHP-FPM may have failed to start. Check `logs/php-fpm-error.log`
- Verify the PHP-FPM socket exists: the startup log should show "Starting PHP-FPM"

### PHP-FPM fails with "failed to chown() the socket"
- This means the pool config has `listen.owner`/`listen.group` directives
- Pterodactyl drops `CAP_CHOWN` from containers
- Fix: remove those directives from `conf/php/pool.d/www.conf` (or reinstall the server to get fresh configs)

### Site not accessible / connection refused
- Check that Nginx is listening on the correct port in the startup logs ("Nginx will listen on port XXXX")
- The port must match the allocation in the Pterodactyl panel
- If the port is wrong, delete `conf/nginx/conf.d/default.conf` via the file manager and restart

### Browser forces HTTPS redirect
- This is a browser-side HSTS cache issue, not the server
- Chrome: go to `chrome://net-internals/#hsts` -> Delete domain security policies
- Or use incognito mode as a workaround

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

### Config changes not applying after image update
- Configs in `conf/` are persistent and copied only on first run
- To reset: delete the `conf/` directory via the panel file manager, then restart
- Or reinstall the server from the panel

### PHP file changes via SFTP not taking effect
- OPcache has `validate_timestamps = 0` — cached bytecode is never re-checked
- Restart the server to clear the OPcache and load the new files

## Wings Security Recommendations

If you host multiple users on the same Pterodactyl node, disable inter-container communication:

In `/etc/pterodactyl/config.yml`:
```yaml
docker:
  network:
    enable_icc: false
```

Then apply the change:
```bash
systemctl stop wings
docker network rm pterodactyl_nw
systemctl start wings
```

This prevents containers from scanning or accessing each other on the Docker network while still allowing internet access (needed for Composer, Git, NPM).

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

Test with Pterodactyl-like environment:

```bash
docker run --rm -e STARTUP="/bin/bash /start.sh" -e SERVER_PORT=8080 -p 8080:8080 laravel-egg:8.4
```

## License

MIT — See [LICENSE](LICENSE) for details.

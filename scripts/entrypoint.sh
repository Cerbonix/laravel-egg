#!/bin/bash

# =============================================================================
# Pterodactyl entrypoint — Standard yolks pattern
# Substitutes {{VAR}} → ${VAR}, resolves variables, then exec the command
# =============================================================================

# Default timezone to UTC
TZ=${TZ:-UTC}
export TZ

# Detect internal container IP for Pterodactyl networking
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Switch to container working directory
cd /home/container || exit 1

# Print PHP version
printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mphp -v\n"
php -v | head -1

# Convert {{VARIABLE}} placeholders to ${VARIABLE} and resolve them
PARSED=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g' | eval echo "$(cat -)")

# Display the command and execute it, replacing this shell process
printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0m%s\n" "$PARSED"
# shellcheck disable=SC2086
exec env ${PARSED}

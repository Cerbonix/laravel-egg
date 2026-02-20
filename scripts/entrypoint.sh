#!/bin/bash
# =============================================================================
# Pterodactyl entrypoint — Variable substitution + startup exec
# Converts {{VAR}} template syntax to shell ${VAR} and executes the command
# Pattern matches yolks/entrypoint.sh used across Pterodactyl eggs
# =============================================================================

# Detect internal container IP for Pterodactyl networking
INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2); exit}')
export INTERNAL_IP

# Replace Pterodactyl {{VAR}} placeholders with actual environment values
# The panel sends startup commands with {{VARIABLE}} syntax
MODIFIED_STARTUP=$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')

echo "-------------------------------------------------------"
echo "Laravel Egg — Pterodactyl"
echo "-------------------------------------------------------"
echo "PHP Version: $(cat /etc/php_version)"
echo "Internal IP: ${INTERNAL_IP}"
echo "Startup Command: ${MODIFIED_STARTUP}"
echo "-------------------------------------------------------"

# Evaluate variable references and execute the startup command
eval "${MODIFIED_STARTUP}"

#!/usr/bin/env fish

# Enable optional debug settings for Qt
# set -x QT_DEBUG_PLUGINS 1
# set -e QT_QPA_PLATFORM_PLUGIN_PATH

# Activate Python virtual environment
source ./.venv/bin/activate.fish

# Run the application
echo "Launching application..."
if not sudo -E python3 ./hcli.py
    echo "Application exited with an error."
end

# Always deactivate the virtual environment
deactivate
echo "Virtual environment deactivated."


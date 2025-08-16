#!/usr/bin/env bash

# Activate Python virtual environment
source ./.venv/bin/activate

# Run the application
echo "Launching application..."
sudo -E python3 ./hcli.py
exit_code=$?

# Always deactivate the virtual environment
deactivate
echo "Virtual environment deactivated."

# Exit with the same status code as the application
exit $exit_code


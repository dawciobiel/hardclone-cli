#!/usr/bin/fish

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


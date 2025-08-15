#!/usr/bin/env fish

# Exit on first error
function on_error
    echo "❌ Error occurred. Exiting."
    exit 1
end
trap on_error ERR

echo "🔧 Checking Python virtual environment (.venv)..."

# Create the virtual environment if it doesn't exist
if not test -d ".venv"
    echo "📦 Creating a new virtual environment (.venv)..."
    python3 -m venv .venv
else
    echo "✅ Virtual environment already exists – skipping creation."
end

# Check if pip exists in the virtual environment
if not test -x ".venv/bin/pip"
    echo "❌ Error: 'pip' not found in the virtual environment."
    exit 1
end

# Activate the environment (only within this script)
echo "🧪 Activating the virtual environment..."
source .venv/bin/activate.fish

# Install dependencies
echo "📥 Installing dependencies from requirements.txt..."
pip install -r requirements.txt

# Deactivate the environment
echo "🔌 Deactivating the virtual environment..."
deactivate

echo "✅ Environment setup complete!"


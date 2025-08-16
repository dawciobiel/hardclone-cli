# #!/usr/bin/fish

# Exit on first error
function fish_posterror --on-event fish_posterror
    echo "❌ Error occurred. Exiting."
    exit 1
end

echo "🔧 Checking Python virtual environment (.venv)..."

# Create the virtual environment if it doesn't exist
if not test -d ".venv"
    echo "📦 Creating a new virtual environment (.venv)..."
    python3 -m venv .venv
else
    echo "✅ Virtual environment already exists – skipping creation."
end

# Decide which pip to use
set pip_path ".venv/bin/pip"

if not test -x $pip_path
    echo "⚠️  'pip' not found in the virtual environment. Falling back to system pip."
    set pip_path "python3 -m pip"
end

# Activate the environment (only within this script)
echo "🧪 Activating the virtual environment..."
if test -f ".venv/bin/activate.fish"
    source .venv/bin/activate.fish
else
    echo "⚠️  No activate.fish found in .venv – continuing without activation."
end

# Install dependencies
echo "📥 Installing dependencies from requirements.txt..."
$pip_path install -r requirements.txt

# Deactivate the environment (only if it was activated)
if functions -q deactivate
    echo "🔌 Deactivating the virtual environment..."
    deactivate
end

echo "✅ Environment setup complete!"

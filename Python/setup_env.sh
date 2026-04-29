#!/bin/bash
set -e

# Base directory for the environment
ENV_DIR="$1"

if [ -z "$ENV_DIR" ]; then
    echo "Usage: $0 <path_to_env_dir>"
    exit 1
fi

if [ ! -d "$ENV_DIR" ]; then
    echo "Creating virtual environment at $ENV_DIR..."
    python3 -m venv "$ENV_DIR"
fi

source "$ENV_DIR/bin/activate"

# Install required packages
pip install --upgrade pip
pip install -r "$(dirname "$0")/requirements.txt"

echo "Environment setup complete."

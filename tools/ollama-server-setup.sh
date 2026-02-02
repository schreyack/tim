#!/bin/bash
#
# Ollama Server Setup for Tim Loop LLM-as-Judge
#
# Run this on your LLM server
# Creates a dedicated user and sets up Ollama as a service.
#
# Usage:
#   scp ollama-server-setup.sh user@your-server:~
#   ssh user@your-server
#   sudo bash ollama-server-setup.sh
#

set -e

# Configuration
OLLAMA_USER="ollama-tim"
OLLAMA_PORT="11434"
OLLAMA_HOST="0.0.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[!]${NC} $1"; exit 1; }

# Check root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
fi

log "Setting up Ollama for Tim Loop LLM-as-Judge"
echo ""

# Step 1: Create dedicated user
log "Creating dedicated user: $OLLAMA_USER"
if id "$OLLAMA_USER" &>/dev/null; then
    warn "User $OLLAMA_USER already exists"
else
    useradd --system --shell /bin/false --create-home --home-dir /home/$OLLAMA_USER $OLLAMA_USER
    log "Created user $OLLAMA_USER"
fi

# Step 2: Install Ollama
log "Installing Ollama..."
if command -v ollama &>/dev/null; then
    warn "Ollama already installed: $(ollama --version)"
else
    curl -fsSL https://ollama.com/install.sh | sh
    log "Ollama installed"
fi

# Step 3: Create systemd service
log "Creating systemd service..."
cat > /etc/systemd/system/ollama-tim.service << EOF
[Unit]
Description=Ollama LLM Server for Tim Loop
After=network-online.target

[Service]
Type=simple
User=$OLLAMA_USER
Group=$OLLAMA_USER
Environment="OLLAMA_HOST=$OLLAMA_HOST:$OLLAMA_PORT"
Environment="OLLAMA_MODELS=/home/$OLLAMA_USER/.ollama/models"
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=3

# Security hardening
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# Step 4: Set up directories
log "Setting up directories..."
mkdir -p /home/$OLLAMA_USER/.ollama/models
chown -R $OLLAMA_USER:$OLLAMA_USER /home/$OLLAMA_USER/.ollama

# Step 5: Enable and start service
log "Enabling and starting service..."
systemctl daemon-reload
systemctl enable ollama-tim
systemctl start ollama-tim

# Wait for service to be ready
sleep 3

# Step 6: Check status
if systemctl is-active --quiet ollama-tim; then
    log "Service is running!"
else
    error "Service failed to start. Check: journalctl -u ollama-tim"
fi

echo ""
log "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Pull a model (as the ollama-tim user):"
echo "     sudo -u $OLLAMA_USER ollama pull llama3.1:8b"
echo ""
echo "  2. Test the API:"
echo "     curl http://localhost:$OLLAMA_PORT/api/tags"
echo ""
echo "  3. On your dev machine, set:"
echo "     export TIM_LLM_JUDGE_ENABLED=true"
echo "     export TIM_LLM_SERVER=http://$(hostname -I | awk '{print $1}'):$OLLAMA_PORT"
echo "     export TIM_LLM_MODEL=llama3.1:8b"
echo ""
echo "Model recommendations by server RAM:"
echo "  8GB RAM:  llama3.2:3b (fastest, decent quality)"
echo "  16GB RAM: llama3.1:8b (good balance)"
echo "  32GB RAM: llama3.1:8b or mistral:7b"
echo "  64GB+ RAM: llama3.1:70b (best quality, slow without GPU)"
echo ""
echo "If you have a GPU, larger models will be much faster."

#!/bin/bash
# =============================================================================
# Kimi K2.5 POC - Start Script
# =============================================================================
# This script starts the Kimi K2.5 POC instance and configures firewall rules
# for your current IP address.
#
# Usage: ./start-poc.sh [PROJECT_ID] [ZONE] [INSTANCE_NAME]
# =============================================================================

set -e

# Configuration (can be overridden via environment variables or arguments)
PROJECT_ID="${1:-${PROJECT_ID:-}}"
ZONE="${2:-${ZONE:-us-central1-a}}"
INSTANCE_NAME="${3:-${INSTANCE_NAME:-kimi-k25-poc}}"
API_PORT="${API_PORT:-8000}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# Validation
# =============================================================================

if [ -z "$PROJECT_ID" ]; then
    log_error "PROJECT_ID is required. Set it as an environment variable or pass as first argument."
    echo "Usage: ./start-poc.sh [PROJECT_ID] [ZONE] [INSTANCE_NAME]"
    echo ""
    echo "Example:"
    echo "  export PROJECT_ID=my-gcp-project"
    echo "  ./start-poc.sh"
    echo ""
    echo "Or:"
    echo "  ./start-poc.sh my-gcp-project us-central1-a kimi-k25-poc"
    exit 1
fi

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI is not installed. Please install it first:"
    echo "  https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    log_error "Not authenticated with gcloud. Please run:"
    echo "  gcloud auth login"
    exit 1
fi

# Set project
gcloud config set project "$PROJECT_ID" > /dev/null 2>&1

# =============================================================================
# Get Current IP
# =============================================================================

log_info "Detecting your current IP address..."
CURRENT_IP=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null || echo "")

if [ -z "$CURRENT_IP" ]; then
    log_warning "Could not detect your IP address. Firewall rules may need manual configuration."
    CURRENT_IP="0.0.0.0/0"
else
    log_success "Detected IP: $CURRENT_IP"
    CURRENT_IP="$CURRENT_IP/32"
fi

# =============================================================================
# Configure Firewall Rules
# =============================================================================

log_info "Configuring firewall rules..."

# SSH access
FIREWALL_RULE_SSH="${INSTANCE_NAME}-allow-ssh-$(date +%s)"
if gcloud compute firewall-rules create "$FIREWALL_RULE_SSH" \
    --allow tcp:22 \
    --source-ranges="$CURRENT_IP" \
    --target-tags="$INSTANCE_NAME" \
    --description="Temporary SSH access for Kimi K2.5 POC" \
    --quiet 2>/dev/null; then
    log_success "Created SSH firewall rule: $FIREWALL_RULE_SSH"
else
    log_warning "Could not create SSH firewall rule (may already exist)"
fi

# API access
FIREWALL_RULE_API="${INSTANCE_NAME}-allow-api-$(date +%s)"
if gcloud compute firewall-rules create "$FIREWALL_RULE_API" \
    --allow "tcp:$API_PORT" \
    --source-ranges="$CURRENT_IP" \
    --target-tags="$INSTANCE_NAME" \
    --description="Temporary API access for Kimi K2.5 POC" \
    --quiet 2>/dev/null; then
    log_success "Created API firewall rule: $FIREWALL_RULE_API"
else
    log_warning "Could not create API firewall rule (may already exist)"
fi

# =============================================================================
# Start Instance
# =============================================================================

log_info "Starting instance $INSTANCE_NAME in zone $ZONE..."

if ! gcloud compute instances start "$INSTANCE_NAME" --zone="$ZONE" --quiet; then
    log_error "Failed to start instance. Please check:"
    echo "  1. Instance exists: gcloud compute instances list --filter=name:$INSTANCE_NAME"
    echo "  2. You have permission to start instances"
    echo "  3. Zone is correct: $ZONE"
    exit 1
fi

log_success "Instance started successfully!"

# =============================================================================
# Wait for Instance to be Ready
# =============================================================================

log_info "Waiting for instance to be ready (this may take 1-2 minutes)..."

MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    # Check if instance is running
    STATUS=$(gcloud compute instances describe "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --format="value(status)" 2>/dev/null || echo "UNKNOWN")
    
    if [ "$STATUS" = "RUNNING" ]; then
        # Try to get external IP
        EXTERNAL_IP=$(gcloud compute instances describe "$INSTANCE_NAME" \
            --zone="$ZONE" \
            --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "")
        
        if [ -n "$EXTERNAL_IP" ]; then
            log_success "Instance is running with external IP: $EXTERNAL_IP"
            break
        fi
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo -n "."
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    log_error "Timeout waiting for instance to be ready"
    exit 1
fi

echo ""  # New line after dots

# =============================================================================
# Wait for API to be Ready
# =============================================================================

log_info "Waiting for vLLM API to be ready (this may take 5-10 minutes for first startup)..."
log_info "The model needs to be downloaded and loaded into GPU memory."

API_URL="http://$EXTERNAL_IP:$API_PORT"
MAX_RETRIES=60
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s "$API_URL/health" > /dev/null 2>&1; then
        log_success "vLLM API is ready!"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    
    if [ $((RETRY_COUNT % 12)) -eq 0 ]; then
        echo ""  # New line every minute
        log_info "Still waiting... ($((RETRY_COUNT * 5 / 60)) minutes elapsed)"
    else
        echo -n "."
    fi
    
    sleep 5
done

echo ""  # New line after dots

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    log_warning "Timeout waiting for API. The instance is running but the API may still be starting."
    log_info "You can check the logs later with: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='docker logs kimi-k25-server'"
fi

# =============================================================================
# Display Connection Information
# =============================================================================

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    Kimi K2.5 POC - Instance Ready                            ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Instance Name:     $INSTANCE_NAME"
echo "  Zone:              $ZONE"
echo "  External IP:       $EXTERNAL_IP"
echo ""
echo "  API Endpoint:      http://$EXTERNAL_IP:$API_PORT/v1"
echo "  Health Check:      http://$EXTERNAL_IP:$API_PORT/health"
echo "  Docs (if enabled): http://$EXTERNAL_IP:$API_PORT/docs"
echo ""
echo "  SSH Command:       gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
echo ""
echo "  Estimated Cost:    ~\$16/hour (On-Demand) or ~\$5/hour (Spot)"
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                              Quick Test                                      ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Test the API with curl:"
echo ""
echo "  curl http://$EXTERNAL_IP:$API_PORT/v1/models"
echo ""
echo "  curl http://$EXTERNAL_IP:$API_PORT/v1/chat/completions \\"
echo "    -H \"Content-Type: application/json\" \\"
echo "    -d '{\"model\": \"moonshotai/Kimi-K2.5\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}]}'"
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                           Important Notes                                    ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  1. STOP the instance when not in use to avoid charges:"
echo "     ./stop-poc.sh $PROJECT_ID $ZONE $INSTANCE_NAME"
echo ""
echo "  2. First startup may take 5-10 minutes to download the model."
echo ""
echo "  3. Check container logs:"
echo "     gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='docker logs -f kimi-k25-server'"
echo ""
echo "  4. Your IP ($CURRENT_IP) has been added to firewall rules for access."
echo ""
echo "  💰 Current running cost: ~\$16/hour (On-Demand) or ~\$5/hour (Spot)"
echo ""

# Save connection info to file
CONNECTION_INFO_FILE="${INSTANCE_NAME}-connection-info.txt"
cat > "$CONNECTION_INFO_FILE" << EOF
Kimi K2.5 POC - Connection Information
======================================
Generated: $(date)

Instance:     $INSTANCE_NAME
Zone:         $ZONE
Project:      $PROJECT_ID
External IP:  $EXTERNAL_IP
API Port:     $API_PORT

Endpoints:
  API:      http://$EXTERNAL_IP:$API_PORT/v1
  Health:   http://$EXTERNAL_IP:$API_PORT/health

Commands:
  SSH:      gcloud compute ssh $INSTANCE_NAME --zone=$ZONE
  Stop:     ./stop-poc.sh $PROJECT_ID $ZONE $INSTANCE_NAME
  Logs:     gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='docker logs -f kimi-k25-server'

Cost: ~\$16/hour (On-Demand) or ~\$5/hour (Spot)
EOF

log_info "Connection info saved to: $CONNECTION_INFO_FILE"

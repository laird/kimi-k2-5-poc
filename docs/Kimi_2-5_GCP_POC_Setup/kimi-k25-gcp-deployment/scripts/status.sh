#!/bin/bash
# =============================================================================
# Kimi K2.5 POC - Status Check Script
# =============================================================================
# This script checks the status of the Kimi K2.5 deployment including:
#   - Instance status
#   - GPU utilization
#   - API health
#   - Container logs
#
# Usage: ./status.sh [PROJECT_ID] [ZONE] [INSTANCE_NAME]
# =============================================================================

set -e

# Configuration
PROJECT_ID="${1:-${PROJECT_ID:-}}"
ZONE="${2:-${ZONE:-us-central1-a}}"
INSTANCE_NAME="${3:-${INSTANCE_NAME:-kimi-k25-poc}}"
API_PORT="${API_PORT:-8000}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_header() { echo -e "${CYAN}$1${NC}"; }

# Validation
if [ -z "$PROJECT_ID" ]; then
    log_error "PROJECT_ID is required."
    echo "Usage: ./status.sh [PROJECT_ID] [ZONE] [INSTANCE_NAME]"
    exit 1
fi

gcloud config set project "$PROJECT_ID" > /dev/null 2>&1

echo ""
log_header "╔══════════════════════════════════════════════════════════════════════════════╗"
log_header "║                    Kimi K2.5 POC - Status Check                              ║"
log_header "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# Instance Status
# =============================================================================
log_info "Checking instance status..."

INSTANCE_INFO=$(gcloud compute instances describe "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --format="table[box](
        name,
        status,
        machineType.basename(),
        networkInterfaces[0].accessConfigs[0].natIP,
        creationTimestamp
    )" 2>/dev/null || echo "")

if [ -z "$INSTANCE_INFO" ]; then
    log_error "Instance $INSTANCE_NAME not found in zone $ZONE"
    exit 1
fi

echo "$INSTANCE_INFO"
echo ""

# Get detailed status
STATUS=$(gcloud compute instances describe "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --format="value(status)" 2>/dev/null || echo "UNKNOWN")

EXTERNAL_IP=$(gcloud compute instances describe "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "")

if [ "$STATUS" != "RUNNING" ]; then
    log_warning "Instance is not running (status: $STATUS)"
    log_info "To start the instance, run: ./start-poc.sh $PROJECT_ID $ZONE $INSTANCE_NAME"
    exit 0
fi

log_success "Instance is running"
echo "  External IP: $EXTERNAL_IP"
echo ""

# =============================================================================
# API Health Check
# =============================================================================
log_info "Checking API health..."

API_URL="http://$EXTERNAL_IP:$API_PORT"

if curl -s "$API_URL/health" > /dev/null 2>&1; then
    log_success "API is healthy"
    
    # Get available models
    MODELS=$(curl -s "$API_URL/v1/models" 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "Could not parse response")
    echo "  Available models:"
    echo "$MODELS" | grep -E '"id":' | head -5 | sed 's/^/    /'
else
    log_warning "API is not responding or still starting up"
    log_info "If the instance was just started, the model may still be loading (5-10 minutes)"
fi
echo ""

# =============================================================================
# GPU Status (via SSH)
# =============================================================================
log_info "Checking GPU status..."

GPU_INFO=$(gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --command='nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw --format=csv' 2>/dev/null || echo "")

if [ -n "$GPU_INFO" ]; then
    echo "  GPU Status:"
    echo "$GPU_INFO" | sed 's/^/    /'
else
    log_warning "Could not retrieve GPU information"
fi
echo ""

# =============================================================================
# Container Status
# =============================================================================
log_info "Checking container status..."

CONTAINER_STATUS=$(gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --command='docker ps --filter name=kimi-k25-server --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"' 2>/dev/null || echo "")

if [ -n "$CONTAINER_STATUS" ]; then
    echo "  Container Status:"
    echo "$CONTAINER_STATUS" | sed 's/^/    /'
else
    log_warning "Container information not available"
fi
echo ""

# =============================================================================
# Recent Logs
# =============================================================================
log_info "Recent container logs (last 20 lines):"
echo ""

LOGS=$(gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --command='docker logs --tail 20 kimi-k25-server 2>&1' 2>/dev/null || echo "")

if [ -n "$LOGS" ]; then
    echo "$LOGS" | sed 's/^/  /'
else
    log_warning "Could not retrieve logs"
fi
echo ""

# =============================================================================
# Cost Information
# =============================================================================
log_header "╔══════════════════════════════════════════════════════════════════════════════╗"
log_header "║                              Cost Information                                ║"
log_header "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Current running cost: ~\$16/hour (On-Demand) or ~\$5/hour (Spot)"
echo "  Storage cost (always): ~\$97/month"
echo ""

# Calculate uptime if connection info exists
if [ -f "${INSTANCE_NAME}-connection-info.txt" ]; then
    START_TIME=$(stat -c %Y "${INSTANCE_NAME}-connection-info.txt" 2>/dev/null || echo "0")
    if [ "$START_TIME" != "0" ]; then
        CURRENT_TIME=$(date +%s)
        ELAPSED_SECONDS=$((CURRENT_TIME - START_TIME))
        ELAPSED_HOURS=$((ELAPSED_SECONDS / 3600))
        ELAPSED_MINUTES=$(((ELAPSED_SECONDS % 3600) / 60))
        
        echo "  Session uptime: ${ELAPSED_HOURS}h ${ELAPSED_MINUTES}m"
        echo ""
    fi
fi

# =============================================================================
# Quick Actions
# =============================================================================
log_header "╔══════════════════════════════════════════════════════════════════════════════╗"
log_header "║                             Quick Actions                                    ║"
log_header "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  View full logs:     gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='docker logs -f kimi-k25-server'"
echo "  SSH into instance:  gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
echo "  Stop instance:      ./stop-poc.sh $PROJECT_ID $ZONE $INSTANCE_NAME"
echo "  Test API:           curl http://$EXTERNAL_IP:$API_PORT/v1/models"
echo ""

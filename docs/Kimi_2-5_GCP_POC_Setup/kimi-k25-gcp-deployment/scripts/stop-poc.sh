#!/bin/bash
# =============================================================================
# Kimi K2.5 POC - Stop Script
# =============================================================================
# This script stops the Kimi K2.5 POC instance to halt compute billing.
# Storage charges will continue for the persistent disk.
#
# Usage: ./stop-poc.sh [PROJECT_ID] [ZONE] [INSTANCE_NAME]
# =============================================================================

set -e

# Configuration (can be overridden via environment variables or arguments)
PROJECT_ID="${1:-${PROJECT_ID:-}}"
ZONE="${2:-${ZONE:-us-central1-a}}"
INSTANCE_NAME="${3:-${INSTANCE_NAME:-kimi-k25-poc}}"

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
    echo "Usage: ./stop-poc.sh [PROJECT_ID] [ZONE] [INSTANCE_NAME]"
    echo ""
    echo "Example:"
    echo "  export PROJECT_ID=my-gcp-project"
    echo "  ./stop-poc.sh"
    echo ""
    echo "Or:"
    echo "  ./stop-poc.sh my-gcp-project us-central1-a kimi-k25-poc"
    exit 1
fi

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI is not installed. Please install it first:"
    echo "  https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Set project
gcloud config set project "$PROJECT_ID" > /dev/null 2>&1

# =============================================================================
# Get Instance Status
# =============================================================================

log_info "Checking instance status..."

INSTANCE_STATUS=$(gcloud compute instances describe "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --format="value(status)" 2>/dev/null || echo "NOT_FOUND")

if [ "$INSTANCE_STATUS" = "NOT_FOUND" ]; then
    log_error "Instance $INSTANCE_NAME not found in zone $ZONE"
    exit 1
fi

if [ "$INSTANCE_STATUS" = "TERMINATED" ] || [ "$INSTANCE_STATUS" = "STOPPED" ]; then
    log_success "Instance is already stopped (status: $INSTANCE_STATUS)"
    
    # Still clean up firewall rules
    log_info "Cleaning up firewall rules..."
    
    # Find and delete firewall rules created by start script
    FIREWALL_RULES=$(gcloud compute firewall-rules list \
        --filter="targetTags:$INSTANCE_NAME" \
        --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$FIREWALL_RULES" ]; then
        for rule in $FIREWALL_RULES; do
            if gcloud compute firewall-rules delete "$rule" --quiet 2>/dev/null; then
                log_success "Deleted firewall rule: $rule"
            fi
        done
    fi
    
    echo ""
    log_info "Instance is already stopped. No compute charges are accruing."
    echo "  Note: Storage charges (~\$80/month for 1TB SSD) continue for the persistent disk."
    exit 0
fi

log_info "Instance status: $INSTANCE_STATUS"

# =============================================================================
# Confirm Shutdown (Optional)
# =============================================================================

if [ -z "$SKIP_CONFIRM" ]; then
    echo ""
    echo "This will stop instance '$INSTANCE_NAME' in zone '$ZONE'."
    echo ""
    read -p "Are you sure? (y/N) " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Shutdown cancelled."
        exit 0
    fi
fi

# =============================================================================
# Stop Instance
# =============================================================================

log_info "Stopping instance $INSTANCE_NAME..."

if ! gcloud compute instances stop "$INSTANCE_NAME" --zone="$ZONE" --quiet; then
    log_error "Failed to stop instance. Please check:"
    echo "  1. You have permission to stop instances"
    echo "  2. The instance is not in a failed state"
    exit 1
fi

log_success "Instance stopped successfully!"

# =============================================================================
# Clean Up Firewall Rules
# =============================================================================

log_info "Cleaning up firewall rules..."

# Find and delete firewall rules created by start script
FIREWALL_RULES=$(gcloud compute firewall-rules list \
    --filter="targetTags:$INSTANCE_NAME" \
    --format="value(name)" 2>/dev/null || true)

if [ -n "$FIREWALL_RULES" ]; then
    for rule in $FIREWALL_RULES; do
        if gcloud compute firewall-rules delete "$rule" --quiet 2>/dev/null; then
            log_success "Deleted firewall rule: $rule"
        fi
    done
else
    log_info "No firewall rules to clean up"
fi

# =============================================================================
# Display Cost Information
# =============================================================================

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    Kimi K2.5 POC - Instance Stopped                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Instance Name:     $INSTANCE_NAME"
echo "  Zone:              $ZONE"
echo "  Status:            STOPPED"
echo ""
echo "  ✅ Compute billing has been halted."
echo ""
echo "  💾 Storage charges continue:"
echo "     - Boot disk (200GB SSD):     ~\$17/month"
echo "     - Model disk (1TB SSD):      ~\$80/month"
echo "     - Total storage:             ~\$97/month"
echo ""
echo "  🚀 To restart the instance, run:"
echo "     ./start-poc.sh $PROJECT_ID $ZONE $INSTANCE_NAME"
echo ""
echo "  📊 To check costs, visit:"
echo "     https://console.cloud.google.com/billing"
echo ""

# Calculate estimated savings
if [ -f "${INSTANCE_NAME}-connection-info.txt" ]; then
    START_TIME=$(stat -c %Y "${INSTANCE_NAME}-connection-info.txt" 2>/dev/null || echo "0")
    if [ "$START_TIME" != "0" ]; then
        CURRENT_TIME=$(date +%s)
        ELAPSED_SECONDS=$((CURRENT_TIME - START_TIME))
        ELAPSED_HOURS=$((ELAPSED_SECONDS / 3600))
        ELAPSED_MINUTES=$(((ELAPSED_SECONDS % 3600) / 60))
        
        # Rough cost estimate (on-demand)
        ESTIMATED_COST=$(echo "scale=2; $ELAPSED_SECONDS / 3600 * 16" | bc 2>/dev/null || echo "unknown")
        
        echo "  ⏱️  This session ran for: ${ELAPSED_HOURS}h ${ELAPSED_MINUTES}m"
        if [ "$ESTIMATED_COST" != "unknown" ]; then
            echo "  💰 Estimated cost for this session: ~\$$ESTIMATED_COST"
        fi
        echo ""
    fi
fi

# Save stop info
STOP_INFO_FILE="${INSTANCE_NAME}-stop-info.txt"
cat > "$STOP_INFO_FILE" << EOF
Kimi K2.5 POC - Stop Information
================================
Stopped: $(date)
Instance: $INSTANCE_NAME
Zone:     $ZONE
Project:  $PROJECT_ID

Status:
  - Compute billing: HALTED
  - Storage billing: ACTIVE (~\$97/month)

To restart:
  ./start-poc.sh $PROJECT_ID $ZONE $INSTANCE_NAME
EOF

log_info "Stop info saved to: $STOP_INFO_FILE"

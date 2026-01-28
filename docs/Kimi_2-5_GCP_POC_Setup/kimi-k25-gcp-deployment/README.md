# Kimi K2.5 GCP Deployment

Complete deployment package for running Kimi K2.5 (Moonshot AI's 1-trillion parameter LLM) on Google Cloud Platform.

## Overview

This deployment package provides everything needed to deploy Kimi K2.5 on GCP with:
- **4x NVIDIA H100 80GB GPUs** for optimal inference performance
- **Spot/Preemptible instances** for ~70% cost savings
- **Automated start/stop scripts** for on-demand usage
- **Terraform infrastructure-as-code** for reproducible deployments
- **Container-optimized OS** with Docker and vLLM

## Quick Start

### Prerequisites

1. **GCP Project** with billing enabled
2. **GPU Quota** approved for H100 in your region (request at: https://cloud.google.com/docs/quotas/gpu)
3. **gcloud CLI** installed and authenticated
4. **Terraform** >= 1.0 installed

### 1. Configure Environment

```bash
# Set your GCP project
export PROJECT_ID=your-gcp-project-id
export ZONE=us-central1-a
export INSTANCE_NAME=kimi-k25-poc

# Authenticate
gcloud auth login
gcloud config set project $PROJECT_ID
```

### 2. Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply (creates the instance)
terraform apply

# Save outputs
cd ..
```

### 3. Start the Instance

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Start the instance and wait for API
./scripts/start-poc.sh $PROJECT_ID $ZONE $INSTANCE_NAME
```

### 4. Test the API

```bash
# Get the API endpoint from the output
curl http://<EXTERNAL_IP>:8000/v1/models

# Test chat completion
curl http://<EXTERNAL_IP>:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "moonshotai/Kimi-K2.5",
    "messages": [{"role": "user", "content": "Hello, who are you?"}]
  }'
```

### 5. Stop When Done

```bash
# Stop the instance to halt compute billing
./scripts/stop-poc.sh $PROJECT_ID $ZONE $INSTANCE_NAME
```

## Directory Structure

```
kimi-k25-gcp-deployment/
├── README.md                    # This file
├── terraform/                   # Infrastructure-as-code
│   ├── main.tf                  # Main Terraform configuration
│   ├── variables.tf             # Input variables
│   ├── outputs.tf               # Output values
│   └── startup.sh               # VM startup script
├── scripts/                     # Operational scripts
│   ├── start-poc.sh             # Start instance and configure access
│   ├── stop-poc.sh              # Stop instance
│   └── status.sh                # Check deployment status
├── container/                   # Container configuration
│   ├── docker-compose.yaml      # Docker Compose for vLLM
│   └── .env.example             # Environment variables template
└── docs/                        # Additional documentation
```

## Cost Breakdown

### On-Demand Pricing (4x H100 80GB)

| Component | Hourly | Monthly (24/7) |
|-----------|--------|----------------|
| 4x H100 GPUs | ~$14.00 | ~$10,220 |
| VM (vCPU/RAM) | ~$1.20 | ~$876 |
| 1TB SSD Storage | - | ~$170 |
| **Total Running** | **~$16/hr** | **~$11,390** |

### Spot Pricing (~70% Savings)

| Component | Hourly | Monthly (24/7) |
|-----------|--------|----------------|
| 4x H100 GPUs | ~$4.20 | ~$3,066 |
| VM (vCPU/RAM) | ~$0.36 | ~$263 |
| 1TB SSD Storage | - | ~$170 |
| **Total Running** | **~$5/hr** | **~$3,499** |

### Budget Scenarios (On-Demand)

| Usage Pattern | Hours/Month | Cost |
|--------------|-------------|------|
| Always-on dev | 730 | ~$11,390 |
| Business hours (8x5) | 160 | ~$2,730 |
| Demo-heavy | 40 | ~$810 |
| Sporadic testing | 20 | ~$490 |

**Storage cost is always ~$97/month** (boot + model disk).

## Configuration

### Terraform Variables

Edit `terraform/terraform.tfvars` or pass variables:

```hcl
project_id     = "your-project-id"
region         = "us-central1"
zone           = "us-central1-a"
instance_name  = "kimi-k25-poc"
machine_type   = "a3-highgpu-4g"
gpu_count      = 4
use_spot       = true
model_path     = "moonshotai/Kimi-K2.5"
api_port       = "8000"
```

### Environment Variables

```bash
# Required
export PROJECT_ID=your-project-id
export ZONE=us-central1-a
export INSTANCE_NAME=kimi-k25-poc

# Optional
export API_PORT=8000
export HUGGINGFACE_TOKEN=your-token  # If model requires auth
```

## API Usage

### OpenAI-Compatible Endpoints

The vLLM server provides OpenAI-compatible API endpoints:

```python
import openai

client = openai.OpenAI(
    base_url="http://<EXTERNAL_IP>:8000/v1",
    api_key="not-needed"
)

response = client.chat.completions.create(
    model="moonshotai/Kimi-K2.5",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Explain quantum computing"}
    ],
    temperature=0.7,
    max_tokens=1024
)

print(response.choices[0].message.content)
```

### Available Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /v1/models` | List available models |
| `POST /v1/chat/completions` | Chat completion |
| `POST /v1/completions` | Text completion |
| `GET /health` | Health check |
| `GET /metrics` | Prometheus metrics |

## Monitoring

### Check Status

```bash
./scripts/status.sh $PROJECT_ID $ZONE $INSTANCE_NAME
```

### View Logs

```bash
# SSH and view logs
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='docker logs -f kimi-k25-server'

# Or use the helper script on the VM
kimi-logs
```

### GPU Monitoring

```bash
# Check GPU utilization
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='nvidia-smi'

# Watch GPU stats
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='watch -n 1 nvidia-smi'
```

## Troubleshooting

### Instance Won't Start

```bash
# Check quota
gcloud compute project-info describe --project $PROJECT_ID | grep -i quota

# Check if GPU quota is approved
gcloud compute regions describe $REGION --project $PROJECT_ID
```

### API Not Responding

```bash
# Check container status
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='docker ps'

# View container logs
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='docker logs kimi-k25-server'

# Check if model is downloading (first startup)
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='ls -la /mnt/disks/model-storage/'
```

### GPU Not Detected

```bash
# Verify NVIDIA drivers
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='nvidia-smi'

# Check container runtime
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='docker info | grep -i nvidia'
```

## Security

### Firewall Rules

The start script automatically creates firewall rules for your IP. For production:

1. **Restrict SSH access** to specific IPs:
   ```bash
   --source-ranges="YOUR_OFFICE_IP/32"
   ```

2. **Use IAP (Identity-Aware Proxy)** instead of public SSH:
   ```bash
   gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --tunnel-through-iap
   ```

3. **Enable VPC Service Controls** for additional security.

### Service Account

The deployment creates a dedicated service account with minimal permissions:
- Logging and monitoring
- Storage read access
- Compute instance management

## Cleanup

### Destroy All Resources

```bash
cd terraform
terraform destroy
```

### Keep Disk, Delete Instance Only

```bash
# Stop and delete instance but keep disk
gcloud compute instances delete $INSTANCE_NAME --zone=$ZONE --keep-disks=data

# Later, attach disk to new instance
gcloud compute instances attach-disk NEW_INSTANCE --disk=$INSTANCE_NAME-model-disk --zone=$ZONE
```

## Advanced Configuration

### Custom Model Path

If you have a fine-tuned model or want to use a different version:

```hcl
model_path = "your-org/your-model"
```

### Quantization

For reduced memory usage (at some quality cost):

```yaml
# In docker-compose.yaml, add to command:
- --quantization=awq  # or gptq, fp8
```

### Multi-Node Deployment

For 8x H100 or distributed setups, contact Moonshot AI for guidance.

## Support

- **vLLM Documentation**: https://docs.vllm.ai/
- **Kimi K2.5 on HuggingFace**: https://huggingface.co/moonshotai/Kimi-K2.5
- **GCP GPU Quotas**: https://cloud.google.com/docs/quotas/gpu

## License

This deployment package is provided as-is for deploying Kimi K2.5 on GCP. Please comply with Moonshot AI's model license and GCP terms of service.

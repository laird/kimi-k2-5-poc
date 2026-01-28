# =============================================================================
# Kimi K2.5 GCP Deployment - Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "GCP Project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "GCP Region for resource deployment"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone for the GPU instance"
  type        = string
  default     = "us-central1-a"
}

# -----------------------------------------------------------------------------
# Instance Configuration
# -----------------------------------------------------------------------------

variable "instance_name" {
  description = "Name of the GPU instance"
  type        = string
  default     = "kimi-k25-poc"
}

variable "machine_type" {
  description = "Machine type for the GPU instance"
  type        = string
  default     = "a3-highgpu-4g"

  validation {
    condition     = can(regex("^(a3-|a2-ultragpu-|a2-highgpu-)", var.machine_type))
    error_message = "Machine type must be an A3 or A2 Ultra series instance with H100 or A100-80GB GPUs."
  }
}

variable "gpu_type" {
  description = "Type of GPU accelerator"
  type        = string
  default     = "nvidia-h100-80gb"
}

variable "gpu_count" {
  description = "Number of GPUs to attach to the instance"
  type        = number
  default     = 4

  validation {
    condition     = var.gpu_count >= 1 && var.gpu_count <= 8
    error_message = "GPU count must be between 1 and 8."
  }
}

# -----------------------------------------------------------------------------
# Disk Configuration
# -----------------------------------------------------------------------------

variable "boot_disk_size_gb" {
  description = "Size of the boot disk in GB"
  type        = number
  default     = 200
}

variable "model_disk_size_gb" {
  description = "Size of the persistent disk for model storage in GB"
  type        = number
  default     = 1000
}

# -----------------------------------------------------------------------------
# Pricing and Scheduling
# -----------------------------------------------------------------------------

variable "use_spot" {
  description = "Use Spot/Preemptible instances for cost savings (~70% off)"
  type        = bool
  default     = true
}

variable "automatic_restart" {
  description = "Automatically restart instance if terminated (only for non-spot)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------

variable "create_vpc" {
  description = "Create a new VPC network (true) or use existing (false)"
  type        = bool
  default     = true
}

variable "existing_vpc_self_link" {
  description = "Self-link of existing VPC network (if create_vpc is false)"
  type        = string
  default     = ""
}

variable "existing_subnet_self_link" {
  description = "Self-link of existing subnetwork (if create_vpc is false)"
  type        = string
  default     = ""
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet (if creating new VPC)"
  type        = string
  default     = "10.0.0.0/24"
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed to SSH to the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production!
}

variable "allowed_api_cidrs" {
  description = "List of CIDR blocks allowed to access the API"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production!
}

variable "api_port" {
  description = "Port for the vLLM API server"
  type        = string
  default     = "8000"
}

# -----------------------------------------------------------------------------
# Model Configuration
# -----------------------------------------------------------------------------

variable "model_path" {
  description = "Path to the Kimi K2.5 model (HuggingFace model ID or local path)"
  type        = string
  default     = "moonshotai/Kimi-K2.5"
}

variable "huggingface_token" {
  description = "HuggingFace API token for downloading models (if required)"
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Optional Features
# -----------------------------------------------------------------------------

variable "create_model_bucket" {
  description = "Create a Cloud Storage bucket for model caching"
  type        = bool
  default     = false
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring alerts"
  type        = bool
  default     = true
}

variable "monitoring_notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

variable "enable_auto_shutdown" {
  description = "Automatically shut down the instance if idle for 30 minutes"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Labels and Metadata
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Environment label (dev, staging, prod)"
  type        = string
  default     = "poc"
}

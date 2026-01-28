# =============================================================================
# Kimi K2.5 GCP Deployment - Terraform Configuration
# =============================================================================
# This Terraform configuration provisions the infrastructure required to
# deploy Kimi K2.5 on Google Cloud Platform using A3 series GPU instances.
#
# Prerequisites:
#   - GCP project with billing enabled
#   - GPU quota approved for H100 in your region
#   - gcloud CLI authenticated
#   - Terraform >= 1.0
# =============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# =============================================================================
# Service Account
# =============================================================================
resource "google_service_account" "kimi_service_account" {
  account_id   = "${var.instance_name}-sa"
  display_name = "Kimi K2.5 Service Account"
  description  = "Service account for Kimi K2.5 deployment"
}

resource "google_project_iam_member" "kimi_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/storage.objectViewer",
    "roles/compute.instanceAdmin.v1",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.kimi_service_account.email}"
}

# =============================================================================
# VPC Network (if create_vpc is true)
# =============================================================================
resource "google_compute_network" "kimi_vpc" {
  count                   = var.create_vpc ? 1 : 0
  name                    = "${var.instance_name}-vpc"
  auto_create_subnetworks = false
  description             = "VPC network for Kimi K2.5 deployment"
}

resource "google_compute_subnetwork" "kimi_subnet" {
  count         = var.create_vpc ? 1 : 0
  name          = "${var.instance_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.kimi_vpc[0].id

  private_ip_google_access = true
}

locals {
  network = var.create_vpc ? google_compute_network.kimi_vpc[0].self_link : var.existing_vpc_self_link
  subnet  = var.create_vpc ? google_compute_subnetwork.kimi_subnet[0].self_link : var.existing_subnet_self_link
}

# =============================================================================
# Firewall Rules
# =============================================================================
resource "google_compute_firewall" "kimi_allow_ssh" {
  name        = "${var.instance_name}-allow-ssh"
  network     = local.network
  description = "Allow SSH access to Kimi K2.5 instance"
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_ssh_cidrs
  target_tags   = [var.instance_name]
}

resource "google_compute_firewall" "kimi_allow_iap_ssh" {
  name        = "${var.instance_name}-allow-iap-ssh"
  network     = local.network
  description = "Allow SSH access via IAP"
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = [var.instance_name]
}

resource "google_compute_firewall" "kimi_allow_api" {
  name        = "${var.instance_name}-allow-api"
  network     = local.network
  description = "Allow API access to vLLM server"
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = [var.api_port]
  }

  source_ranges = var.allowed_api_cidrs
  target_tags   = [var.instance_name]
}

resource "google_compute_firewall" "kimi_allow_darksoft" {
  name        = "${var.instance_name}-allow-darksoft"
  network     = local.network
  description = "Allow API access from the darksoft sandbox project"
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = [var.api_port]
  }

  source_ranges = ["10.0.1.0/24"]
  target_tags   = [var.instance_name]
}

# =============================================================================
# Persistent Disk for Model Storage
# =============================================================================
resource "google_compute_disk" "kimi_model_disk" {
  name        = "${var.instance_name}-model-disk"
  type        = "pd-ssd"
  zone        = var.zone
  size        = var.model_disk_size_gb
  description = "Persistent disk for Kimi K2.5 model weights"

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# =============================================================================
# Boot Disk Image
# =============================================================================
data "google_compute_image" "cos" {
  family  = "cos-stable"
  project = "cos-cloud"
}

# =============================================================================
# Startup Script
# =============================================================================
locals {
  startup_script = templatefile("${path.module}/startup.sh", {
    model_path           = var.model_path
    MODEL_PATH           = var.model_path
    tensor_parallel      = var.gpu_count
    TENSOR_PARALLEL      = var.gpu_count
    api_port             = var.api_port
    API_PORT             = var.api_port
    huggingface_token    = var.huggingface_token
    HUGGINGFACE_TOKEN    = var.huggingface_token
    GOOGLE_CLOUD_PROJECT = var.project_id
    ENABLE_AUTO_SHUTDOWN = var.enable_auto_shutdown
    google_cloud_project = var.project_id
  })
}

# =============================================================================
# GPU Instance
# =============================================================================
resource "google_compute_instance" "kimi_instance" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  description  = "Kimi K2.5 inference server"

  # Use preemptible/spot instances for cost savings
  scheduling {
    preemptible       = var.use_spot
    automatic_restart = var.use_spot ? false : var.automatic_restart
    on_host_maintenance = "TERMINATE"
    provisioning_model = var.use_spot ? "SPOT" : "STANDARD"
  }

  # Boot disk with Container-Optimized OS
  boot_disk {
    initialize_params {
      image = data.google_compute_image.cos.self_link
      size  = var.boot_disk_size_gb
      type  = "pd-ssd"
    }
  }

  # Attach model storage disk
  attached_disk {
    source      = google_compute_disk.kimi_model_disk.id
    device_name = "model-storage"
    mode        = "READ_WRITE"
  }

  # GPU configuration
  guest_accelerator {
    type  = var.gpu_type
    count = var.gpu_count
  }

  # Network configuration
  network_interface {
    network    = local.network
    subnetwork = local.subnet
  }

  # Metadata and startup script
  metadata = {
    google-logging-enabled    = "true"
    google-monitoring-enabled = "true"
    user-data                 = local.startup_script
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  # Service account
  service_account {
    email  = google_service_account.kimi_service_account.email
    scopes = ["cloud-platform"]
  }

  # Labels for cost tracking
  labels = {
    environment = var.environment
    managed_by  = "terraform"
    model       = "kimi-k25"
  }

  tags = [var.instance_name]

  depends_on = [
    google_project_iam_member.kimi_roles,
    google_compute_disk.kimi_model_disk,
  ]

  lifecycle {
    prevent_destroy = false
    ignore_changes = [
      metadata["ssh-keys"],
    ]
  }
}

# =============================================================================
# Cloud Storage Bucket for Model Cache (Optional)
# =============================================================================
resource "google_storage_bucket" "kimi_model_cache" {
  count         = var.create_model_bucket ? 1 : 0
  name          = "${var.project_id}-${var.instance_name}-models"
  location      = var.region
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  versioning {
    enabled = false
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 90
    }
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# =============================================================================
# Cloud Monitoring Alerting (Optional)
# =============================================================================
resource "google_monitoring_alert_policy" "kimi_high_gpu_temp" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "${var.instance_name} High GPU Temperature"
  combiner     = "OR"

  conditions {
    display_name = "GPU Temperature > 85C"

    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND metric.type=\"nvidia.com/gpu/temperature\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 85

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.monitoring_notification_channels

  alert_strategy {
    auto_close = "86400s"
  }

  severity = "WARNING"

  user_labels = {
    environment = var.environment
    instance    = var.instance_name
  }
}
# =============================================================================
# VPC Network Peering (Cross-Project Access)
# =============================================================================
resource "google_compute_network_peering" "peering_to_darksoft" {
  count                = var.create_vpc ? 1 : 0
  name                 = "peering-to-darksoft"
  network              = google_compute_network.kimi_vpc[0].self_link
  peer_network         = "projects/gp-ct-sbox-sat-gcp0bg-darksoft/global/networks/dev-network"
  export_custom_routes = true
  import_custom_routes = true
}

# =============================================================================
# Cloud NAT (Allow internet access without public IP)
# =============================================================================
resource "google_compute_router" "kimi_router" {
  count   = var.create_vpc ? 1 : 0
  name    = "${var.instance_name}-router"
  region  = var.region
  network = local.network
}

resource "google_compute_router_nat" "kimi_nat" {
  count                              = var.create_vpc ? 1 : 0
  name                               = "${var.instance_name}-nat"
  router                             = google_compute_router.kimi_router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

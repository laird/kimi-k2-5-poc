# =============================================================================
# Kimi K2.5 GCP Deployment - Outputs
# =============================================================================

output "instance_name" {
  description = "Name of the created GPU instance"
  value       = google_compute_instance.kimi_instance.name
}

output "instance_id" {
  description = "ID of the created GPU instance"
  value       = google_compute_instance.kimi_instance.id
}

output "instance_self_link" {
  description = "Self-link of the created GPU instance"
  value       = google_compute_instance.kimi_instance.self_link
}

output "internal_ip" {
  description = "Internal IP address of the Kimi K2.5 instance"
  value       = google_compute_instance.kimi_instance.network_interface[0].network_ip
}

output "api_endpoint" {
  description = "Base URL for the vLLM API (accessible via IAP-tunnel or VPN)"
  value       = "http://${google_compute_instance.kimi_instance.network_interface[0].network_ip}:${var.api_port}/v1"
}

output "health_check_url" {
  description = "Health check URL for the vLLM API (accessible via IAP-tunnel or VPN)"
  value       = "http://${google_compute_instance.kimi_instance.network_interface[0].network_ip}:${var.api_port}/health"
}

output "ssh_command" {
  description = "Command to SSH into the instance using IAP tunnel"
  value       = "gcloud compute ssh ${var.instance_name} --zone=${var.zone} --project=${var.project_id} --tunnel-through-iap"
}

output "start_command" {
  description = "Command to start the instance"
  value       = "gcloud compute instances start ${google_compute_instance.kimi_instance.name} --zone=${var.zone} --project=${var.project_id}"
}

output "stop_command" {
  description = "Command to stop the instance"
  value       = "gcloud compute instances stop ${google_compute_instance.kimi_instance.name} --zone=${var.zone} --project=${var.project_id}"
}

output "service_account_email" {
  description = "Email of the service account created for the instance"
  value       = google_service_account.kimi_service_account.email
}

output "model_disk_name" {
  description = "Name of the persistent disk for model storage"
  value       = google_compute_disk.kimi_model_disk.name
}

output "model_bucket_name" {
  description = "Name of the Cloud Storage bucket for model cache (if created)"
  value       = var.create_model_bucket ? google_storage_bucket.kimi_model_cache[0].name : null
}

output "estimated_hourly_cost" {
  description = "Estimated hourly cost based on configuration"
  value       = var.use_spot ? "$9.00-$10.36 (Spot)" : "$14.00-$15.72 (On-Demand)"
}

output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = var.create_vpc ? google_compute_network.kimi_vpc[0].name : "Using existing VPC"
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = var.create_vpc ? google_compute_subnetwork.kimi_subnet[0].name : "Using existing subnet"
}

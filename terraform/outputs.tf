output "function_name" {
  description = "Name of the Cloud Function"
  value       = google_cloudfunctions2_function.mig_scheduler.name
}

output "function_url" {
  description = "URL of the Cloud Function"
  value       = google_cloudfunctions2_function.mig_scheduler.service_config[0].uri
}

output "mig_name" {
  description = "Managed Instance Group being managed"
  value       = var.mig_name
}

output "mig_region" {
  description = "Region of the MIG"
  value       = var.mig_region
}

output "scale_down_topic" {
  description = "Pub/Sub topic for scale down"
  value       = google_pubsub_topic.scale_down.name
}

output "scale_up_topic" {
  description = "Pub/Sub topic for scale up"
  value       = google_pubsub_topic.scale_up.name
}

output "scale_down_schedule" {
  description = "Schedule for scaling down VMs"
  value       = google_cloud_scheduler_job.scale_down.schedule
}

output "scale_up_schedule" {
  description = "Schedule for scaling up VMs"
  value       = google_cloud_scheduler_job.scale_up.schedule
}

output "service_account_email" {
  description = "Service account email for the function"
  value       = google_service_account.vm_scheduler.email
}

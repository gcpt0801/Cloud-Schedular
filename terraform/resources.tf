# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "pubsub.googleapis.com",
    "compute.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com",
    "logging.googleapis.com"
  ])

  service            = each.key
  disable_on_destroy = false
}

# Create Pub/Sub topics for scale up and scale down
resource "google_pubsub_topic" "scale_down" {
  name = "mig-scale-down"

  depends_on = [google_project_service.required_apis]
}

resource "google_pubsub_topic" "scale_up" {
  name = "mig-scale-up"

  depends_on = [google_project_service.required_apis]
}

# Service account for Cloud Function
resource "google_service_account" "mig_scheduler" {
  account_id   = "mig-scheduler-sa"
  display_name = "MIG Scheduler Service Account"
  description  = "Service account for MIG scheduler Cloud Function"
}

# Grant Compute Instance Admin role to service account (required for MIG resize)
resource "google_project_iam_member" "compute_admin" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.mig_scheduler.email}"
}

# Grant Compute Viewer role to service account
resource "google_project_iam_member" "compute_viewer" {
  project = var.project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.mig_scheduler.email}"
}

# Grant service agents permission to use MIG scheduler service account
# Note: Only Google-managed service agents need permissions
# Cloud Build and Compute default SAs are NOT required for Cloud Functions Gen2
# when deploying via a properly configured service account (like GitHub Actions SA)

resource "google_service_account_iam_member" "mig_scheduler_gcf_user" {
  service_account_id = google_service_account.mig_scheduler.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:service-${data.google_project.project.number}@gcf-admin-robot.iam.gserviceaccount.com"
}

resource "google_service_account_iam_member" "mig_scheduler_cloudbuild_agent_user" {
  service_account_id = google_service_account.mig_scheduler.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

# Get project number for service agent accounts
data "google_project" "project" {
  project_id = var.project_id
}

# Create GCS bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name          = "${var.project_id}-vm-scheduler-source"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  depends_on = [google_project_service.required_apis]
}

# Archive the function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/../function-source.zip"
  source_dir  = "${path.module}/.."

  excludes = [
    "terraform",
    ".git",
    ".gitignore",
    "README.md",
    "function-source.zip",
    ".gcloudignore",
    "config.yaml",
    "Dockerfile",
    ".dockerignore",
    "cloudbuild.yaml"
  ]
}

# Upload function source to GCS
resource "google_storage_bucket_object" "function_source" {
  name   = "vm-scheduler-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# Cloud Function for VM scheduling
resource "google_cloudfunctions2_function" "mig_scheduler" {
  name        = "mig-scheduler"
  location    = var.region
  description = "Automated MIG scheduler for scale up/down"

  build_config {
    runtime     = "python311"
    entry_point = "mig_scheduler"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    min_instance_count    = 0
    available_memory      = "256Mi"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.mig_scheduler.email

    environment_variables = {
      GCP_PROJECT       = var.project_id
      MIG_NAME          = var.mig_name
      MIG_ZONE          = var.mig_zone
      MIG_SCALE_UP_SIZE = tostring(var.mig_scale_up_size)
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.scale_down.id
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.mig_scheduler.email
  }

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.compute_admin,
    google_project_iam_member.compute_viewer
  ]
}

# Second function instance for scale up (shares same code, different trigger)
resource "google_cloudfunctions2_function" "mig_scheduler_scale_up" {
  name        = "mig-scheduler-scale-up"
  location    = var.region
  description = "Automated MIG scheduler for scale up"

  build_config {
    runtime     = "python311"
    entry_point = "mig_scheduler"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    min_instance_count    = 0
    available_memory      = "256Mi"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.mig_scheduler.email

    environment_variables = {
      GCP_PROJECT       = var.project_id
      MIG_NAME          = var.mig_name
      MIG_ZONE          = var.mig_zone
      MIG_SCALE_UP_SIZE = tostring(var.mig_scale_up_size)
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.scale_up.id
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.mig_scheduler.email
  }

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.compute_admin,
    google_project_iam_member.compute_viewer
  ]
}

# Grant Cloud Run invoker permissions for the functions
resource "google_cloud_run_service_iam_member" "mig_scheduler_eventarc_invoker" {
  location = google_cloudfunctions2_function.mig_scheduler.location
  service  = google_cloudfunctions2_function.mig_scheduler.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-eventarc.iam.gserviceaccount.com"
}

resource "google_cloud_run_service_iam_member" "mig_scheduler_sa_invoker" {
  location = google_cloudfunctions2_function.mig_scheduler.location
  service  = google_cloudfunctions2_function.mig_scheduler.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.mig_scheduler.email}"
}

resource "google_cloud_run_service_iam_member" "mig_scheduler_scale_up_eventarc_invoker" {
  location = google_cloudfunctions2_function.mig_scheduler_scale_up.location
  service  = google_cloudfunctions2_function.mig_scheduler_scale_up.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-eventarc.iam.gserviceaccount.com"
}

resource "google_cloud_run_service_iam_member" "mig_scheduler_scale_up_sa_invoker" {
  location = google_cloudfunctions2_function.mig_scheduler_scale_up.location
  service  = google_cloudfunctions2_function.mig_scheduler_scale_up.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.mig_scheduler.email}"
}

# Service account for Cloud Scheduler
resource "google_service_account" "scheduler" {
  account_id   = "vm-scheduler-invoker"
  display_name = "VM Scheduler Invoker"
  description  = "Service account for Cloud Scheduler to publish to Pub/Sub"
}

# Grant Pub/Sub Publisher role to scheduler service account
resource "google_pubsub_topic_iam_member" "scale_down_publisher" {
  topic  = google_pubsub_topic.scale_down.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.scheduler.email}"
}

resource "google_pubsub_topic_iam_member" "scale_up_publisher" {
  topic  = google_pubsub_topic.scale_up.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.scheduler.email}"
}

# Cloud Scheduler job for scaling down MIG
resource "google_cloud_scheduler_job" "scale_down" {
  name             = "mig-scale-down-weekend"
  description      = "Scale down MIG for the weekend"
  schedule         = var.scale_down_schedule
  time_zone        = var.timezone
  attempt_deadline = "320s"

  pubsub_target {
    topic_name = google_pubsub_topic.scale_down.id
    data = base64encode(jsonencode({
      action     = "scale_down"
      project_id = var.project_id
      mig_name   = var.mig_name
      zone       = var.mig_zone
    }))
  }

  depends_on = [
    google_project_service.required_apis,
    google_pubsub_topic_iam_member.scale_down_publisher
  ]
}

# Cloud Scheduler job for scaling up MIG
resource "google_cloud_scheduler_job" "scale_up" {
  name             = "mig-scale-up-weekday"
  description      = "Scale up MIG for the weekday"
  schedule         = var.scale_up_schedule
  time_zone        = var.timezone
  attempt_deadline = "320s"

  pubsub_target {
    topic_name = google_pubsub_topic.scale_up.id
    data = base64encode(jsonencode({
      action        = "scale_up"
      project_id    = var.project_id
      mig_name      = var.mig_name
      zone          = var.mig_zone
      scale_up_size = var.mig_scale_up_size
    }))
  }

  depends_on = [
    google_project_service.required_apis,
    google_pubsub_topic_iam_member.scale_up_publisher
  ]
}

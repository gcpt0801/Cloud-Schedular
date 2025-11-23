variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "mig_name" {
  description = "Name of the Managed Instance Group to scale"
  type        = string
  default     = "oracle-linux-mig"
}

variable "mig_region" {
  description = "Region where the MIG is located"
  type        = string
  default     = "us-central1"
}

variable "mig_scale_up_size" {
  description = "Target size when scaling up the MIG"
  type        = number
  default     = 3
  
  validation {
    condition     = var.mig_scale_up_size > 0
    error_message = "mig_scale_up_size must be greater than 0"
  }
}

variable "scale_down_schedule" {
  description = "Cron schedule for scaling down VMs (default: Friday 6 PM)"
  type        = string
  default     = "0 18 * * 5"
}

variable "scale_up_schedule" {
  description = "Cron schedule for scaling up VMs (default: Monday 8 AM)"
  type        = string
  default     = "0 8 * * 1"
}

variable "timezone" {
  description = "Timezone for the Cloud Scheduler"
  type        = string
  default     = "America/New_York"
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 300
}

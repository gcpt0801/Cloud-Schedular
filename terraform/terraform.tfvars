project_id = "gcp-terraform-demo-474514"
region     = "us-central1"

# Managed Instance Group configuration
mig_name   = "oracle-linux-mig"
mig_region = "us-central1"

# Target size when scaling up (scales down to 0 on weekends)
mig_scale_up_size = 3

# Cron schedules (in Cloud Scheduler format)
# Default: Scale down on Friday at 6 PM, scale up on Monday at 8 AM
scale_down_schedule = "0 18 * * 5"  # Friday 6 PM
scale_up_schedule   = "0 8 * * 1"   # Monday 8 AM

# Timezone for schedules
timezone = "America/New_York"

# Function timeout in seconds
function_timeout = 300

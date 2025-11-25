# Google Cloud MIG Scheduler

Automated solution for scaling Managed Instance Groups (MIGs) in Google Cloud Platform based on custom schedules for cost optimization. This project uses **Cloud Functions (Gen 2)**, **Cloud Scheduler**, **Pub/Sub**, and **Terraform** for infrastructure as code with a single consolidated service account for simplified IAM management.

## ✨ Key Improvements

This project implements several best practices and optimizations:

- 🎯 **Single Service Account**: Consolidated IAM using one service account (`mig-scheduler-sa`) for all operations
- 🔧 **Dual Function Design**: Separate Cloud Functions for scale-up and scale-down for better monitoring
- 🔒 **Automated IAM**: All permissions automatically configured via Terraform - no manual setup
- 🚀 **Cloud Build Integration**: Functions built using the application service account (not default Compute SA)
- 📦 **Clean Architecture**: No redundant service accounts or IAM bindings
- 🗑️ **Safe Destruction**: GitHub Actions workflow with double confirmation for infrastructure teardown
- 🔄 **Idempotent**: Can be applied multiple times safely

## 📊 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    GitHub Actions (CI/CD)                       │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────┐   │
│  │  Validate   │ -> │  Terraform   │ -> │  Deploy to GCP  │   │
│  │  (PR/Push)  │    │     Plan     │    │   (Push main)   │   │
│  └─────────────┘    └──────────────┘    └─────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Google Cloud Platform                          │
│                                                                 │
│  ┌──────────────────┐        ┌──────────────────┐             │
│  │ Cloud Scheduler  │        │ Cloud Scheduler  │             │
│  │  (Scale Down)    │        │   (Scale Up)     │             │
│  │  Fri 6 PM EST    │        │  Mon 8 AM EST    │             │
│  └────────┬─────────┘        └────────┬─────────┘             │
│           │                           │                        │
│           ▼                           ▼                        │
│  ┌──────────────────┐        ┌──────────────────┐             │
│  │   Pub/Sub Topic  │        │   Pub/Sub Topic  │             │
│  │ mig-scale-down   │        │  mig-scale-up    │             │
│  └────────┬─────────┘        └────────┬─────────┘             │
│           │                           │                        │
│           └───────────┬───────────────┘                        │
│                       ▼                                        │
│       ┌───────────────────────────────┐                       │
│       │  Cloud Function (Gen 2)       │                       │
│       │     mig-scheduler             │                       │
│       │   • Python 3.11               │                       │
│       │   • Eventarc Trigger          │                       │
│       └──────────────┬────────────────┘                       │
│                      │                                         │
│                      ▼                                         │
│       ┌───────────────────────────────┐                       │
│       │    Compute Engine API         │                       │
│       │  • Resize MIG to 0 (down)     │                       │
│       │  • Resize MIG to N (up)       │                       │
│       └──────────────┬────────────────┘                       │
│                      │                                         │
│                      ▼                                         │
│       ┌───────────────────────────────┐                       │
│       │  Managed Instance Group       │                       │
│       │    oracle-linux-mig           │                       │
│       │    Zone: us-central1-a        │                       │
│       │    Size: 0 ↔ 5                │                       │
│       └───────────────────────────────┘                       │
└─────────────────────────────────────────────────────────────────┘
```

## 🎯 Features

- ⏰ **Automated Scheduling**: Custom cron schedules for scaling operations (scale up and scale down)
- 🔧 **Zonal MIG Support**: Works with zonal Managed Instance Groups
- 🔒 **Secure**: Single service account with consolidated IAM permissions
- 📦 **Infrastructure as Code**: Complete Terraform configuration with automated IAM setup
- 🚀 **CI/CD Ready**: GitHub Actions workflows for automated deployment and destruction
- 💰 **Cost Optimization**: Save costs by scaling down during off-hours or weekends
- 🔄 **State Management**: Remote state in GCS bucket with state locking
- 🧪 **Easy Testing**: Manual trigger via Cloud Scheduler
- 🗑️ **Infrastructure Destruction**: Safe workflow with confirmation for tearing down resources
- 📊 **Dual Function Design**: Separate Cloud Functions for scale-up and scale-down operations

## 📋 Prerequisites

- Google Cloud Platform account with billing enabled
- GCP Project with necessary APIs enabled (automated by Terraform)
- GitHub repository with required secrets configured
- Terraform >= 1.6
- Python 3.11 (for Cloud Functions runtime)
- Existing Managed Instance Group (MIG) in GCP

## 🚀 Quick Start

### 1. Configure Variables

Edit `terraform/terraform.tfvars`:

```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"

# MIG configuration
mig_name = "your-mig-name"
mig_zone = "us-central1-a"  # Zone where your MIG is located

# Target size when scaling up
mig_scale_up_size = 5

# Schedules (cron format)
scale_down_schedule = "0 18 * * 5"  # Friday 6 PM
scale_up_schedule   = "0 8 * * 1"   # Monday 8 AM
timezone            = "America/New_York"
```

### 2. Configure Backend

Edit `terraform/backend.tf` with your existing GCS bucket:

```hcl
terraform {
  backend "gcs" {
    bucket = "your-existing-terraform-state-bucket"
    prefix = "cloud-schedular/terraform/state"
  }
}
```

### 3. Set Up GitHub Secrets

Add the following secrets to your GitHub repository (Settings → Secrets and variables → Actions):

| Secret Name | Description |
|------------|-------------|
| `GCP_SA_KEY` | Service account JSON key with appropriate permissions |
| `GCP_PROJECT_ID` | Your GCP project ID |

**Required Service Account Permissions:**
- Editor or Owner role (for Terraform to create all resources)
- OR specific roles: Compute Admin, Cloud Functions Admin, Cloud Scheduler Admin, Pub/Sub Admin, Storage Admin, IAM Admin

### 4. Deploy

Push to main branch - GitHub Actions will automatically deploy:

```bash
git add .
git commit -m "Initial setup"
git push origin main
```

## 🔧 Manual Deployment

For local deployment:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## 📊 Testing

### Manual Trigger via Cloud Scheduler

```bash
# Scale down
gcloud scheduler jobs run mig-scale-down-weekend --location=us-central1

# Scale up
gcloud scheduler jobs run mig-scale-up-weekday --location=us-central1
```

### Check Function Logs

```bash
# Scale down function logs
gcloud functions logs read mig-scheduler --region=us-central1 --limit=50 --gen2

# Scale up function logs
gcloud functions logs read mig-scheduler-scale-up --region=us-central1 --limit=50 --gen2
```

### Check MIG Status

```bash
# Get current MIG size
gcloud compute instance-groups managed describe your-mig-name \
  --zone=us-central1-a \
  --format="value(targetSize)"

# Get detailed MIG info
gcloud compute instance-groups managed describe your-mig-name \
  --zone=us-central1-a
```

### Verify Scheduled Jobs

```bash
# List all Cloud Scheduler jobs
gcloud scheduler jobs list --location=us-central1

# Get specific job details
gcloud scheduler jobs describe mig-scale-down-weekend --location=us-central1
```

## 📁 Project Structure

```
.
├── main.py                          # Cloud Function code (shared by both functions)
├── requirements.txt                 # Python dependencies
├── .github/
│   └── workflows/
│       ├── deploy.yml              # Main deployment workflow (Terraform apply)
│       └── destroy.yml             # Infrastructure destruction workflow
└── terraform/
    ├── backend.tf                  # GCS backend configuration
    ├── main.tf                     # Provider configuration
    ├── variables.tf                # Variable definitions
    ├── terraform.tfvars            # Variable values (customize here)
    ├── resources.tf                # All GCP resources & IAM (single SA)
    └── outputs.tf                  # Output values
```

## 🔐 IAM Permissions

All IAM permissions are **fully automated** via Terraform using a **single consolidated service account** (`mig-scheduler-sa`).

### Single Service Account Architecture

The project uses one service account (`mig-scheduler-sa`) for all operations:
- ✅ Cloud Functions runtime
- ✅ Cloud Build (for building functions)
- ✅ MIG resize operations
- ✅ Cloud Storage access
- ✅ Logging and monitoring

### Automated Roles (Applied via Terraform)

| Role | Purpose |
|------|---------|
| `roles/compute.instanceAdmin.v1` | Resize MIG instances |
| `roles/compute.viewer` | View MIG state and metadata |
| `roles/cloudfunctions.admin` | Deploy Cloud Functions |
| `roles/storage.admin` | Access Cloud Storage buckets |
| `roles/logging.logWriter` | Write function logs |
| `roles/artifactregistry.writer` | Push container images |
| `roles/cloudbuild.builds.builder` | Build Cloud Functions |
| `roles/iam.serviceAccountUser` | Act as service account |

### Verify Permissions

```bash
gcloud projects get-iam-policy YOUR_PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:mig-scheduler-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --format="table(bindings.role)"
```

## 🛠️ Customization

### Change Schedule

Edit schedules in `terraform/terraform.tfvars`:

```hcl
# Scale down every day at 10 PM
scale_down_schedule = "0 22 * * *"

# Scale up every day at 6 AM
scale_up_schedule = "0 6 * * *"
```

### Change Scale Size

```hcl
# Scale up to 10 instances
mig_scale_up_size = 10
```

## 🐛 Troubleshooting

### Function Build Failures

**Issue**: Cloud Function fails to build with permission errors

**Solution**: Verify service account has all required roles:
```bash
gcloud projects get-iam-policy YOUR_PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:mig-scheduler-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --format="table(bindings.role)"
```

Should show all 8 roles listed in the IAM Permissions section.

### Function Not Executing

**Issue**: Scheduler triggers but function doesn't execute

**Solution**: Check Cloud Run invoker permissions:
```bash
gcloud run services get-iam-policy mig-scheduler --region=us-central1
```

### MIG Not Found Error

**Issue**: Function logs show "MIG not found"

**Solution**: Verify MIG exists and zone is correct:
```bash
gcloud compute instance-groups managed list
gcloud compute instance-groups managed describe YOUR_MIG_NAME --zone=YOUR_ZONE
```

### Permission Denied for MIG Operations

**Issue**: "Permission denied" when trying to resize MIG

**Solution**: 
1. Verify service account has `roles/compute.instanceAdmin.v1`
2. Check if MIG is in the correct zone specified in `terraform.tfvars`
3. Ensure function is using the correct service account:
```bash
gcloud functions describe mig-scheduler --region=us-central1 --gen2 \
  --format="value(serviceConfig.serviceAccountEmail)"
```

### Terraform State Issues

**Issue**: Terraform state lock or conflicts

**Solution**:
```bash
# Check state lock
gsutil ls gs://YOUR_BUCKET/cloud-schedular/terraform/state/

# Force unlock (use with caution)
terraform force-unlock LOCK_ID
```

### GCS Bucket Access Denied

**Issue**: Function build fails with "Access to bucket gcf-v2-sources-* denied"

**Solution**: This is handled automatically by Terraform. If you see this error, ensure:
1. The `google_storage_bucket_iam_member.gcf_source_bucket_access` resource is applied
2. Re-run `terraform apply` to ensure all IAM bindings are created

## 💰 Cost Savings Example

### Weekend Shutdown Scenario
For a 5-instance MIG running weekdays only (scale down Friday 6 PM, scale up Monday 8 AM):
- **Before**: 5 instances × 168 hours/week = 840 instance-hours/week
- **After**: 5 instances × 118 hours/week = 590 instance-hours/week  
- **Weekly Savings**: ~30% reduction in compute hours
- **Monthly Savings**: ~250 instance-hours saved

### Cost Estimate (e2-medium instances in us-central1)
- Instance cost: ~$0.033/hour
- Monthly savings: 250 hours × $0.033 × 4 weeks = **~$33/month per instance**
- Total savings for 5-instance MIG: **~$165/month**

### Infrastructure Costs
- Cloud Functions: $0.00 (within free tier for 2 invocations/week)
- Cloud Scheduler: $0.30/month (2 jobs)
- Pub/Sub: $0.00 (within free tier)
- Cloud Storage: $0.02/month (function source)
- **Total overhead**: ~$0.32/month

**Net monthly savings: ~$164.68 for a 5-instance MIG** 🎉

## 🗑️ Destroying Infrastructure

A safe destruction workflow is included for tearing down all resources.

### Via GitHub Actions (Recommended)

1. Go to **Actions** tab in GitHub
2. Select **"Destroy Infrastructure"** workflow
3. Click **"Run workflow"**
4. Type `destroy` in the confirmation field
5. Select environment (dev/staging/production)
6. Click **"Run workflow"**

The workflow includes:
- ✅ Double confirmation required
- ✅ Terraform plan shown before destruction
- ✅ 10-second wait for manual cancellation
- ✅ Audit trail of who destroyed what

### Via Local Terraform

```bash
cd terraform
terraform destroy
```

Review the plan carefully and type `yes` to confirm.

## 🔄 CI/CD Workflows

### Deploy Workflow (`deploy.yml`)
- **Trigger**: Push to `main` branch
- **Steps**: Terraform init → validate → plan → apply
- **Authentication**: Uses `GCP_SA_KEY` secret
- **State**: Managed in GCS bucket

### Destroy Workflow (`destroy.yml`)
- **Trigger**: Manual workflow dispatch
- **Safety**: Requires typing "destroy" to confirm
- **Features**: Shows plan, includes 10-second cancellation window
- **Audit**: Records who destroyed and when

## 📝 License

MIT License - feel free to use this project for your own needs.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 🔗 Resources

- [Cloud Functions Gen 2 Documentation](https://cloud.google.com/functions/docs/2nd-gen/overview)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [MIG Documentation](https://cloud.google.com/compute/docs/instance-groups)
- [Cloud Build Service Account Permissions](https://cloud.google.com/build/docs/cloud-build-service-account)
- [IAM Best Practices](https://cloud.google.com/iam/docs/best-practices)

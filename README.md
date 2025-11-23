# Google Cloud MIG Scheduler

Automated solution for scaling Managed Instance Groups (MIGs) in Google Cloud Platform during weekends for cloud cost optimization. This project uses **Cloud Functions (2nd gen)**, **Cloud Scheduler**, **Pub/Sub**, and **Terraform** for infrastructure as code.

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

- ⏰ **Automated Scheduling**: Custom cron schedules for scaling operations
- 🔧 **Zonal MIG Support**: Works with zonal Managed Instance Groups
- 🔒 **Secure**: Service account authentication with least-privilege IAM
- 📦 **Infrastructure as Code**: Complete Terraform configuration with automated IAM
- 🚀 **CI/CD Ready**: GitHub Actions for automated deployment
- 💰 **Cost Optimization**: Save costs by scaling down during off-hours
- 🔄 **State Management**: Remote state in existing GCS bucket
- 🧪 **Easy Testing**: Manual trigger via Cloud Scheduler or GitHub Actions

## 📋 Prerequisites

- Google Cloud Platform account with billing enabled
- Existing GCS bucket for Terraform state
- GitHub repository with GCP service account key secret
- Terraform >= 1.6
- Python 3.11 (for local testing)

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

Add `GCP_SA_KEY` secret to your GitHub repository:
- Go to Settings → Secrets and variables → Actions
- Add new repository secret: `GCP_SA_KEY`
- Paste your service account JSON key

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

### Manual Trigger via GitHub Actions

1. Go to Actions tab in GitHub
2. Select "Manual MIG Scaling" workflow
3. Click "Run workflow"
4. Choose action (scale_down or scale_up)

### Check Logs

```bash
gcloud functions logs read mig-scheduler --region=us-central1 --limit=50 --gen2
```

### Check MIG Status

```bash
gcloud compute instance-groups managed describe your-mig-name --zone=us-central1-a
```

## 📁 Project Structure

```
.
├── main.py                          # Cloud Function code
├── requirements.txt                 # Python dependencies
├── .github/
│   └── workflows/
│       ├── deploy.yml              # Main deployment workflow
│       ├── validate.yml            # PR validation
│       └── manual-trigger.yml      # Manual scaling trigger
└── terraform/
    ├── backend.tf                  # GCS backend configuration
    ├── main.tf                     # Provider configuration
    ├── variables.tf                # Variable definitions
    ├── terraform.tfvars            # Variable values
    ├── resources.tf                # All GCP resources & IAM
    └── outputs.tf                  # Output values
```

## 🔐 IAM Permissions

All required permissions are automated via Terraform - no manual setup needed!

### Automated Permissions Include:
- Cloud Build service account permissions
- Compute service account permissions
- MIG scheduler service account permissions
- Cloud Run invoker permissions
- Storage bucket access
- Service agent permissions

📖 **For detailed explanation of why each permission is needed, see [PERMISSIONS.md](PERMISSIONS.md)**

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

### Function not executing

Check Cloud Run invoker permissions:
```bash
gcloud run services get-iam-policy mig-scheduler --region=us-central1
```

### MIG not found

Verify MIG exists and zone is correct:
```bash
gcloud compute instance-groups managed list
```

### Permission denied

Check IAM policies:
```bash
gcloud projects get-iam-policy your-project-id \
  --flatten="bindings[].members" \
  --filter="bindings.members:mig-scheduler-sa@*"
```

## 📈 Cost Savings Example

For a 5-instance MIG running weekdays only:
- **Before**: 5 instances × 24/7 × 4 weeks = 840 instance-hours/month
- **After**: 5 instances × 120 hours/week × 4 weeks = 600 instance-hours/month  
- **Savings**: ~29% reduction in compute hours

## 📝 License

MIT License - feel free to use this project for your own needs.

## 🔗 Resources

- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [MIG Documentation](https://cloud.google.com/compute/docs/instance-groups)

# Grant necessary permissions to your Terraform service account
# Run this script locally with your GCP credentials

$PROJECT_ID = "gcp-terraform-demo-474514"
$SERVICE_ACCOUNT = "gcp-terraform-demo@gcp-terraform-demo-474514.iam.gserviceaccount.com"

Write-Host "Granting Cloud Build Service Agent role..." -ForegroundColor Yellow
gcloud projects add-iam-policy-binding $PROJECT_ID `
  --member="serviceAccount:$SERVICE_ACCOUNT" `
  --role="roles/cloudbuild.builds.builder"

Write-Host "`nGranting Cloud Functions Developer role..." -ForegroundColor Yellow
gcloud projects add-iam-policy-binding $PROJECT_ID `
  --member="serviceAccount:$SERVICE_ACCOUNT" `
  --role="roles/cloudfunctions.developer"

Write-Host "`nGranting Service Account User role..." -ForegroundColor Yellow
gcloud projects add-iam-policy-binding $PROJECT_ID `
  --member="serviceAccount:$SERVICE_ACCOUNT" `
  --role="roles/iam.serviceAccountUser"

Write-Host "`nPermissions granted successfully!" -ForegroundColor Green
Write-Host "You can now run the deployment workflow again." -ForegroundColor Green

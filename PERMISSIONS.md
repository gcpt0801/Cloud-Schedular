# IAM Permissions Documentation

This document explains all IAM permissions required for the MIG Scheduler and why each one is necessary.

## 🤔 Why So Many Permissions?

**Cloud Functions Gen2** runs on **Cloud Run** and uses **Cloud Build** automatically for deployment. When you deploy a Cloud Function, Google's infrastructure:
1. Triggers Cloud Build to package your code
2. Creates a container image
3. Pushes to Artifact Registry
4. Deploys to Cloud Run

This automated process requires permissions across multiple service accounts.

---

## 📊 Permission Overview

| Service Account | Role | Purpose |
|----------------|------|---------|
| mig-scheduler | compute.instanceAdmin.v1 | Scale MIG instances |
| mig-scheduler | compute.viewer | Read MIG configuration |
| Cloud Build SA | iam.serviceAccountUser | Deploy as mig-scheduler |
| Cloud Build SA | logging.logWriter | Write build logs |
| Cloud Build SA | artifactregistry.writer | Push containers |
| Cloud Build SA | cloudbuild.builds.builder | Execute builds |
| Cloud Build SA | storage.objectViewer | Read source code |
| Compute Default SA | iam.serviceAccountUser | Use mig-scheduler SA |
| Compute Default SA | cloudfunctions.developer | Deploy functions |
| Compute Default SA | cloudbuild.builds.builder | Trigger builds |
| GCF Admin Robot | iam.serviceAccountUser | Manage function lifecycle |
| Cloud Build Agent | iam.serviceAccountUser | Create containers |
| Eventarc Agent | run.invoker | Trigger function |
| mig-scheduler | run.invoker | Self-invoke capability |

---

## 🔐 Detailed Permission Breakdown

### 1. MIG Scheduler Service Account
**Identity:** `mig-scheduler-sa@{project}.iam.gserviceaccount.com`

**Created by:** You (via Terraform)

**Purpose:** This is the identity your Cloud Function runs as - it's the "user" that executes your Python code.

#### Permissions:
```terraform
roles/compute.instanceAdmin.v1
```
- **Why:** Allows the function to resize MIGs (scale up/down)
- **Without it:** Function cannot change MIG size
- **Grants:** `compute.instanceGroupManagers.update`, `compute.instanceGroups.update`

```terraform
roles/compute.viewer
```
- **Why:** Allows the function to read MIG current state
- **Without it:** Function cannot check current size before scaling
- **Grants:** `compute.instanceGroupManagers.get`, `compute.instanceGroups.list`

---

### 2. Cloud Build Service Account
**Identity:** `{project_id}@cloudbuild.gserviceaccount.com`

**Created by:** Google (automatically exists in every project)

**Purpose:** Executes the container build process when deploying Cloud Functions.

#### Why Cloud Build?
Cloud Functions Gen2 doesn't deploy Python code directly - it:
1. Takes your `main.py` + `requirements.txt`
2. Creates a Dockerfile automatically
3. Builds a container image
4. Stores in Artifact Registry
5. Deploys container to Cloud Run

#### Permissions:
```terraform
roles/iam.serviceAccountUser on project
```
- **Why:** Needs to deploy the function with mig-scheduler SA as the runtime identity
- **Without it:** Cannot set service account for the function
- **Grants:** `iam.serviceAccounts.actAs`

```terraform
roles/logging.logWriter
```
- **Why:** Write build logs to Cloud Logging
- **Without it:** No visibility into build process
- **Grants:** `logging.logEntries.create`

```terraform
roles/artifactregistry.writer
```
- **Why:** Push container images to Artifact Registry
- **Without it:** Build succeeds but cannot store image
- **Grants:** `artifactregistry.repositories.uploadArtifacts`

```terraform
roles/cloudbuild.builds.builder
```
- **Why:** Execute build steps and access build resources
- **Without it:** Build cannot start
- **Grants:** `cloudbuild.builds.create`, `cloudbuild.builds.get`

```terraform
roles/storage.objectViewer on function source bucket
```
- **Why:** Read your `main.py` and `requirements.txt` from GCS
- **Without it:** Build has no source code to work with
- **Grants:** `storage.objects.get`, `storage.objects.list`

```terraform
roles/iam.serviceAccountUser on mig-scheduler SA
```
- **Why:** Allows Cloud Build to deploy function as mig-scheduler SA
- **Without it:** Cannot assign SA to function
- **Grants:** `iam.serviceAccounts.actAs`

---

### 3. Compute Engine Default Service Account
**Identity:** `{project_id}-compute@developer.gserviceaccount.com`

**Created by:** Google (default SA for Compute Engine)

**Purpose:** Cloud Functions Gen2 infrastructure uses this SA to orchestrate deployment.

#### Permissions:
```terraform
roles/iam.serviceAccountUser
```
- **Why:** Needs to use mig-scheduler SA during deployment
- **Without it:** Deployment orchestration fails
- **Grants:** `iam.serviceAccounts.actAs`

```terraform
roles/cloudfunctions.developer
```
- **Why:** Deploy and manage Cloud Functions resources
- **Without it:** Cannot create or update functions
- **Grants:** `cloudfunctions.functions.create`, `cloudfunctions.functions.update`

```terraform
roles/cloudbuild.builds.builder
```
- **Why:** Trigger Cloud Build when deploying function
- **Without it:** Deployment cannot start build process
- **Grants:** `cloudbuild.builds.create`

---

### 4. Service Agents (Google-Managed)
These are Google's internal service accounts that power Cloud Functions behind the scenes.

#### a) Cloud Functions Admin Robot
**Identity:** `service-{project_number}@gcf-admin-robot.iam.gserviceaccount.com`

**Created by:** Google (automatically when enabling Cloud Functions API)

**Purpose:** Google's backend service that manages Cloud Functions lifecycle.

**Permission:**
```terraform
roles/iam.serviceAccountUser on mig-scheduler SA
```
- **Why:** Google's Cloud Functions service needs to manage your function
- **Without it:** Function lifecycle events (create, update, delete) fail
- **Grants:** Internal management capabilities

#### b) Cloud Build Service Agent
**Identity:** `service-{project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com`

**Created by:** Google (automatically when enabling Cloud Build API)

**Purpose:** Internal agent that executes Cloud Build operations.

**Permission:**
```terraform
roles/iam.serviceAccountUser on mig-scheduler SA
```
- **Why:** Needs to set SA during container build process
- **Without it:** Container cannot be tagged with correct SA
- **Grants:** Build-time SA assignment

---

### 5. Cloud Run Invoker Permissions
Cloud Functions Gen2 runs on Cloud Run, so invocation requires Cloud Run IAM.

#### a) Eventarc Service Agent
**Identity:** `service-{project_number}@gcp-sa-eventarc.iam.gserviceaccount.com`

**Permission:**
```terraform
roles/run.invoker on both Cloud Functions
```
- **Why:** Eventarc forwards Pub/Sub messages to your function
- **Without it:** Messages arrive but function never triggers
- **Grants:** `run.routes.invoke`

#### b) MIG Scheduler Service Account
**Identity:** `mig-scheduler-sa@{project}.iam.gserviceaccount.com`

**Permission:**
```terraform
roles/run.invoker on both Cloud Functions
```
- **Why:** Function needs to invoke itself (Cloud Run requirement)
- **Without it:** Internal function calls fail
- **Grants:** `run.routes.invoke`

---

## 🔄 Complete Deployment Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Terraform Apply                                              │
│    • Creates service accounts                                   │
│    • Assigns IAM permissions                                    │
│    • Uploads source code to GCS bucket                          │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Cloud Functions Deployment Request                           │
│    • Terraform requests function creation                       │
│    • Specifies: source location, runtime, SA                    │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Compute Engine SA Orchestrates                               │
│    ✓ Uses: cloudfunctions.developer                             │
│    ✓ Uses: iam.serviceAccountUser                               │
│    • Initiates deployment workflow                              │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. Cloud Build Triggered                                        │
│    ✓ Uses: storage.objectViewer (read source from GCS)          │
│    ✓ Uses: cloudbuild.builds.builder (execute build)            │
│    • Downloads main.py, requirements.txt                        │
│    • Generates Dockerfile                                       │
│    • Runs: pip install -r requirements.txt                      │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Container Image Creation                                     │
│    ✓ Uses: artifactregistry.writer (push image)                 │
│    ✓ Uses: logging.logWriter (write logs)                       │
│    • Builds container with Python + dependencies               │
│    • Tags with mig-scheduler SA                                 │
│    • Pushes to Artifact Registry                                │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. Cloud Run Deployment                                         │
│    ✓ Uses: iam.serviceAccountUser (assign SA to function)       │
│    • Deploys container to Cloud Run                             │
│    • Sets runtime SA: mig-scheduler-sa                          │
│    • Configures Eventarc trigger                                │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 7. Function Ready                                               │
│    • Cloud Scheduler → Pub/Sub → Eventarc → Function            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ 8. Runtime Execution (When Triggered)                           │
│    ✓ Eventarc uses: run.invoker (trigger function)              │
│    ✓ Function uses: compute.instanceAdmin.v1 (scale MIG)        │
│    ✓ Function uses: compute.viewer (read MIG state)             │
│    • Pub/Sub message arrives                                    │
│    • Eventarc invokes Cloud Run service                         │
│    • Python code executes as mig-scheduler-sa                   │
│    • Scales MIG via Compute Engine API                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## ❓ Common Questions

### Q: Why does Cloud Build need `serviceAccountUser` twice?
A: Once on the project (to deploy resources) and once on mig-scheduler SA (to assign it to the function).

### Q: Can I reduce these permissions?
A: No - these are the minimum required by Google's Cloud Functions Gen2 architecture. Removing any permission will cause deployment or runtime failures.

### Q: Why do service agents need permissions on my SA?
A: Google's internal services (gcf-admin-robot, gcp-sa-cloudbuild) manage your function's lifecycle and need to act as your SA.

### Q: What if I deploy manually via `gcloud`?
A: You'd still need the same permissions - Cloud Build is always used behind the scenes for Cloud Functions Gen2.

### Q: Why `run.invoker` instead of `cloudfunctions.invoker`?
A: Cloud Functions Gen2 runs on Cloud Run infrastructure, so it uses Cloud Run IAM roles.

---

## 🧹 What We Removed

Previously, we had a `grant-permissions.ps1` script with manual `gcloud` commands. That's now **completely automated** in Terraform:

**Before (Manual):**
```powershell
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:..." \
  --role="roles/..."
```

**After (Automated):**
```terraform
resource "google_project_iam_member" "..." {
  project = var.project_id
  role    = "roles/..."
  member  = "serviceAccount:..."
}
```

---

## 🔒 Security Best Practices

✅ **Least Privilege:** Each SA has only the permissions it needs
✅ **Service-Specific SAs:** Not using default/broad permissions
✅ **No Owner Roles:** No excessive admin permissions granted
✅ **Scoped Bindings:** Storage permissions scoped to specific bucket
✅ **Automated:** All permissions in version control, no manual changes

---

## 📚 References

- [Cloud Functions IAM](https://cloud.google.com/functions/docs/securing/function-identity)
- [Cloud Build IAM](https://cloud.google.com/build/docs/iam-roles-permissions)
- [Cloud Run IAM](https://cloud.google.com/run/docs/securing/managing-access)
- [Service Agents](https://cloud.google.com/iam/docs/service-agents)
- [Compute Engine IAM](https://cloud.google.com/compute/docs/access/iam)

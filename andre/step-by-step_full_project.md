# Run the Full Project on Your AWS Account

Run all commands in **Git Bash**, from the repo root. The cluster costs **~US$ 16/day**, so destroy it the same day (step 8).

---

## 1. Install the GitHub CLI and log in

1. Install it:
   ```bash
   winget install --id GitHub.cli -e
   ```
2. Log in, answering **GitHub.com → HTTPS → Yes → Login with a web browser**:
   ```bash
   gh auth login
   ```

---

## 2. Create an AWS user for this project

1. In the AWS console (as root), go to **IAM → Users → Create user**.
2. Name it `eks-ws-deployer` → **Next**.
3. Choose **Attach policies directly**, check `AdministratorAccess` → **Next** → **Create user**.
4. Open the user → **Security credentials** tab → **Create access key**.
5. Choose **Command Line Interface (CLI)**, check the confirmation box → **Next** → **Create access key**.
6. Copy the **Access key ID** and the **Secret access key**. The secret is shown only once.
7. Save the key on your machine (region `us-east-2`, output `json`):
   ```bash
   aws configure --profile eks-ws
   ```

---

## 3. Set the project variables

1. Get your account ID:
   ```bash
   aws sts get-caller-identity --profile eks-ws --query Account --output text
   ```
2. Fill in `.env` at the repo root:
   ```bash
   AWS_PROFILE=eks-ws
   AWS_REGION=us-east-2
   ACCOUNT_ID=<account-id>
   STATE_BUCKET=eks-ws-tfstate-<account-id>
   REPO_URL=https://github.com/<your-user>/<repo-name>
   ```
3. Load it. Repeat this in every new terminal:
   ```bash
   set -a; source .env; set +a
   ```

---

## 4. Point the project to your AWS account and repo

1. Create the Terraform state bucket and use it:
   ```bash
   aws s3api create-bucket --bucket "$STATE_BUCKET" --region us-east-1
   sed -i "s/cjmm-datahandson-configs/$STATE_BUCKET/" infra/terraform/envs/*/backend.tf
   ```
2. Replace the original account ID:
   ```bash
   git grep -l 093499160510 | xargs sed -i "s/093499160510/$ACCOUNT_ID/g"
   ```
3. Replace the original repo URL:
   ```bash
   OLD=https://github.com/cicerojmm/treinamentoDataHandsLakehouseOpenSourceAWS
   git grep -l "$OLD" | xargs sed -i "s#$OLD#$REPO_URL#g"
   ```
4. Create the image repositories in ECR (type `yes` when asked):
   ```bash
   cd infra/terraform/envs/shared && terraform init && terraform apply && cd -
   ```

---

## 5. Create the GitHub repo and its secrets

1. Get a free license: on <https://www.min.io/pricing>, choose **Get Started** under **AIStor Free**. Then copy the key from <https://subnet.min.io> → **Deployments** → **License Key**.
2. Create the repo:
   ```bash
   gh repo create <repo-name> --public --source=. --remote=origin
   ```
3. Add the secrets. Each command asks for the value:
   ```bash
   gh secret set AWS_ACCESS_KEY_ID        # Access key ID from step 2
   gh secret set AWS_SECRET_ACCESS_KEY    # Secret access key from step 2
   gh secret set MINIO_LICENSE            # license from item 1
   ```
4. On GitHub, open the repo → **Settings → Actions → General**. Under **Workflow permissions**, choose **Read and write permissions** → **Save**.

---

## 6. Push the code

1. Commit and push:
   ```bash
   git add -A
   git commit -m "chore: point project to my AWS account"
   git push -u origin main
   ```
2. Wait until no workflow is running:
   ```bash
   gh run list
   ```

---

## 7. Create the cluster and deploy the platform

1. Start the deploy and follow it (~45 min):
   ```bash
   gh workflow run infra-bootstrap.yml
   gh run watch
   ```
2. Connect `kubectl` to the cluster:
   ```bash
   aws eks update-kubeconfig --name data-platform-eks --region us-east-2 --alias data-platform-eks
   ```
3. Check that every application shows **Synced / Healthy**:
   ```bash
   kubectl get applications -n argocd
   ```
4. List the service URLs (the **EXTERNAL-IP** column):
   ```bash
   kubectl get svc -A | grep LoadBalancer
   ```
5. Configure the UIs, in this order: `docs/runbooks/airbyte-eks-setup.md`, `metabase-trino-setup.md`, `openmetadata-connectors-setup.md`.
6. In Airflow, trigger the `dbt_movielens` DAG.

---

## 8. Destroy everything

1. Delete the applications first. This removes the load balancers and disks:
   ```bash
   KUBE_CONTEXT=data-platform-eks bash scripts/teardown-argocd-apps.sh 600
   ```
2. Destroy the cluster (type `yes` when asked):
   ```bash
   cd infra/terraform/envs/eks && terraform init && terraform destroy && cd -
   ```
3. Confirm that no load balancer is left. The result must be `[]`:
   ```bash
   aws elbv2 describe-load-balancers --region us-east-2 --query 'LoadBalancers[].LoadBalancerName'
   ```

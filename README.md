# Beacon — Rolling Deployments on AWS EC2 Auto Scaling

**Infrastructure as Code · AWS · Terraform · Docker · GitHub Actions**

Beacon is a cloud deployment project that demonstrates how to provision, deploy, and operate a containerized ASP.NET Core API on AWS using Terraform and GitHub Actions.

The project focuses on practical DevOps engineering: automated infrastructure provisioning, secure CI/CD authentication with AWS OIDC, container image scanning, rolling instance deployments, health checks, and controlled infrastructure teardown.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [Technology Stack](#technology-stack)
- [Key Features](#key-features)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Local Development](#local-development)
- [Initial AWS Setup](#initial-aws-setup)
- [CI/CD Workflows](#cicd-workflows)
- [Deploying the Application](#deploying-the-application)
- [API Reference](#api-reference)
- [Security Considerations](#security-considerations)
- [Cost Management](#cost-management)
- [Destroying the Infrastructure](#destroying-the-infrastructure)
- [Troubleshooting](#troubleshooting)
- [Design Decisions](#design-decisions)
- [Future Improvements](#future-improvements)

---

## Project Overview

The goal of Beacon is to demonstrate how a small stateless application can be deployed to AWS using Infrastructure as Code and an automated delivery pipeline without requiring a Kubernetes cluster.

The application is a lightweight diagnostic API. It reports information about the running application version and the EC2 instance serving the request. This makes it possible to observe load balancing, instance replacement, and rolling deployments.

Terraform manages the infrastructure, Docker packages the application, Amazon ECR stores the container image, and GitHub Actions automates testing and deployment. GitHub Actions authenticates to AWS through OpenID Connect (OIDC), avoiding long-lived AWS access keys in the deployment workflow.

This is a learning and portfolio project rather than a production-ready application. Its primary purpose is to demonstrate cloud infrastructure design, deployment automation, security practices, and operational troubleshooting.

## Architecture

```text
                         DEVELOPER
                             |
                             v
                     GITHUB REPOSITORY
                       /           \
                      v             v
                 CI WORKFLOW   MANUAL DEPLOY WORKFLOW
                 - Build/test  1. Build & scan image
                 - Trivy scan  2. Push image to ECR
                 - Terraform   3. terraform apply
                   fmt/validate       |
                   / PR plan          v
                              Launch Template updated
                                      |
                                      v
                              ASG rolling instance refresh
                                      |
                                      v
                              Auto Scaling Group replaces
                              instances with new version

AMAZON ECR ----------------> EC2 instances pull image
                                   on startup

                        RUNTIME REQUEST FLOW

USERS --> Application Load Balancer --> Target Group --> EC2 instances
                                                         (managed by ASG)
                                                              |
                                                              v
                                                       Beacon API
                                                       containers

Terraform provisions and manages AWS infrastructure.
Terraform state is stored in Amazon S3.
GitHub Actions authenticates to AWS using GitHub OIDC.

```

### Request Flow

1. A client sends an HTTP request to the public Application Load Balancer (ALB).
2. The ALB forwards traffic to healthy, registered EC2 instances through the target group on port `80`.
3. Each EC2 instance runs the Beacon API inside a Docker container listening on port `8080`.
4. Docker maps the EC2 host's port `80` to the container's port `8080`.
5. The ALB uses the `/health` endpoint to check whether each target is healthy.

### Deployment Flow

1. The CI workflow builds and tests the application, runs a Trivy image scan, and validates the Terraform configuration. On pull requests, it also runs a Terraform plan.
2. The deployment workflow checks whether an image tagged with the current Git commit SHA already exists in Amazon ECR. If it does not, the workflow builds, scans, and pushes the image.
3. Terraform applies the infrastructure configuration using the current commit SHA as the image tag, updating the launch template when required.
4. The Auto Scaling Group performs the configured rolling instance refresh when the launch template changes. New EC2 instances pull the configured image from ECR during startup and run the Beacon API container.
5. GitHub Actions polls the public `/health` endpoint and publishes the application URL after a successful health check.

The ALB health check and the GitHub Actions health check serve different purposes. The ALB continuously evaluates individual targets, while the workflow verifies that the application is reachable through the public endpoint after deployment.

## Technology Stack

| Component | Purpose |
|---|---|
| AWS | Cloud infrastructure |
| Terraform | Infrastructure as Code |
| Amazon EC2 Auto Scaling | Instance lifecycle management and replacement |
| Application Load Balancer | Public HTTP traffic distribution and target health checks |
| Amazon VPC | Network isolation and subnet layout |
| NAT Gateway | Outbound connectivity for private instances |
| Amazon ECR | Container image storage |
| Amazon S3 | Remote Terraform state and state locking |
| Docker | Application containerization |
| Docker Compose | Local development |
| ASP.NET Core 10 | Minimal API runtime |
| GitHub Actions | CI/CD automation |
| GitHub OIDC and AWS IAM | Short-lived AWS authentication |
| Trivy | Container vulnerability scanning |
| AWS Systems Manager | Instance access without SSH |
| xUnit and WebApplicationFactory | API integration testing |

## Key Features

### Infrastructure as Code

- Modular Terraform configuration for networking, load balancing, and compute.
- Separate bootstrap and application infrastructure stacks.
- Remote main-stack Terraform state in a versioned S3 bucket.
- Native S3 state locking through Terraform's `use_lockfile` functionality.
- Security groups that restrict instance ingress to the ALB security group.

### Containerized Application

- Multi-stage Docker build.
- Non-root application container.
- Explicit container port `8080`.
- Docker Compose configuration for local development.
- Version and instance metadata exposed through API endpoints.

### Deployment Automation

- Separate CI, Deploy, and Destroy workflows.
- Manual AWS deployment with an explicit confirmation checkbox.
- Git commit SHA image tags for traceability.
- Trivy image scanning before publishing.
- Terraform-driven launch template updates and rolling instance refresh.
- Automated health verification before the workflow reports success.

### Security

- GitHub Actions uses AWS OIDC rather than long-lived AWS access keys.
- Dedicated IAM policies for deployment, ECR, Terraform state, and related IAM operations.
- IMDSv2 is required for EC2 metadata access.
- No SSH key pair is configured on the application launch template.
- EC2 instances are placed in private subnets.

## Repository Structure

```text
aws-ec2-autoscaling-deploy/
├── .github/
│   └── workflows/
│       ├── ci.yml
│       ├── deploy.yml
│       └── destroy.yml
├── app/
│   ├── BeaconApi/
│   │   ├── Dockerfile
│   │   └── ...
│   └── BeaconApi.Tests/
│       └── ...
├── bootstrap/
│   ├── terraform.tfvars.example
│   ├── terraform.tfstate          # Local, gitignored
│   └── ...
├── terraform/
│   ├── modules/
│   │   ├── alb/
│   │   ├── compute/
│   │   └── network/
│   ├── backend.tf
│   ├── backend.hcl.example
│   ├── main.tf
│   ├── variables.tf
│   └── ...
├── scripts/
│   ├── bootstrap.sh
│   └── destroy-bootstrap.sh       # Final bootstrap teardown
└── compose.yaml
```

The repository has two Terraform roots:

- `bootstrap/` creates the resources needed for future deployments, including the state bucket, ECR repository, and GitHub Actions IAM configuration.
- `terraform/` manages the application infrastructure.

The bootstrap stack uses local Terraform state, while the main application stack uses remote state in S3.

## Prerequisites

Before deploying, you need:

- An AWS account with permissions to create the required infrastructure.
- AWS CLI v2, configured for the intended AWS account.
- Terraform `>= 1.11`.
- Docker and Docker Compose.
- Git and Bash.
- GitHub CLI (`gh`) authenticated to the correct GitHub account.
- A GitHub repository with permission to configure repository variables and Actions workflows.

For local application development and testing, the .NET 10 SDK is also required.

Verify your AWS and GitHub CLI setup:

```bash
aws sts get-caller-identity
gh auth status
```

Review the current AWS pricing before creating infrastructure. The main stack includes resources that can incur charges while running.

## Local Development

Build and start the application using Docker Compose:

```bash
docker compose up --build
```

The API is available locally at:

```text
http://localhost:8080
```

Test the endpoints:

```bash
curl http://localhost:8080/
curl http://localhost:8080/version
curl http://localhost:8080/health
```

To stop the local container:

```bash
docker compose down
```

Run the automated tests with:

```bash
dotnet test app/BeaconApi.Tests/BeaconApi.Tests.csproj
```

The test project covers the API's health, root, and version endpoints.

## Initial AWS Setup

The bootstrap stack must be configured before deploying the main application infrastructure.

### 1. Configure the bootstrap variables

From the repository root:

```bash
cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars
```

Edit `bootstrap/terraform.tfvars` and review the account-specific configuration.

In particular, check the `create_oidc_provider` setting:

- Set it to `true` if the AWS account does not already have the required GitHub OIDC provider and this stack is intended to create it.
- Set it to `false` when an appropriate provider already exists in the account.

A shared OIDC provider should not be deleted merely because this project is being retired.

Do not commit `bootstrap/terraform.tfvars` or Terraform state files.

### 2. Review and apply the bootstrap stack

Initialize Terraform:

```bash
terraform -chdir=bootstrap init
```

Review the planned changes:

```bash
terraform -chdir=bootstrap plan
```

Apply only after checking the plan:

```bash
terraform -chdir=bootstrap apply
```

The bootstrap stack prepares the resources required by the deployment pipeline, including:

- The S3 Terraform state bucket.
- The `beacon-api` ECR repository.
- The GitHub Actions IAM role and its associated policies.

### 3. Configure the GitHub repository

Run the repository helper:

```bash
./scripts/bootstrap.sh
```

The script uses bootstrap outputs to configure the GitHub repository variables and production environment needed by the workflows.

The deployment workflow currently uses these repository variables:

| Variable | Purpose |
|---|---|
| `AWS_REGION` | AWS deployment region |
| `AWS_ROLE_ARN` | IAM role assumed by GitHub Actions |
| `ECR_REPOSITORY` | ECR repository name |
| `TF_STATE_BUCKET` | S3 bucket containing main Terraform state |

Do not store AWS access keys in GitHub repository variables. The workflow uses OIDC to assume the configured IAM role.

## CI/CD Workflows

The repository contains three main GitHub Actions workflows.

### CI — `.github/workflows/ci.yml`

The CI workflow runs on relevant pushes to `main` and pull requests.

It validates the application and infrastructure configuration, including application build and tests, Docker image checks, Trivy scanning, Terraform formatting and validation, and the applicable Terraform plan checks.

The CI workflow does not deploy the application infrastructure.

### Deploy — `.github/workflows/deploy.yml`

Deployment is manual. A normal push to `main` does not automatically create AWS resources.

To deploy:

1. Open the repository's **Actions** tab.
2. Select **Deploy**.
3. Click **Run workflow**.
4. Select the `confirm_deploy` checkbox acknowledging that deployment creates AWS resources and may incur charges.
5. Start the workflow.

The workflow runs the following jobs:

1. **Validate:** verifies the explicit deployment confirmation.
2. **Build and push:** checks whether an image already exists for the commit SHA, builds and scans the image when necessary, and pushes it to ECR.
3. **Deploy:** initializes Terraform, applies the main stack, and waits for the public `/health` endpoint to respond successfully.

The health-check step polls every 15 seconds for up to 600 seconds. After a successful check, the workflow summary includes the public application URL.

### Destroy — `.github/workflows/destroy.yml`

The Destroy workflow is also manual.

To run it:

1. Open **Actions**.
2. Select **Destroy**.
3. Click **Run workflow**.
4. Enter `destroy` exactly when prompted.
5. Start the workflow and verify its result.

It runs `terraform destroy` against the main application stack.

**The normal Destroy workflow does not delete the bootstrap S3 bucket, ECR repository, GitHub Actions IAM resources, or the shared OIDC provider.**

## Deploying the Application

After completing the initial setup, deploy through GitHub Actions as described above.

Once the workflow completes successfully, open the application URL shown in the workflow summary.

You can also retrieve the URL from Terraform while the infrastructure exists:

```bash
terraform -chdir=terraform output -raw app_url
```

The application currently uses HTTP on port `80`; HTTPS and a custom domain are not configured.

Test the public endpoint:

```bash
curl http://<ALB-DNS-NAME>/
curl http://<ALB-DNS-NAME>/version
curl http://<ALB-DNS-NAME>/health
```

Replace `<ALB-DNS-NAME>` with the URL published by the workflow.

The root endpoint returns the version and instance metadata. Consecutive requests may be served by different EC2 instances, allowing you to observe load balancing.

## API Reference

| Method | Endpoint | Purpose |
|---|---|---|
| `GET` | `/` | Returns a greeting, version, instance ID, availability zone, hostname, and timestamp |
| `GET` | `/version` | Returns the application version |
| `GET` | `/health` | Returns a healthy response when the health endpoint is available |

### Example root response

```json
{
  "message": "Hello from Beacon!",
  "version": "<git-commit-sha>",
  "instanceId": "i-0123456789abcdef0",
  "availabilityZone": "eu-central-1a",
  "hostname": "ip-10-0-11-42",
  "timestamp": "2026-10-27T14:23:01.123Z"
}
```

The values above are illustrative; the instance ID, hostname, version, and timestamp depend on the running instance.

### Version endpoint

```json
{
  "version": "<git-commit-sha>"
}
```

### Health endpoint

`GET /health` returns a successful HTTP response when the endpoint is healthy. The ALB uses the same route for target health checks.

## Security Considerations

### AWS OIDC Authentication

GitHub Actions uses OIDC to assume a dedicated AWS IAM role with temporary credentials. The workflows do not require long-lived AWS access keys stored as GitHub secrets.

The role's trust policy restricts which GitHub repository identity can assume it. Changes to repository identity configuration must remain consistent with the bootstrap configuration.

### IAM Permissions

The deployment role uses dedicated policies for the AWS actions required by the pipeline instead of unrestricted administrator permissions.

The instance role has ECR pull and Systems Manager permissions required by the application instances.

### Network Access

- EC2 instances are placed in private subnets.
- The instances accept application traffic from the ALB security group on port `80`.
- The ALB is internet-facing and listens on HTTP port `80`.
- The launch template requires IMDSv2 and uses a metadata hop limit of `1`.
- Instances are accessed through AWS Systems Manager rather than SSH.

### Terraform State

The main Terraform state is stored in a private S3 bucket with versioning and server-side encryption. Native S3 locking is enabled through Terraform's `use_lockfile` functionality.

Terraform state may contain sensitive infrastructure attributes. Do not commit state files, `terraform.tfvars`, account-specific backend configuration, credentials, or other private configuration to Git.

## Cost Management

The project is intended as a learning and demonstration environment. It is not free to leave running indefinitely.

When the main stack is provisioned, potential charges include:

- EC2 instance runtime.
- Application Load Balancer hourly and capacity-unit usage.
- NAT Gateway hourly and data-processing charges.
- Allocated public IPv4 addresses.
- Data transfer.
- S3 and ECR storage.

A single NAT Gateway is used to reduce costs compared with deploying one per Availability Zone, but it introduces an availability trade-off for outbound connectivity.

The normal Destroy workflow removes the main application infrastructure after a demo session. The bootstrap resources are retained to make later deployments easier.

Review current prices using the [AWS Pricing Calculator](https://calculator.aws/) before deploying, and verify that the Destroy workflow succeeds before leaving the environment unused.

## Destroying the Infrastructure

There are two distinct teardown operations.

### Normal teardown — main application infrastructure

Use the manual **Destroy** workflow in GitHub Actions and enter `destroy` when prompted.

This removes the main stack, including its EC2 Auto Scaling Group, load balancer, networking resources, and associated application infrastructure managed by Terraform.

After a successful Destroy run, verify that no project EC2 instances, Auto Scaling Groups, load balancers, NAT Gateways, or allocated Elastic IPs remain.

The following bootstrap resources are intentionally retained:

- S3 Terraform state bucket.
- ECR repository and any retained images.
- GitHub Actions IAM role and policies.
- Shared GitHub OIDC provider.

Retaining these resources allows the environment to be provisioned again without rebuilding the bootstrap setup.

### Permanent teardown — bootstrap infrastructure

`scripts/destroy-bootstrap.sh` is a separate, final teardown utility intended for when the project is permanently retired.

It is designed to remove the project's ECR repository, IAM role and associated policies, and the versioned S3 Terraform state bucket. It intentionally preserves the shared GitHub OIDC provider.

**Before using this script:**

- Ensure the main application infrastructure has been destroyed.
- Verify that the bootstrap resources are dedicated to this project.
- Review the script and its confirmation prompts.
- Remember that deleting the state bucket and bootstrap resources means the bootstrap must be recreated before another deployment.

**Account-specific configuration**

The `scripts/destroy-bootstrap.sh` script is configured for the original project owner's AWS account. If you use this project in a different AWS account, review and update the following values in the script before running it:

- **AWS account ID:** Replace `554422868760` in the AWS account verification check with your own AWS account ID.
- **AWS region:** Update `AWS_DEFAULT_REGION` to match the region where your bootstrap resources are deployed.
- **S3 state bucket:** Update `BUCKET` to match your bootstrap S3 bucket name.
- **Terraform state key:** Update `beacon/infra.tfstate` in the S3 state path if you use a different key in your Terraform backend configuration.
- **Project-specific resource names and tags:** If you change the project naming convention, review the ECR repository and IAM role names shown in the confirmation message, as well as the `Project=beacon` tag filters used to check for remaining application resources.
- **Terraform state resource addresses:** If you modify the bootstrap Terraform resource names, review the resource addresses used by the `terraform state rm` command to ensure they match your actual bootstrap state.

Keep the account verification, resource checks, and explicit confirmation prompt in place. Verify that all configured values match your actual infrastructure before running this destructive script.

The script expects the GitHub OIDC provider to be external to the bootstrap Terraform state. If the provider is managed as a Terraform resource in that state, the script will abort rather than risk deleting it. Review the state and OIDC configuration before proceeding.

## Troubleshooting

### The ALB health check fails

Check the target group health status and verify that the application container is running on the EC2 instances.

Useful commands:

```bash
aws elbv2 describe-target-health \
  --target-group-arn <TARGET-GROUP-ARN> \
  --region eu-central-1
```

Connect to an instance through Systems Manager and inspect the startup log:

```bash
sudo cat /var/log/cloud-init-output.log
sudo docker ps -a
sudo docker logs beacon
```

Common causes include user-data failures, Docker startup errors, failed ECR image pulls, or a container that does not respond on the expected port.

### GitHub Actions cannot authenticate to AWS

- Verify that the configured `AWS_ROLE_ARN` is correct.
- Check the bootstrap configuration for the correct GitHub repository identity.
- Verify the IAM role's OIDC trust conditions and attached permissions.
- Review the workflow logs for the exact AWS authorization error.

### Terraform initialization fails

- Confirm that the bootstrap stack has created the state bucket.
- Verify that `TF_STATE_BUCKET` and `AWS_REGION` are correct.
- Check that the deployment role has the required state access permissions.
- Ensure the bootstrap resources have not been permanently removed.

### The deployment times out at `/health`

- Inspect the Auto Scaling Group and ALB target health.
- Confirm that the EC2 user-data script completed successfully.
- Check whether the `beacon` Docker container exists and is running.
- Inspect cloud-init output and Docker logs before increasing timeouts further.

## Design Decisions

| Decision | Reasoning |
|---|---|
| EC2 Auto Scaling instead of EKS | A small stateless API does not require a Kubernetes control plane, reducing operational complexity and fixed infrastructure costs. |
| Modular Terraform | Separates networking, load balancing, and compute into understandable components. |
| Separate bootstrap stack | Creates the state bucket and deployment resources needed before the main stack can be applied. |
| S3 remote state with native locking | Centralizes the main state and prevents concurrent state modifications. |
| Git commit SHA image tags | Associates each published container image with a specific source revision. |
| ECR immutable tags | Prevents existing published tags from being overwritten. |
| Manual deployment confirmation | Prevents a regular source-code push from unexpectedly creating billable AWS infrastructure. |
| One NAT Gateway | Reduces recurring costs while trading off outbound connectivity availability across Availability Zones. |
| Private EC2 instances and SSM | Avoids exposing SSH access to the internet. |
| ALB health checks and rolling instance refresh | Replaces unhealthy instances and supports controlled application updates. |

## Lessons Learned

The project provided practical experience with debugging failures that crossed infrastructure, identity, and application-startup boundaries.

### Terraform IAM permissions

The deployment initially failed because `elasticloadbalancing:DescribeTargetHealth` was scoped to a target group ARN. This action requires `Resource: "*"`, so the policy was corrected and applied.

### Terraform templates and Bash syntax

The EC2 user-data template initially used invalid command substitutions. The Bash script failed before authenticating to ECR or starting the Docker container. The rendered user-data output revealed the error, and the three command substitutions were corrected.

### Auto Scaling health-check timing

The Auto Scaling Group grace period and instance warmup were increased to give newly launched instances enough time to initialize. The final working deployment verified that the infrastructure, Docker startup process, and public health check could complete successfully together.

These issues demonstrated why a successful Terraform apply is not sufficient by itself: the deployed application must also start correctly and respond through its real network path.

## Future Improvements

Potential improvements include:

- HTTPS using AWS Certificate Manager and a custom domain.
- Additional integration tests against the deployed environment.
- CloudWatch metrics, alarms, and operational dashboards.
- Automated dependency-update checks.
- More advanced rollout strategies.
- Further review of NAT Gateway availability and cost trade-offs.

These are future ideas and are not represented as currently implemented functionality.

---
## Developer

Ákos Bukovinszki\
https://github.com/bukovinszkiakos

------------------------------------------------------------------------

## License

MIT License

---

<p align="right">(<a href="#top">Back to top</a>)</p>

*Beacon is a learning and demonstration project. Review the Terraform configuration, IAM policies, and GitHub Actions workflows before reusing it in another AWS environment.*

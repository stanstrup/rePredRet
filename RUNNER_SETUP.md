# Self-Hosted GitHub Actions Runner Setup

This guide sets up a self-hosted GitHub Actions runner using Docker Compose with the **myoung34/github-runner** image to bypass GitHub's job time limits.

## Runner Scope Options

- **Repository-level**: Only serves one repository (limited use)
- **Organization-level** (what we're setting up): Serves ALL repos in the organization
- **Enterprise-level**: For multiple organizations

**This guide uses organization-level runners**, which is ideal for managing multiple projects. One runner handles jobs from all repos in the organization!

This is equivalent to **GitLab's group-level runners** - just register once at the organization level and it works everywhere.

## Step 0: Prerequisites

- Docker and Docker Compose installed
- Access to `/var/run/docker.sock` on your host
- GitHub account with organization `stanstrup-metabolomics` (already done)

## Step 1: Create a GitHub Personal Access Token (PAT)

This is the easiest authentication method for organization-level runners.

1. Go to: https://github.com/settings/tokens
2. Click **Generate new token** → **Generate new token (classic)**
3. Give it a name: `github-runner`
4. Select scopes:
   - `repo` (full control of private repositories)
   - `admin:org` (required for organization-level runners)
   - `workflow` (for workflow control)
   - `notifications` (optional, for status notifications)
5. Click **Generate token**
6. **Copy the token immediately** (you won't see it again!)

## Step 2: Set Up Environment Variables

Create a `.github_runner.env` file in the directory where you'll run docker-compose:

```bash
# GitHub Personal Access Token (with admin:org scope)
ACCESS_TOKEN=ghp_your_token_here

# Organization name
ORG_NAME=stanstrup-metabolomics

# Runner configuration
RUNNER_NAME_PREFIX=docker-runner
RUNNER_GROUP=default
LABELS=docker,linux,ubuntu

# Optional: Make runner ephemeral (auto-removes after each job)
EPHEMERAL=false

# Optional: Disable auto-update (useful in restricted environments)
DISABLE_AUTO_UPDATE=false
```

**Note**: The `github_runner.yml` automatically loads `.github_runner.env` - no need to pass `--env-file` in the command!

## Step 3: Start the Runner

```bash
# Navigate to the directory with github_runner.yml and .github_runner.env
cd /mnt/z/docker/compose

# Start the runner with docker-compose (automatically loads .github_runner.env)
docker-compose --file github_runner.yml up -d

# Check logs (should show "Listening for Jobs")
docker-compose --file github_runner.yml logs -f github-runner
```

**Expected output:**
```
github-runner    | Current runner version: '2.x.x'
github-runner    | Listening for Jobs
```

## Step 4: Verify the Runner is Online

1. Go to https://github.com/organizations/stanstrup-metabolomics/settings/actions/runners
2. You should see your runner with a green dot (online)
3. The runner is now available to ALL repos in the `stanstrup-metabolomics` organization

## Step 5: Update Workflows to Use Your Runner

Your repositories (rePredRet and rePredRet-models) are already in the organization.

Edit `.github/workflows/build-models.yml` in rePredRet and change:

```yaml
jobs:
  build:
    # Change from: runs-on: ubuntu-latest
    runs-on: [self-hosted, docker, linux]
```

The same runner handles jobs from **all repos in the organization**. This is equivalent to GitLab's group-level runners!

## Step 6: Test the Workflow

1. Push a test commit to trigger the workflow, or
2. Go to: https://github.com/stanstrup-metabolomics/rePredRet/actions
3. Click **Run workflow**

You should see the job run on your self-hosted runner with no time limit!

## Troubleshooting

### "Listening for Jobs" not appearing in logs
```bash
# Check if token is valid
docker-compose --file github_runner.yml logs github-runner | grep -i error

# Re-create runner with new token
docker-compose --file github_runner.yml down
# Update .github_runner.env with new PAT
docker-compose --file github_runner.yml up -d
```

### Runner not appearing in GitHub UI
- Verify token is valid (hasn't expired)
- Check ORG_NAME matches exactly: `stanstrup-metabolomics`
- Verify token has correct scopes: `repo`, `admin:org`, `workflow`, and `notifications`
- Check logs for authentication errors

### Docker socket permission denied
```bash
# Check socket permissions
ls -la /var/run/docker.sock

# If not readable, add current user to docker group
sudo usermod -aG docker $USER
```

### Check runner logs
```bash
# Real-time logs
docker-compose --file github_runner.yml logs -f github-runner

# Search for specific messages
docker-compose --file github_runner.yml logs | grep -i "registered\|listening\|error"
```

### Runner needs more resources
Edit `github_runner.yml` and increase resource limits:
```yaml
deploy:
  resources:
    limits:
      cpus: '8'
      memory: 16G
    reservations:
      cpus: '4'
      memory: 8G
```

Then restart:
```bash
docker-compose --file github_runner.yml restart
```

## Removing the Runner

1. Stop the Docker container:
```bash
docker-compose --file github_runner.yml down
```

2. (Optional) Remove the volume:
```bash
docker volume rm runner-work
```

3. Go to https://github.com/organizations/stanstrup-metabolomics/settings/actions/runners
4. Click the three dots next to your runner and select "Remove"

## Running Multiple Runners (Advanced)

To run multiple runners for parallel job execution:

```bash
# Create separate compose files for each runner
cp github_runner.yml github_runner_2.yml

# Create separate env files
cp .github_runner.env .github_runner_2.env

# Edit .github_runner_2.env and update:
# - RUNNER_NAME_PREFIX=docker-runner-2
# - Optionally use different directory: /mnt/z/docker/config_dirs/github-runner-2
```

Start both:
```bash
docker-compose --file github_runner.yml up -d
docker-compose --file github_runner_2.yml -p runner2 up -d
```

Each runner will be available to the organization and can handle jobs in parallel.

## Notes

- **Docker Image**: `myoung34/github-runner` - actively maintained community image from myoung34
- **Authentication**: Use GitHub Personal Access Token (PAT) with scopes: `repo`, `admin:org`, `workflow`, `notifications`
- **Organization**: `stanstrup-metabolomics` - all runners serve all repos in this org
- **Scope**: `RUNNER_SCOPE: 'org'` makes this runner available to all organization repositories
- **Persistent mode**: `EPHEMERAL=false` (default) - runner stays online for multiple jobs
- **Ephemeral mode**: `EPHEMERAL=true` - runner auto-removes after each job (more secure)
- **Storage**: `/mnt/z/docker/config_dirs/github-runner` - persistent configuration and workspace
- **Resource limits**: Adjust based on your system capacity in `github_runner.yml`
- **Docker-in-Docker**: Runner can build and run containers via mounted docker.sock
- **No time limits**: Self-hosted runners have no job duration limits (unlike GitHub's 6-hour limit)
- **Cost**: Free with GitHub Free plan - unlimited runners, only pay for your infrastructure

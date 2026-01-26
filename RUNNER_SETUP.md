# Self-Hosted GitHub Actions Runner Setup

This guide sets up a self-hosted GitHub Actions runner using Docker Compose to bypass GitHub's job time limits.

## Runner Scope Options

- **Repository-level**: Only serves one repository (limited use)
- **Account-level** (what we're setting up): Serves ALL your personal repositories
- **Organization-level**: Serves all repos in an organization (for teams)

**This guide uses account-level runners**, which is ideal for individual developers like you. One runner handles jobs from all your repositories!

This is equivalent to **GitLab's group-level runners** - just register once and it works everywhere.

## Step 1: Get the Runner Token (Account Level)

1. Go to your **personal account settings**: https://github.com/settings/actions/runners
   - **NOT** the repository settings
   - This makes the runner available to ALL your repos

2. Click **New self-hosted runner**
3. Note the token shown in the `Configure` section (valid for 1 hour)

**Note**: If you registered a repository-level runner before, you can still use this. Just get the account-level token for broader access.

## Step 2: Set Up Environment Variables

Create a `.github_runner.env` file in the rePredRet directory:

```bash
# GitHub repository configuration
REPO_URL=https://github.com/stanstrup/rePredRet

# Runner token (get from Step 1 - only valid for 1 hour)
RUNNER_TOKEN=<paste_token_here>

# Optional: Give the runner a name
RUNNER_NAME=docker-runner-1

# Optional: Labels for the runner (comma-separated)
RUNNER_LABELS=docker,linux,long-jobs

# Optional: Make runner ephemeral (auto-removes after job)
EPHEMERAL=false
```

**Note**: The `github_runner.yml` automatically loads `.github_runner.env` - no need to pass `--env-file` in the command!

## Step 3: Start the Runner

```bash
# Navigate to rePredRet directory
cd /path/to/rePredRet

# Start the runner with docker-compose (automatically loads .github_runner.env)
docker-compose -f github_runner.yml up -d

# Check logs
docker-compose -f github_runner.yml logs -f github-runner
```

## Step 4: Verify the Runner is Online

1. Go to https://github.com/settings/actions/runners (your account-level settings)
2. You should see your runner with a green dot (online)
3. This runner will now be available to ALL your repositories

## Step 5: Update Workflows to Use Your Runner

### For rePredRet Repository

Edit `.github/workflows/build-models.yml` and change the `runs-on` line:

```yaml
jobs:
  build:
    # Change this from 'ubuntu-latest' to your runner's labels
    runs-on: [self-hosted, docker, long-jobs]
```

Or use the runner name directly:

```yaml
    runs-on: docker-runner-1
```

### For ANY Other Repository

Since this is an **account-level runner**, you can use it in **any of your repositories**!

In any workflow file in any of your repos, just add:

```yaml
jobs:
  build:
    runs-on: [self-hosted, docker]
```

The same runner handles jobs from all your repositories. This is equivalent to GitLab's group-level runners!

## Step 6: Test the Workflow

Push a test commit to trigger the workflow, or manually trigger it from:
https://github.com/stanstrup/rePredRet/actions

## Troubleshooting

### Runner stuck in offline/stale state
```bash
# Stop and remove the runner
docker-compose -f github_runner.yml down

# Remove the container completely
docker rm github-actions-runner

# Get a new token and start again
```

### Check runner logs
```bash
docker-compose -f github_runner.yml logs -f github-runner
```

### Runner needs more resources
Edit `github_runner.yml` and increase the resource limits:
```yaml
deploy:
  resources:
    limits:
      cpus: '8'      # Change from 4 to 8
      memory: 16G    # Change from 8G to 16G
```

### Docker in Docker issues
Make sure the Docker socket is properly mounted:
```bash
ls -la /var/run/docker.sock
```

Should output something like:
```
srw-rw---- 1 root docker /var/run/docker.sock
```

## Removing the Runner

1. Stop the Docker container:
```bash
docker-compose -f github_runner.yml down
```

2. Go to https://github.com/settings/actions/runners (your account settings)
3. Click the three dots next to your runner and select "Remove"

Note: This removes the runner from ALL your repositories since it's account-level

## Running Multiple Runners (Advanced)

If you want to run multiple jobs in parallel, you can register multiple runners at the account level:

```bash
# Start runner 1 (uses .github_runner.env by default)
docker-compose -f github_runner.yml up -d

# Start runner 2 with a different config file
# First create .github_runner2.env with a different token and name
# Then override the env_file for this instance:
docker-compose -f github_runner.yml --env-file .github_runner2.env -p runner2 up -d
```

For each runner:
1. Get a NEW token from https://github.com/settings/actions/runners
2. Create a new `.github_runner2.env`, `.github_runner3.env`, etc.
3. Give each a different `RUNNER_NAME` (e.g., docker-runner-1, docker-runner-2)
4. Start with different project names: default for first, `-p runner2`, `-p runner3`, etc.

Then all runners are available at your account level and can handle jobs from all repos in parallel!

## Notes

- **Token expiration**: Runner tokens expire after 1 hour. If your runner can't register, get a new token.
- **Persistent runner**: Set `EPHEMERAL=false` to keep the runner available for multiple jobs
- **Ephemeral runner**: Set `EPHEMERAL=true` to auto-remove the runner after each job (more secure, needs re-registration)
- **Resource limits**: Adjust `cpus` and `memory` based on your machine's capacity
- **Docker socket**: The runner needs access to Docker to build/run containers in workflow steps

#!/usr/bin/env bash
# Wire this sandbox to your devbox, and make image builds work.
#
# Run once at the start of the workshop:  bash scripts/bootstrap.sh
#
# You typed exactly one thing into Kiro to make this possible: an IAM role ARN
# (Settings > Agent > Sandbox > IAM Role). That role gives this sandbox short-lived AWS
# credentials for your account. Everything else — your devbox address, your Cognito
# details, your LlamaCloud key — this script reads from AWS SSM using that role. There are
# no secrets to type.
#
# What it does, each step printing a ✅:
#   1. confirms the sandbox has AWS credentials (the role is configured)
#   2. reads your config from SSM
#   3. installs a `docker` shim that routes to podman (Flyte's builder wants `docker buildx`)
#   4. logs podman in to your account's ECR
#   5. writes .flyte/config.yaml (+ .flyte/workshop.env for the token script)
#   6. mints a Cognito token, proving auth works
#   7. calls the devbox, proving it answers

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${REPO_ROOT}/.flyte"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
ENV_FILE="${CONFIG_DIR}/workshop.env"
TOKEN_SCRIPT="${REPO_ROOT}/scripts/flyte-token.sh"
SHIM_SRC="${REPO_ROOT}/scripts/docker-shim.sh"

# Must match ParameterPrefix in provisioning/kiro-sandbox.yaml.
SSM_PREFIX="/workshop"

# The whole workshop is us-east-1. The role gives creds but not a region; default it.
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION}"

fail() { echo ""; echo "❌ $*" >&2; exit 1; }
step() { echo ""; echo "→ $*"; }

# ---------------------------------------------------------------------------
# 1. Confirm the sandbox has AWS credentials
# ---------------------------------------------------------------------------
step "Checking AWS credentials from the sandbox role…"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
    cat >&2 <<'EOF'
❌ This sandbox has no AWS credentials.

That means the IAM role isn't configured. In Kiro Web:

  Settings → Agent → Sandbox → IAM Role → paste the role ARN from your card,
  then start a NEW task (the role is picked up when the sandbox boots).

Full instructions: setup/00-kiro-web.md
EOF
    exit 1
}
echo "✅ Authenticated to AWS account ${ACCOUNT_ID}"

# ---------------------------------------------------------------------------
# 2. Read config from SSM
# ---------------------------------------------------------------------------
step "Reading your workshop config from SSM (${SSM_PREFIX}/*)…"
get() {
    aws ssm get-parameter --with-decryption --name "${SSM_PREFIX}/$1" \
        --query Parameter.Value --output text 2>/dev/null
}
FLYTE_DOMAIN=$(get flyte-domain)          || true
COGNITO_DOMAIN=$(get cognito-domain)      || true
COGNITO_CLIENT_ID=$(get cognito-client-id) || true
COGNITO_CLIENT_SECRET=$(get cognito-client-secret) || true
LLAMA_CLOUD_API_KEY=$(get llama-cloud-api-key) || true

missing=()
[ -n "${FLYTE_DOMAIN:-}" ]          || missing+=("flyte-domain")
[ -n "${COGNITO_DOMAIN:-}" ]        || missing+=("cognito-domain")
[ -n "${COGNITO_CLIENT_ID:-}" ]     || missing+=("cognito-client-id")
[ -n "${COGNITO_CLIENT_SECRET:-}" ] || missing+=("cognito-client-secret")
if [ ${#missing[@]} -gt 0 ]; then
    echo "❌ These SSM parameters are missing or unreadable:" >&2
    printf '     %s/%s\n' "$SSM_PREFIX" "${missing[@]}" >&2
    fail "The account may not be fully provisioned, or the role lacks SSM read. Tell a facilitator — this is a provisioning issue, not something you can fix from here."
fi
echo "✅ Config loaded for ${FLYTE_DOMAIN}"

# ---------------------------------------------------------------------------
# 3. Install the docker→podman shim
# ---------------------------------------------------------------------------
step "Installing the docker→podman shim…"
chmod +x "$TOKEN_SCRIPT" "$SHIM_SRC"
if command -v docker > /dev/null 2>&1 && ! docker buildx version 2>/dev/null | grep -q podman-shim; then
    echo "   A real docker is already on PATH — leaving it alone."
else
    SHIM_DEST=""
    for d in /usr/local/bin "$HOME/.local/bin"; do
        if mkdir -p "$d" 2>/dev/null && cp "$SHIM_SRC" "$d/docker" 2>/dev/null; then
            chmod +x "$d/docker" && SHIM_DEST="$d/docker" && break
        fi
    done
    [ -n "$SHIM_DEST" ] || fail "Couldn't install the shim to /usr/local/bin or ~/.local/bin. Neither was writable."
    echo "   Installed at ${SHIM_DEST}"
    case ":$PATH:" in
        *":$(dirname "$SHIM_DEST"):"*) ;;
        *) export PATH="$(dirname "$SHIM_DEST"):$PATH" ;;
    esac
fi
docker buildx version > /dev/null 2>&1 \
    || fail "The shim is installed but 'docker buildx version' failed. Is podman present? Try: podman --version"
echo "✅ docker buildx responds via podman"

# ---------------------------------------------------------------------------
# 4. Log in to ECR
# ---------------------------------------------------------------------------
# Flyte's builder never logs in to a registry — it assumes the daemon is already
# authenticated. Good for 12 hours; a late-day 401 on push means re-run this script.
step "Logging in to ECR…"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$ECR_REGISTRY" > /dev/null 2>&1 \
    || fail "ECR login failed for ${ECR_REGISTRY}. The role may lack ecr:GetAuthorizationToken."
echo "✅ Logged in to ${ECR_REGISTRY}"

# ---------------------------------------------------------------------------
# 5. Write config + the env file the token script reads
# ---------------------------------------------------------------------------
# Config key names verified against the Flyte SDK's reader (flyte/config/_internal.py).
# authType: ExternalCommand shells out for a bearer token instead of opening a browser
# (there's no browser here for PKCE). The token command path is absolute because the CLI
# runs it from whatever directory it happens to be in.
step "Writing ${CONFIG_FILE}…"
mkdir -p "$CONFIG_DIR"

# flyte-token.sh sources this to get the Cognito details each time the CLI calls it.
umask 077
cat > "$ENV_FILE" <<EOF
# Generated by scripts/bootstrap.sh — secret, gitignored, do not commit.
export FLYTE_DOMAIN='${FLYTE_DOMAIN}'
export COGNITO_DOMAIN='${COGNITO_DOMAIN}'
export COGNITO_CLIENT_ID='${COGNITO_CLIENT_ID}'
export COGNITO_CLIENT_SECRET='${COGNITO_CLIENT_SECRET}'
EOF

cat > "$CONFIG_FILE" <<EOF
# Generated by scripts/bootstrap.sh — do not edit by hand, do not commit.
admin:
  endpoint: dns:///${FLYTE_DOMAIN}:443
  authType: ExternalCommand
  command: ["sh", "-c", "${TOKEN_SCRIPT}"]
task:
  project: flytesnacks
  domain: development
image:
  builder: local
  registry: ${ECR_REGISTRY}
EOF
echo "✅ endpoint dns:///${FLYTE_DOMAIN}:443 · registry ${ECR_REGISTRY}"

# Export the LlamaCloud key for this shell (Module 10 tasks pass it through to the pod).
if [ -n "${LLAMA_CLOUD_API_KEY:-}" ]; then
    echo "export LLAMA_CLOUD_API_KEY='${LLAMA_CLOUD_API_KEY}'" >> "$ENV_FILE"
fi

# ---------------------------------------------------------------------------
# 6. Prove auth works, before Flyte hides the error behind a stack trace
# ---------------------------------------------------------------------------
step "Requesting a Cognito token…"
"$TOKEN_SCRIPT" > /dev/null \
    || fail "Could not get a token. The error above says why — most likely the Cognito domain isn't in your Kiro network allow-list (setup/00-kiro-web.md)."
echo "✅ Cognito issued a token"

# ---------------------------------------------------------------------------
# 7. Prove the devbox answers
# ---------------------------------------------------------------------------
step "Talking to your devbox (up to ~2 min if it was asleep — that's normal)…"
flyte get config \
    || fail "Got a token, but the devbox didn't answer. If this timed out, wait 2 minutes and re-run — the box auto-stops when idle and the first request wakes it."

cat <<EOF

🎉 You're connected and you can build images.

   Flyte UI:  https://${FLYTE_DOMAIN}/v2
   Registry:  ${ECR_REGISTRY}

   Open the UI in a second tab and leave it there — it's where you'll verify
   everything today. Next: setup/00-kiro-web.md, Checkpoint B.
EOF

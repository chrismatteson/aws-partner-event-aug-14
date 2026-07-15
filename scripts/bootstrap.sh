#!/usr/bin/env bash
# Wire this sandbox to your devbox, and make image builds work.
#
# Run once at the start of the workshop:  bash scripts/bootstrap.sh
#
# It does five things, in order, each of which will tell you plainly if it fails:
#   1. installs a `docker` shim that routes to podman (Flyte's builder wants `docker buildx`)
#   2. logs that podman into your account's ECR, so built images have somewhere to go
#   3. writes .flyte/config.yaml pointing at your devbox, with ECR as the image registry
#   4. mints a Cognito token, proving auth works
#   5. calls the devbox, proving it answers
#
# The config is per-attendee (everyone has a different domain), so it's gitignored and
# generated here rather than committed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${REPO_ROOT}/.flyte"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
TOKEN_SCRIPT="${REPO_ROOT}/scripts/flyte-token.sh"
SHIM_SRC="${REPO_ROOT}/scripts/docker-shim.sh"

fail() { echo ""; echo "❌ $*" >&2; exit 1; }
step() { echo ""; echo "→ $*"; }

# ---------------------------------------------------------------------------
# 0. Check the secrets Kiro should have injected
# ---------------------------------------------------------------------------
missing=()
for v in FLYTE_DOMAIN COGNITO_DOMAIN COGNITO_CLIENT_ID COGNITO_CLIENT_SECRET \
         AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION; do
    [ -n "${!v:-}" ] || missing+=("$v")
done

if [ ${#missing[@]} -gt 0 ]; then
    echo "❌ These environment variables are not set:" >&2
    printf '     %s\n' "${missing[@]}" >&2
    cat >&2 <<'EOF'

They come from Kiro Web secrets. Your facilitator gave you a card with the values.

  Kiro Web → Settings → Agent → Secrets → Add secret (one per variable)

Then start a NEW task — secrets are injected when the sandbox boots, so a task that
was already running won't see them.

Full instructions: setup/00-kiro-web.md
EOF
    exit 1
fi

chmod +x "$TOKEN_SCRIPT" "$SHIM_SRC"

# ---------------------------------------------------------------------------
# 1. Install the docker→podman shim
# ---------------------------------------------------------------------------
# Flyte's local image builder shells out to `docker buildx`. This sandbox has podman.
# The shim fakes just enough of buildx to keep the builder happy. See scripts/docker-shim.sh.
step "Installing the docker→podman shim…"

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
        *) export PATH="$(dirname "$SHIM_DEST"):$PATH"
           echo "   ⚠️  $(dirname "$SHIM_DEST") wasn't on PATH. Added for this shell — if a later"
           echo "       build says 'docker: not found', that's why. Re-run this script." ;;
    esac
fi

docker buildx version > /dev/null 2>&1 \
    || fail "The shim is installed but 'docker buildx version' failed. Is podman present? Try: podman --version"
echo "✅ docker buildx responds: $(docker buildx version)"

# ---------------------------------------------------------------------------
# 2. Log in to ECR
# ---------------------------------------------------------------------------
# Flyte's builder does NOT log in to any registry — it assumes the daemon is already
# authenticated. So we do it here. The login is good for 12 hours; if pushes start
# failing with a 401 late in the day, re-run this script.
step "Logging in to ECR…"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
    || fail "Couldn't call AWS STS. Check AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY on your card."
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$ECR_REGISTRY" > /dev/null 2>&1 \
    || fail "ECR login failed for ${ECR_REGISTRY}. Your key may lack ecr:GetAuthorizationToken."
echo "✅ Logged in to ${ECR_REGISTRY}"

# ---------------------------------------------------------------------------
# 3. Write the config
# ---------------------------------------------------------------------------
# Key names verified against the Flyte SDK's config reader (flyte/config/_internal.py).
#
# authType: ExternalCommand tells the CLI to shell out for a bearer token instead of
# opening a browser. PKCE (the default, and what a human on a laptop would use) cannot
# work here — there is no browser in this sandbox to complete the redirect.
#
# The command path is absolute on purpose: the Flyte CLI runs it from whatever the
# current working directory happens to be, and a relative path breaks the moment the
# agent cd's into a subdirectory.
#
# image.registry is what makes `flyte run` push built images to YOUR ECR. Without it the
# SDK falls back to ghcr.io/flyteorg, which you cannot push to.
step "Writing ${CONFIG_FILE}…"
mkdir -p "$CONFIG_DIR"
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

# ---------------------------------------------------------------------------
# 4. Prove auth works, before Flyte hides the error behind a stack trace
# ---------------------------------------------------------------------------
step "Requesting a Cognito token…"
"$TOKEN_SCRIPT" > /dev/null \
    || fail "Could not get a token. The error above says why. Most likely: a wrong secret value, or the Cognito domain isn't in your Kiro network allow-list (setup/00-kiro-web.md)."
echo "✅ Cognito issued a token"

# ---------------------------------------------------------------------------
# 5. Prove the devbox answers
# ---------------------------------------------------------------------------
step "Talking to your devbox (this can take ~2 min if it was asleep — that's normal)…"
flyte get config \
    || fail "Got a token, but the devbox didn't answer. If this timed out, wait 2 minutes and re-run — the box auto-stops when idle and the first request wakes it."

cat <<EOF

🎉 You're connected and you can build images.

   Flyte UI:  https://${FLYTE_DOMAIN}/v2
   Registry:  ${ECR_REGISTRY}

   Open the UI in a second tab and leave it there — it's where you'll verify
   everything today. Next: setup/00-kiro-web.md, Checkpoint B.
EOF

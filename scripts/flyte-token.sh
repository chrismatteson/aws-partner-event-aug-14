#!/usr/bin/env sh
# Mint a Cognito access token for this attendee's Flyte devbox.
#
# Referenced by .flyte/config.yaml as an ExternalCommand auth provider: the Flyte
# CLI runs it whenever it needs a bearer token and reads the token off stdout. That
# means it must print the token and NOTHING else — every diagnostic goes to stderr.
#
# Why this exists: the devbox authenticates via Cognito at the ALB. Humans use PKCE,
# which opens a browser. There is no browser in the Kiro sandbox, so we use the
# Cognito machine-to-machine client-credentials grant instead.
#
# Required env (set as Kiro Web secrets — see setup/00-kiro-web.md):
#   COGNITO_DOMAIN       e.g. https://flyte-devbox-123456789012.auth.us-east-1.amazoncognito.com
#   COGNITO_CLIENT_ID    the stack's CognitoM2MClientId output
#   COGNITO_CLIENT_SECRET
#   FLYTE_DOMAIN         e.g. student01.workshop.example.com  (scope is derived from it)

set -eu

for v in COGNITO_DOMAIN COGNITO_CLIENT_ID COGNITO_CLIENT_SECRET FLYTE_DOMAIN; do
    eval "val=\${$v:-}"
    if [ -z "$val" ]; then
        echo "flyte-token.sh: \$$v is not set. Check your Kiro Web secrets (setup/00-kiro-web.md)." >&2
        exit 1
    fi
done

# The resource server identifier is https://<domain> with an "access" scope; the ALB's
# jwt-validation rule checks for exactly this scope, so it must match the stack.
SCOPE="https://${FLYTE_DOMAIN}/access"

RESPONSE=$(
    curl --silent --show-error --fail-with-body \
         --max-time 20 \
         --request POST "${COGNITO_DOMAIN}/oauth2/token" \
         --user "${COGNITO_CLIENT_ID}:${COGNITO_CLIENT_SECRET}" \
         --data-urlencode "grant_type=client_credentials" \
         --data-urlencode "scope=${SCOPE}" 2>&1
) || {
    echo "flyte-token.sh: token request to Cognito failed." >&2
    echo "  endpoint: ${COGNITO_DOMAIN}/oauth2/token" >&2
    echo "  scope:    ${SCOPE}" >&2
    echo "  response: ${RESPONSE}" >&2
    echo "If this says 'could not resolve host', the Cognito domain is missing from" >&2
    echo "your Kiro network allow-list. See setup/00-kiro-web.md." >&2
    exit 1
}

TOKEN=$(printf '%s' "$RESPONSE" | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

if [ -z "$TOKEN" ]; then
    echo "flyte-token.sh: Cognito replied but there was no access_token in the response." >&2
    echo "  response: ${RESPONSE}" >&2
    echo "A common cause is a scope mismatch: FLYTE_DOMAIN must match the domain the" >&2
    echo "devbox stack was deployed with, exactly." >&2
    exit 1
fi

printf '%s' "$TOKEN"

#!/bin/bash
# A `docker` that is actually podman, with just enough `buildx` faked to satisfy Flyte.
#
# Installed to /usr/local/bin/docker by scripts/bootstrap.sh. You should never need to
# run this yourself.
#
# WHY THIS EXISTS
# ---------------
# Flyte's local image builder shells out to `docker buildx`. The Kiro Web sandbox has
# podman, not docker. Rather than teach Flyte about podman, we lie to it: this script
# answers the handful of `buildx` subcommands the SDK probes for, translates
# `buildx build` into `podman build` (+ an explicit `podman push`, since podman's build
# has no --push), and passes everything else straight through to podman.
#
# WHAT IT HANDLES
#   docker buildx version|ls|inspect|create|rm   -> canned answers; SDK concludes buildx is ready
#   docker buildx build --push --tag <t> ...     -> podman build ... && podman push <t>
#   docker <anything else>                       -> podman <anything else>
#
# KNOWN LIMITS (fine for the workshop, real if you reuse this)
#   * Forces linux/amd64. Podman can't cross-compile without qemu, and the devbox is amd64.
#   * Multiple --tag flags: every tag is passed to build, but ALL are pushed (see below).
#   * BuildKit-only flags (--provenance/--sbom) are dropped in both `=` and space forms.
#   * --load is dropped; podman build already leaves the image in local storage.

set -o pipefail

PODMAN=/usr/local/bin/podman
[ -x "$PODMAN" ] || PODMAN=$(command -v podman) || {
    echo "docker-shim: podman not found. This shim is useless without it." >&2
    exit 127
}

if [ "$1" != "buildx" ]; then
    exec "$PODMAN" "$@"
fi

shift
case "$1" in
    version)
        echo "github.com/docker/buildx v0.12.0 (podman-shim)"
        ;;
    ls)
        echo "NAME/NODE    DRIVER/ENDPOINT  STATUS   BUILDKIT  PLATFORMS"
        echo "flyte *      docker-container running  v0.12.0   linux/amd64"
        echo "flytex *     docker-container running  v0.12.0   linux/amd64"
        ;;
    inspect)
        echo "Name:   flyte"
        echo "Driver: docker-container"
        echo 'Options: network="host"'
        echo "Status: running"
        echo "Platforms: linux/amd64"
        ;;
    create|rm)
        : # Nothing to create or remove — the builder is a fiction. Succeed quietly.
        ;;
    build)
        shift
        ARGS=()
        TAGS=()
        DO_PUSH=false

        while [ $# -gt 0 ]; do
            case "$1" in
                --builder|--builder=*)
                    # Which builder is irrelevant; there's only podman.
                    [[ "$1" != *=* ]] && shift
                    shift
                    ;;
                --platform|--platform=*)
                    # Pin amd64 regardless of what was asked for.
                    [[ "$1" != *=* ]] && shift
                    shift
                    ARGS+=("--platform" "linux/amd64")
                    ;;
                --load)
                    # podman build already leaves the image in local storage.
                    shift
                    ;;
                --push)
                    # podman build has no --push; we do it explicitly after the build.
                    DO_PUSH=true
                    shift
                    ;;
                --provenance|--sbom|--attest)
                    # BuildKit-only. Space form: drop the flag AND its value.
                    shift 2
                    ;;
                --provenance=*|--sbom=*|--attest=*)
                    # BuildKit-only. Equals form: drop the flag.
                    shift
                    ;;
                --tag|-t)
                    TAGS+=("$2")
                    ARGS+=("--tag" "$2")
                    shift 2
                    ;;
                --tag=*)
                    TAGS+=("${1#*=}")
                    ARGS+=("$1")
                    shift
                    ;;
                *)
                    ARGS+=("$1")
                    shift
                    ;;
            esac
        done

        "$PODMAN" build "${ARGS[@]}" || exit $?

        if [ "$DO_PUSH" = true ]; then
            if [ ${#TAGS[@]} -eq 0 ]; then
                echo "docker-shim: --push with no --tag; nothing to push." >&2
                exit 1
            fi
            # Push every tag, not just the last. Flyte currently passes one, but silently
            # pushing 1-of-N would be a genuinely awful bug to debug.
            for t in "${TAGS[@]}"; do
                "$PODMAN" push "$t" || exit $?
            done
        fi
        ;;
    *)
        echo "docker-shim: unsupported buildx command '$1'." >&2
        echo "If Flyte started calling this, the shim needs a new case." >&2
        exit 1
        ;;
esac

# The fallback workshop image. NOT the default path.
#
# Attendees build their own images — Image.from_debian_base().with_pip_packages(...) —
# in the Kiro sandbox via podman + scripts/docker-shim.sh, pushed to their own ECR. That
# is what the modules teach and what the devbox is designed for.
#
# THIS image exists for one reason: if the build path breaks on the day (the shim, ECR
# auth, or create-on-push), facilitators hand out WORKSHOP_IMAGE and attendees pin it with
# flyte.Image.from_base(os.environ["WORKSHOP_IMAGE"]), chaining nothing onto it. That
# reaches zero Docker calls — a non-cloned Image returns its URI verbatim and the builder
# is never instantiated — so it works even if every build mechanism is broken.
#
# Keep it in sync with what the modules install. It should be a superset.
#
# Build and push before the event; see ORGANIZER.md.
#
#   docker build -f images/Dockerfile -t ghcr.io/unionai-oss/aws-workshop:2026-08-14 .
#   docker push ghcr.io/unionai-oss/aws-workshop:2026-08-14
#
# ⚠️ It must be PUBLIC. The Flyte SDK registers image-pull secrets but never emits
# imagePullSecrets into a pod spec, so a private image gives every attendee an
# ImagePullBackOff and there is no clean fix on the day.

FROM python:3.12-slim-bookworm

# LiteParse shells out to Tesseract for OCR, and to poppler for page rasterization.
# Without these it silently degrades to text-layer-only extraction on scanned pages —
# which looks like "the parser is bad" rather than "a dependency is missing".
RUN apt-get update && apt-get install -y --no-install-recommends \
        tesseract-ocr \
        poppler-utils \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Flyte itself is NOT optional. The task entrypoint is `a0`, a console script installed
# by the flyte package. No flyte in the image → no `a0` on PATH → the container fails to
# start with an error that explains nothing.
#
# Pin everything. A workshop that worked in rehearsal and breaks on the day because a
# transitive dep floated is the worst possible outcome, and it is entirely preventable.
RUN pip install --no-cache-dir \
        "flyte==2.5.9" \
        \
        # Module 10 — LlamaIndex.
        # llama-cloud>=2 is the CURRENT SDK. Do NOT add llama-parse or
        # llama-cloud-services: both hit end-of-maintenance 2026-05-01 and speak the v1
        # API only. Having them present would let a stale-trained agent write dead code
        # that imports successfully — much worse than a clean ImportError.
        "liteparse==2.6.0" \
        "llama-cloud==2.11.0" \
        \
        # Module 11 — Arize Phoenix.
        # auto_instrument only instruments libraries that are actually installed. A
        # missing openinference package produces no spans and NO ERROR — the single
        # most confusing failure in the module. Every framework we trace needs its
        # instrumentor here.
        #
        # NOTE: openinference-instrumentation-anthropic is the RIGHT instrumentor even
        # though we call Claude through Bedrock. It patches
        # anthropic.resources.messages.Messages, which Anthropic, AnthropicBedrock, and
        # AnthropicBedrockMantle all share — so it never sees the transport underneath.
        # openinference-instrumentation-bedrock is a DIFFERENT package that patches
        # boto3's bedrock-runtime; installing it here would tempt an agent into using it
        # and getting zero spans, silently. Deliberately absent.
        "arize-phoenix-otel==0.16.1" \
        "openinference-instrumentation-anthropic==1.0.6" \
        "openinference-instrumentation-openai==0.1.52" \
        "openinference-instrumentation-llama-index==4.4.3" \
        \
        # LLM access is via Bedrock using the EC2 instance role — no API keys anywhere.
        # The [bedrock] extra is what provides AnthropicBedrockMantle.
        "anthropic[bedrock]==0.116.0" \
        "boto3==1.43.48" \
        \
        # Reports and general data wrangling.
        "pandas==3.0.3" \
        "plotly==6.9.0" \
        "httpx==0.28.1"

# Flyte extracts the code bundle into the working directory at container start, so it
# must be writable by the running user. `from_base` — unlike `from_debian_base` — does
# not create a user or set a writable WORKDIR for you. This is that step.
WORKDIR /root

# Fail the build rather than the workshop. If `a0` isn't on PATH, every task on the day
# dies at startup; catching that here costs nothing.
RUN a0 --help > /dev/null 2>&1 || (echo "FATAL: flyte entrypoint 'a0' not on PATH" && exit 1)
RUN python -c "import liteparse, llama_cloud, phoenix.otel, anthropic, boto3; print('imports ok')"

# AnthropicBedrockMantle only exists with the [bedrock] extra installed. If this import
# fails, Module 11 has no LLM and there is no workaround on the day.
RUN python -c "from anthropic import AnthropicBedrockMantle; print('bedrock client ok')"

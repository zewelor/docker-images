FROM f0rc3/gokapi-cli:latest as cli_source

FROM debian:12-slim AS build
# hadolint ignore=DL3008,DL3009
RUN apt-get update && \
    apt-get install --no-install-suggests --no-install-recommends --yes python3-venv gcc libpython3-dev && \
    python3 -m venv /venv && \
    /venv/bin/pip install --upgrade pip setuptools wheel && \
    /venv/bin/pip install --no-cache-dir --disable-pip-version-check flask flask-cors

# Production image
FROM gcr.io/distroless/python3-debian12:nonroot

# Copy gokapi-cli from the official image
COPY --from=cli_source --chown=nonroot:nonroot /app/gokapi-cli /usr/local/bin/gokapi-cli

# Copy the python virtual environment
COPY --from=build --chown=nonroot:nonroot /venv /venv

WORKDIR /app

# Copy the default placeholder script
COPY --chown=nonroot:nonroot server.py /app/server.py

# set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/venv/bin:$PATH"

# Run the placeholder script by default
CMD [ "python3", "server.py" ]

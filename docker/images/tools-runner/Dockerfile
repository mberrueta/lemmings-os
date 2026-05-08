FROM python:3.12-slim

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends poppler-utils ca-certificates && \
    pip install --no-cache-dir markitdown trafilatura && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /tools

# Keep container alive as a controlled capability runtime sidecar.
CMD ["sleep", "infinity"]

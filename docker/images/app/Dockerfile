# Dockerfile for LemmingsOS
#
# Multi-stage build producing an Elixir release.
# The same image is used for both the world (control-plane) node
# and city nodes -- behavior is driven by environment variables.

# ---- Build stage ----
FROM hexpm/elixir:1.18.4-erlang-28.0.2-debian-bookworm-20260316-slim AS build

RUN apt-get update -y && \
    apt-get install -y build-essential git curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Node.js (required for esbuild/tailwind asset compilation)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/runtime.exs config/
RUN mix deps.compile

# Compile application
COPY lib lib
COPY priv priv
COPY assets assets

# Install asset tool binaries
RUN mix assets.setup

# Compile first — generates phoenix-colocated hooks in _build used by esbuild
RUN mix compile

# Build assets
RUN mix assets.deploy

# Build the release
RUN mix release

# ---- Runtime stage ----
FROM debian:bookworm-slim AS runtime

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

# Copy the release from the build stage
COPY --from=build /app/_build/prod/rel/lemmings_os ./

ENV HOME=/app

CMD ["/app/bin/lemmings_os", "start"]

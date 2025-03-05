ARG BUILDER_IMAGE="elixir:1.18-slim"
ARG RUNNER_IMAGE="debian:bookworm-slim"

FROM ${BUILDER_IMAGE} AS builder

# Set env variables
ENV MIX_ENV="prod"

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Hex and rebar3
RUN mix do local.hex --force, local.rebar --force

# Copy configuration
COPY config config

# Copy mix files
COPY mix.exs mix.exs
COPY mix.lock mix.lock

# Install dependencies
RUN mix do deps.get --only $MIX_ENV, deps.compile

# Copy application source code
COPY lib lib

# Compile the project
RUN mix compile

# Copy release configuration and build the release
COPY rel rel
RUN mix release

## Runner image

FROM ${RUNNER_IMAGE}

# Install runtime dependencies
RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV ELIXIR_ERL_OPTIONS="-sname protohackers"

WORKDIR /app

# Copy the compiled release from the builder stage
COPY --from=builder /app/_build/prod/rel /app

# Start the application
CMD /app/protohackers/bin/protohackers start

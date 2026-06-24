FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    RAILS_ENV=development \
    NODE_ENV=development \
    DISCOURSE_RUNNING_IN_RACK=1 \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      curl \
      ca-certificates \
      pkg-config \
      libyaml-dev \
      libxml2-dev \
      libxslt1-dev \
      libpq-dev \
      libsqlite3-dev \
      libffi-dev \
      libssl-dev \
      zlib1g-dev \
      imagemagick \
      shared-mime-info \
    && rm -rf /var/lib/apt/lists/*

# Node.js + pnpm for the Ember/JS frontend build and test tooling
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && rm -rf /var/lib/apt/lists/*

# Copy the full source tree before installing so pnpm can see workspace packages
# and local patch files referenced by package.json / pnpm-lock.yaml.
COPY . .

RUN bundle install \
    && pnpm install --frozen-lockfile

# Some orchestrators execute the configured command via `/bin/sh -lc` on the host,
# which means they do not inherit Dockerfile ENV like PATH and won't automatically
# run inside the image context. Provide a tiny host-visible wrapper named `bundle`
# in the repo root so the startup command `bundle exec rails server ...` resolves to
# `docker run discourse-local bundle exec rails server ...`.
RUN printf '%s\n' '#!/bin/sh' 'exec docker run --rm -p 3000:3000 discourse-local bundle "$@"' > /bundle-host-wrapper \
    && chmod +x /bundle-host-wrapper

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]

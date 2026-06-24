FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    RAILS_ENV=development \
    NODE_ENV=development \
    CI=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg \
    build-essential \
    pkg-config \
    python3 \
    libpq-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev \
    libssl-dev \
    libreadline-dev \
    libgmp-dev \
    libffi-dev \
    libjpeg-dev \
    libpng-dev \
    libvips-dev \
    libxml2-utils \
    xz-utils \
    file \
    procps \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && npm --version \
    && node --version \
    && pnpm --version \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy all dependency metadata and files pnpm needs before install.
# pnpm uses root config, patches, and workspace package manifests.
COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc .pnpmfile.cjs ./
COPY patches ./patches
COPY frontend ./frontend
COPY plugins ./plugins
COPY themes ./themes
COPY docs ./docs

RUN bundle config set without 'production' \
    && bundle install

RUN pnpm install --frozen-lockfile

COPY . .

RUN set -eux; \
    if [ -f config/discourse_defaults.conf ]; then \
      sed -i \
        -e 's/^redis_host *=.*/redis_host = redis/' \
        -e 's/^message_bus_redis_host *=.*/message_bus_redis_host = redis/' \
        config/discourse_defaults.conf; \
    fi; \
    if [ -f config/database.yml ]; then \
      sed -i \
        -e "s/\(host:\s*\).*/\1db/" \
        config/database.yml; \
    fi

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec bin/rails server -b 0.0.0.0 -p 3000"]

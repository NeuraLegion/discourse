FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_BIN=/bundle/bin \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    NODE_ENV=development \
    RAILS_ENV=development \
    PNPM_HOME=/root/.local/share/pnpm \
    PATH=/bundle/bin:/root/.local/share/pnpm:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /app

# System dependencies for Rails + native gems + JS tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    brotli \
    ca-certificates \
    curl \
    git \
    gnupg \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    pkg-config \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 and pnpm 10
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && pnpm config set auto-install-peers false \
    && rm -rf /var/lib/apt/lists/*

# Bundler
RUN gem update --system && gem install bundler

# Copy dependency manifests first for better caching
COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY patches ./patches
COPY frontend ./frontend
COPY plugins ./plugins
COPY themes ./themes
COPY docs ./docs

# Install Ruby gems
RUN bundle install

# Install JS dependencies for the monorepo
RUN pnpm install --frozen-lockfile

# Copy the rest of the application
COPY . .

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails server -b 0.0.0.0 -p 3000"]

FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    RAILS_ENV=development \
    NODE_ENV=development \
    BUNDLE_WITHOUT="" \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PATH="/bundle/bin:/usr/local/lib/node_modules/.bin:${PATH}"

WORKDIR /app

# Core build/runtime deps for Rails + native gems + JS toolchain
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg \
    build-essential \
    pkg-config \
    libpq-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    libffi-dev \
    libgmp-dev \
    libreadline-dev \
    libssl-dev \
    libvips \
    imagemagick \
    python3 \
    python-is-python3 \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20 + pnpm 10.28.0
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g pnpm@10.28.0 \
    && rm -rf /var/lib/apt/lists/*

# Ensure pnpm config matches the lockfile before install
RUN pnpm config set auto-install-peers false

# Copy dependency manifests and files pnpm needs for patched workspace installs
COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY .npmrc ./
COPY patches ./patches
COPY frontend ./frontend
COPY plugins ./plugins
COPY themes ./themes
COPY docs/developer-guides ./docs/developer-guides

# Install Ruby gems and JS dependencies
RUN bundle config set path "$BUNDLE_PATH" \
    && bundle install \
    && pnpm install --frozen-lockfile

# Copy the rest of the application source
COPY . .

EXPOSE 3000 4200

CMD ["bash", "-lc", "rm -rf tmp/cache && bundle exec bin/rails db:prepare && bin/dev"]

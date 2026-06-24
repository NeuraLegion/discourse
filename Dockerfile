FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    RAILS_ENV=development \
    RACK_ENV=development \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    NODE_ENV=development \
    PATH=/app/node_modules/.bin:/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    build-essential \
    pkg-config \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    libpq-dev \
    libgmp-dev \
    libvips \
    imagemagick \
    shared-mime-info \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Node.js + pnpm for the Ember/frontend build and tests
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && rm -rf /var/lib/apt/lists/*

# Ruby dependencies first for better caching
COPY Gemfile Gemfile.lock ./
RUN bundle config set path "$BUNDLE_PATH" \
    && bundle config set without 'production' \
    && bundle install

# JS dependency manifests first for better caching
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY frontend/*/package.json ./frontend/*/
COPY plugins/*/package.json ./plugins/*/
COPY themes/*/package.json ./themes/*/
RUN pnpm install --frozen-lockfile

# Copy the full source tree
COPY . .

EXPOSE 3000 4200

CMD ["bash", "-lc", "bundle exec rails db:prepare && pnpm dev"]

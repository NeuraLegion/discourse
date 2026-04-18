FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    RAILS_ENV=development \
    NODE_ENV=development \
    BUNDLE_WITHOUT="" \
    BUNDLE_PATH="/bundle" \
    PATH="/bundle/bin:/root/.local/share/pnpm:$PATH"

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    git \
    build-essential \
    pkg-config \
    libpq-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    libffi-dev \
    libreadline-dev \
    zlib1g-dev \
    libgdbm-dev \
    libncurses-dev \
    libssl-dev \
    libvips-dev \
    imagemagick \
    redis-tools \
  && rm -rf /var/lib/apt/lists/*

# Node.js 22 + pnpm 10 for the frontend/workspace build
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get update && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/* \
  && corepack enable \
  && corepack prepare pnpm@10.28.0 --activate

# Match the lockfile's pnpm settings so frozen installs succeed
RUN printf "auto-install-peers=false\n" > /app/.npmrc

# Install Ruby dependencies first for better caching
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Install JS dependencies first for better caching
COPY .npmrc package.json pnpm-workspace.yaml ./
COPY pnpm-lock.yaml ./
COPY patches ./patches
COPY frontend/discourse/package.json frontend/discourse/package.json
COPY frontend/discourse-i18n/package.json frontend/discourse-i18n/package.json
COPY frontend/discourse-types/package.json frontend/discourse-types/package.json
COPY frontend/discourse-plugins/package.json frontend/discourse-plugins/package.json
COPY frontend/discourse-markdown-it/package.json frontend/discourse-markdown-it/package.json
COPY frontend/pretty-text/package.json frontend/pretty-text/package.json
COPY frontend/custom-proxy/package.json frontend/custom-proxy/package.json
COPY frontend/deprecation-silencer/package.json frontend/deprecation-silencer/package.json
COPY frontend/asset-processor/package.json frontend/asset-processor/package.json
COPY frontend/ember-cli-progress-ci/package.json frontend/ember-cli-progress-ci/package.json
COPY themes/horizon/package.json themes/horizon/package.json
COPY plugins/*/package.json ./plugins/
RUN pnpm install --frozen-lockfile

# Bring in the full source tree
COPY . .

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec pitchfork -c config/pitchfork.conf.rb -p ${UNICORN_PORT:-3000}"]

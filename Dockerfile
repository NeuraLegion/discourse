FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    DISCOURSE_RUNNING_IN_DOCKER=1 \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      git \
      gnupg \
      libpq-dev \
      libxml2-dev \
      libxslt1-dev \
      libyaml-dev \
      pkg-config \
      python3 \
      shared-mime-info \
      unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22.x and pnpm
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency manifests and pnpm config required for frozen install
COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY patches ./patches

# Copy all workspace package manifests referenced by pnpm-workspace.yaml
COPY frontend/asset-processor/package.json frontend/asset-processor/package.json
COPY frontend/custom-proxy/package.json frontend/custom-proxy/package.json
COPY frontend/deprecation-silencer/package.json frontend/deprecation-silencer/package.json
COPY frontend/discourse/package.json frontend/discourse/package.json
COPY frontend/discourse-i18n/package.json frontend/discourse-i18n/package.json
COPY frontend/discourse-markdown-it/package.json frontend/discourse-markdown-it/package.json
COPY frontend/discourse-plugins/package.json frontend/discourse-plugins/package.json
COPY frontend/discourse-types/package.json frontend/discourse-types/package.json
COPY frontend/ember-cli-progress-ci/package.json frontend/ember-cli-progress-ci/package.json
COPY frontend/pretty-text/package.json frontend/pretty-text/package.json
COPY docs/developer-guides/package.json docs/developer-guides/package.json
COPY plugins/*/package.json ./plugins/
COPY themes/*/package.json ./themes/

RUN bundle config set path "$BUNDLE_PATH" \
    && bundle install \
    && pnpm install --frozen-lockfile

COPY . .

EXPOSE 3000

CMD ["bash", "-lc", "bin/rails server -b 0.0.0.0 -p ${UNICORN_PORT:-3000}"]

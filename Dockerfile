FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_WITHOUT="" \
    PATH=/bundle/bin:/app/bin:/app/node_modules/.bin:$PATH \
    RAILS_ENV=production \
    NODE_ENV=development \
    DISCOURSE_HOSTNAME=localhost

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      gnupg \
      build-essential \
      pkg-config \
      autoconf \
      bison \
      libyaml-dev \
      libxml2-dev \
      libxslt1-dev \
      libffi-dev \
      libgmp-dev \
      libreadline-dev \
      libssl-dev \
      zlib1g-dev \
      libpq-dev \
      libsqlite3-dev \
      liblz4-dev \
      libjemalloc2 \
      shared-mime-info \
      imagemagick \
      ffmpeg \
      chromium \
      libgtk-3-0 \
      libnss3 \
      libasound2 \
      libatk-bridge2.0-0 \
      libatk1.0-0 \
      libcups2 \
      libdrm2 \
      libgbm1 \
      libxcomposite1 \
      libxdamage1 \
      libxfixes3 \
      libxkbcommon0 \
      libxrandr2 \
      xdg-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock* ./
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml* .npmrc* ./
COPY patches ./patches
COPY docs/developer-guides/package.json docs/developer-guides/package.json
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
COPY plugins/*/package.json plugins/*/package.json
COPY themes/*/package.json themes/*/package.json

RUN gem update --system \
    && gem install bundler \
    && bundle install \
    && pnpm install --frozen-lockfile

COPY . .

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rake db:prepare && bundle exec rails server -b 0.0.0.0 -p 3000"]

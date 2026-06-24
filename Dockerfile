FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_WITHOUT=production \
    PNPM_HOME=/pnpm \
    PATH=/pnpm:/bundle/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    RAILS_ENV=development \
    NODE_ENV=development \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    npm_config_update_notifier=false \
    PNPM_PACKAGE_IMPORT_METHOD=copy

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    libpq-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    pkg-config \
    python3 \
    xz-utils \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get update && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

RUN corepack enable \
  && corepack prepare pnpm@10.28.0 --activate

COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY .npmrc* ./
COPY patches ./patches

RUN bundle config set path "$BUNDLE_PATH" \
  && bundle config set without "$BUNDLE_WITHOUT" \
  && bundle install \
  && pnpm config set package-import-method copy \
  && pnpm install --frozen-lockfile --ignore-scripts --child-concurrency=1

COPY . .

RUN mkdir -p tmp/pids tmp/cache log \
  && if [ -f config/database.yml ]; then \
       sed -i "s/hostname: localhost/hostname: db/g; s/host: localhost/host: db/g" config/database.yml || true; \
     fi

EXPOSE 3000 3035

CMD ["bash", "-lc", "bundle exec rails db:prepare && pnpm dev"]

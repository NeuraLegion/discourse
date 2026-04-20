FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=production \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    RAILS_ENV=development \
    NODE_ENV=development \
    CI=true \
    PNPM_HOME=/usr/local/share/pnpm \
    PATH=/usr/local/share/pnpm:/usr/local/bundle/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /app

COPY Gemfile Gemfile.lock ./

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      build-essential \
      curl \
      git \
      gnupg \
      pkg-config \
      libpq-dev \
      libyaml-dev \
      libxml2-dev \
      libxslt1-dev \
      zlib1g-dev \
      libffi-dev \
      libreadline-dev \
      libgmp-dev \
      shared-mime-info \
      imagemagick \
      graphicsmagick \
      ffmpeg \
      chromium \
      libnss3 \
      libatk-bridge2.0-0 \
      libgtk-3-0 \
      libasound2 \
      libgbm1 \
      libxshmfence1 \
      libxdamage1 \
      libxcomposite1 \
      libxrandr2 \
      xdg-utils \
    && rm -rf /var/lib/apt/lists/*

RUN gem update --system \
    && gem install bundler -v "$(grep -A 1 '^BUNDLED WITH$' Gemfile.lock | tail -n1 | tr -d '[:space:]')"

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && pnpm --version

COPY . .

RUN bundle config set without 'production' \
    && bundle install \
    && pnpm install --frozen-lockfile=false --config.auto-install-peers=false

RUN mkdir -p tmp/pids tmp/cache tmp/sockets public/assets public/packs frontend/discourse/dist \
    && if [ -f config/discourse_defaults.conf ]; then \
         sed -i \
           -e 's/^db_host =.*/db_host = db/' \
           -e 's/^db_backup_host =.*/db_backup_host = db/' \
           -e 's/^redis_host =.*/redis_host = redis/' \
           -e 's/^message_bus_redis_host =.*/message_bus_redis_host = redis/' \
           config/discourse_defaults.conf; \
       fi

EXPOSE 3000

CMD ["bash", "-lc", "SKIP_ENFORCE_HOSTNAME=1 DISCOURSE_HOSTNAME=${DISCOURSE_HOSTNAME:-localhost} bundle exec rails server -b 0.0.0.0 -p ${PORT:-3000}"]

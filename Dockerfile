FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    RAILS_ENV=development \
    RACK_ENV=development \
    BUNDLE_PATH=/bundle \
    BUNDLE_WITHOUT=production \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    DISCOURSE_RUNNING_IN_RACK=1 \
    SKIP_ENFORCE_HOSTNAME=1 \
    DISCOURSE_HOSTNAME=localhost \
    DISCOURSE_DEV_DB=discourse_development \
    CHECKOUT_TIMEOUT=5 \
    CI=1 \
    PNPM_HOME=/pnpm \
    PATH=/pnpm:$PATH

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    pkg-config \
    xz-utils \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    libffi-dev \
    libgmp-dev \
    libpq-dev \
    imagemagick \
    brotli \
    libvips \
    redis-server \
    python3 \
  && ln -sf /usr/bin/convert /usr/bin/magick \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get update && apt-get install -y --no-install-recommends nodejs \
  && corepack enable \
  && corepack prepare pnpm@10.28.0 --activate \
  && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY patches ./patches

RUN bundle config set path "${BUNDLE_PATH}" \
  && bundle config set without "${BUNDLE_WITHOUT}" \
  && bundle install

RUN pnpm install --frozen-lockfile --ignore-scripts --config.auto-install-peers=false

COPY . .

RUN ruby -e 'path = "config/database.yml"; text = File.read(path); text.sub!("development:\n", "development:\n  host: db\n"); File.write(path, text)'

EXPOSE 3000

CMD ["bash", "-lc", "redis-server --daemonize yes && bundle exec rails server -b 0.0.0.0 -p 3000"]

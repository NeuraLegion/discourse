FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PATH=/app/node_modules/.bin:/root/.local/share/pnpm:$PATH

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      pkg-config \
      curl \
      ca-certificates \
      libpq-dev \
      libyaml-dev \
      libxml2-dev \
      libxslt-dev \
      zlib1g-dev \
      libffi-dev \
      libgmp-dev \
      liblz4-dev \
      libssl-dev \
      libreadline-dev \
      libsqlite3-dev \
      shared-mime-info \
      brotli \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20 + pnpm 10.x for the Rails frontend/tooling
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && rm -rf /var/lib/apt/lists/*

RUN pnpm config set auto-install-peers false \
    && pnpm config set strict-peer-dependencies true

COPY . .

RUN gem install bundler && bundle install
RUN pnpm install --frozen-lockfile

RUN SKIP_DB_AND_REDIS=1 \
    RAILS_ENV=production \
    SECRET_KEY_BASE=00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000 \
    bundle exec rake assets:precompile

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails db:prepare && SKIP_ENFORCE_HOSTNAME=1 bundle exec rails server -b 0.0.0.0 -p 3000"]

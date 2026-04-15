FROM ruby:3.4.5-slim-bookworm

ENV RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PNPM_HOME=/usr/local/share/pnpm \
    PATH=/usr/local/share/pnpm:$PATH \
    COREPACK_INTEGRITY_KEYS=0 \
    DISCOURSE_SERVE_STATIC_ASSETS=true \
    CI=1 \
    NODE_OPTIONS=--max-old-space-size=4096

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    libpq-dev \
    pkg-config \
    python3 \
    shared-mime-info \
    libvips \
    ca-certificates \
 && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && npm install -g corepack@latest \
 && corepack enable \
 && rm -rf /var/lib/apt/lists/*

COPY . .

RUN bundle config set deployment true \
 && bundle config set without 'development test' \
 && bundle install

RUN pnpm install --frozen-lockfile --ignore-scripts \
 && (pnpm exec patch-package || true)

RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rake assets:precompile

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-e", "production", "-b", "0.0.0.0", "-p", "3000"]

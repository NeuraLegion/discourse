FROM ruby:3.4.7-slim-bookworm

WORKDIR /app

ENV RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_FROZEN=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    pkg-config \
    libyaml-dev \
    zlib1g-dev \
    libffi-dev \
    libgmp-dev \
    libssl-dev \
    libreadline-dev \
    libpq-dev \
    postgresql-client \
    redis-tools \
    libjemalloc2 \
    shared-mime-info \
    python3 \
    nodejs \
    npm \
    && npm install -g pnpm@10 \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml ./

RUN bundle install

COPY . .

RUN pnpm install --frozen-lockfile --ignore-scripts \
    && pnpm exec patch-package || true

RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rake assets:precompile

EXPOSE 3000

CMD ["sh", "-lc", "bundle exec rails db:create db:migrate && bundle exec rails server -b 0.0.0.0 -p 3000"]

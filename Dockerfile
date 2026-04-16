FROM ruby:3.4.7-slim-bookworm

ENV RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PNPM_HOME=/pnpm \
    PATH="/pnpm:$PATH"

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    libyaml-dev \
    libpq-dev \
    pkg-config \
    python3 \
    postgresql-client \
    shared-mime-info \
    tzdata \
    nodejs \
    npm \
    && npm install -g corepack \
    && corepack enable \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml ./

RUN bundle install --without development test

COPY . .

RUN corepack prepare pnpm@10.28.0 --activate \
    && pnpm install --frozen-lockfile --ignore-scripts \
    && (pnpm exec tsc -b || true) \
    && bundle exec rake assets:precompile

EXPOSE 3000

CMD ["sh", "-lc", "bin/rails db:create db:migrate && exec bundle exec rails server -b 0.0.0.0 -p 3000"]

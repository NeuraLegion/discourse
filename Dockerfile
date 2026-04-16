FROM ruby:3.4.7-slim-bookworm

ENV RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_DEPLOYMENT=1 \
    PNPM_HOME=/usr/local/share/pnpm \
    PATH="/usr/local/share/pnpm:${PATH}"

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    libpq-dev \
    postgresql-client \
    pkg-config \
    python3 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && npm install -g pnpm@10.28.0 \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml ./

RUN bundle _2.6.4_ install --without development test

COPY . .

RUN pnpm install --frozen-lockfile --ignore-scripts

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails db:create db:migrate && bundle exec rails server -b 0.0.0.0 -p 3000"]

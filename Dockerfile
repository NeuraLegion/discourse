FROM ruby:3.4.5-slim-bookworm

WORKDIR /app

ENV RAILS_ENV=production \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PNPM_HOME=/root/.local/share/pnpm \
    PATH=/root/.local/share/pnpm:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    libpq-dev \
    pkg-config \
    python3 \
    ca-certificates \
    libvips \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml ./

RUN bundle install --without development test
RUN pnpm install --frozen-lockfile --ignore-scripts

COPY . .

RUN bundle exec rake assets:precompile || true

EXPOSE 3000

CMD ["sh", "-c", "bundle exec rails db:create db:migrate && bundle exec pitchfork -c config/pitchfork.conf.rb"]

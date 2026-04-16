FROM ruby:3.4.7-slim-bookworm

ENV RAILS_ENV=production \
    RACK_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH=/usr/local/bundle \
    PNPM_HOME=/pnpm \
    PATH="/pnpm:/usr/local/bundle/bin:$PATH" \
    RAILS_LOG_TO_STDOUT=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    libpq-dev \
    postgresql-client \
    redis-tools \
    pkg-config \
    python3 \
    shared-mime-info \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml ./

RUN corepack enable && \
    corepack prepare pnpm@10.28.0 --activate && \
    pnpm install --frozen-lockfile --ignore-scripts

RUN gem install bundler:2.6.4 && \
    rm -f Gemfile.lock && \
    bundle install

COPY . .

RUN bundle exec rake assets:precompile

EXPOSE 3000

CMD ["sh", "-lc", "bin/rails db:create db:migrate && bundle exec pitchfork -c config/pitchfork.conf.rb"]

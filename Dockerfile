FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    BUNDLE_WITHOUT="development:test" \
    RAILS_ENV=production \
    RACK_ENV=production \
    NODE_ENV=production \
    DISCOURSE_HOSTNAME=localhost \
    DISCOURSE_DB_HOST=db \
    DISCOURSE_DB_NAME=discourse \
    DISCOURSE_DB_USERNAME=discourse \
    DISCOURSE_DB_PASSWORD=discourse \
    DISCOURSE_REDIS_HOST=redis \
    DISCOURSE_MESSAGE_BUS_REDIS_HOST=redis \
    SECRET_KEY_BASE=dummy_secret_key_base_for_dast_testing \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    pkg-config \
    libpq-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    libssl-dev \
    zlib1g-dev \
    libffi-dev \
    libgmp-dev \
    libreadline-dev \
    libsqlite3-dev \
    imagemagick \
    fonts-noto \
    fonts-liberation \
    libvips42 \
    libjemalloc2 \
    wkhtmltopdf \
    redis-tools \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && rm -rf /var/lib/apt/lists/*

RUN gem update --system --no-document \
    && gem install bundler --no-document

COPY Gemfile Gemfile.lock ./
RUN bundle config set without 'development test' \
    && bundle config set path "${BUNDLE_PATH}" \
    && bundle install

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY frontend ./frontend
COPY plugins ./plugins
COPY themes ./themes
COPY script ./script

RUN pnpm install --frozen-lockfile

COPY . .

RUN sed -i 's/^db_host = .*/db_host = db/' config/discourse_defaults.conf \
    && sed -i 's/^redis_host = .*/redis_host = redis/' config/discourse_defaults.conf \
    && sed -i 's/^message_bus_redis_host = .*/message_bus_redis_host = redis/' config/discourse_defaults.conf \
    && sed -i 's/^hostname = "www.example.com"/hostname = "${DISCOURSE_HOSTNAME:-localhost}"/' config/discourse_defaults.conf

RUN bundle exec rake assets:precompile

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec puma -C config/puma.rb"]

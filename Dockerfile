FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_WITHOUT="production" \
    BUNDLE_PATH="/bundle" \
    BUNDLE_BIN="/bundle/bin" \
    GEM_HOME="/bundle" \
    PATH="/app/bin:/app/node_modules/.bin:/bundle/bin:${PATH}" \
    RAILS_ENV=development \
    NODE_ENV=development

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
    zlib1g-dev \
    libffi-dev \
    libssl-dev \
    libreadline-dev \
    libgdbm-dev \
    libncurses5-dev \
    libjemalloc2 \
    shared-mime-info \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@10.28.0 --activate

RUN gem install bundler:2.6.4

COPY . .

RUN bundle install && pnpm install --frozen-lockfile

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails server -b 0.0.0.0 -p 3000"]

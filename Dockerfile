FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_WITHOUT="production" \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    GEM_HOME="/usr/local/bundle" \
    NODE_ENV=development \
    RAILS_ENV=development \
    DISCOURSE_HOSTNAME=localhost \
    SKIP_ENFORCE_HOSTNAME=1 \
    CHROME_BIN=/usr/bin/chromium

ENV PATH="/usr/local/bundle/bin:/app/node_modules/.bin:/usr/local/bin:${PATH}"

WORKDIR /app

COPY --from=node:20-bookworm /usr/local/ /usr/local/
COPY --from=node:20-bookworm /opt/ /opt/

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    pkg-config \
    python3 \
    make \
    g++ \
    libpq-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev \
    libreadline-dev \
    libffi-dev \
    libgmp-dev \
    libicu-dev \
    liblz4-dev \
    libvips-dev \
    imagemagick \
    shared-mime-info \
    libjemalloc2 \
    chromium \
    && rm -rf /var/lib/apt/lists/*

RUN node -v \
    && npm -v \
    && npx -v \
    && npm install -g pnpm@10.28.0 \
    && pnpm --version

COPY Gemfile Gemfile.lock ./
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY .npmrc ./
COPY patches ./patches
COPY frontend ./frontend
COPY plugins ./plugins
COPY themes ./themes
COPY docs/developer-guides ./docs/developer-guides

RUN bundle config set path "$GEM_HOME" \
    && bundle config set without "$BUNDLE_WITHOUT" \
    && bundle install \
    && pnpm install --frozen-lockfile

COPY . .

RUN sed -i "s/localhost/0.0.0.0/g" config/database.yml \
    && chmod +x script/rails script/discourse script/ember-cli 2>/dev/null || true

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec puma -C config/puma.rb"]

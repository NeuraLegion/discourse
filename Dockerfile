FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_WITHOUT="production" \
    PNPM_HOME=/pnpm \
    PATH=/pnpm:/usr/local/bin:$PATH \
    RAILS_ENV=development \
    NODE_ENV=development \
    DISCOURSE_DEV_DB=discourse_development \
    DISCOURSE_HOSTNAME=localhost

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      curl \
      ca-certificates \
      pkg-config \
      libyaml-dev \
      libxml2-dev \
      libxslt1-dev \
      libpq-dev \
      libssl-dev \
      zlib1g-dev \
      libreadline-dev \
      libffi-dev \
      libgmp-dev \
      libvips \
      imagemagick \
      shared-mime-info \
      bash \
      xz-utils \
    && ln -sf /usr/bin/convert /usr/local/bin/magick \
    && git config --global --add safe.directory /app \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && npm install -g pnpm@10.28.0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set path "$BUNDLE_PATH" \
    && bundle config set without "$BUNDLE_WITHOUT" \
    && bundle install

COPY .npmrc ./
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY patches ./patches
COPY frontend ./frontend
COPY plugins ./plugins
COPY themes ./themes
COPY docs/developer-guides ./docs/developer-guides
COPY config ./config
COPY app ./app
COPY lib ./lib
COPY script ./script
COPY bin ./bin
COPY Rakefile ./
RUN pnpm install --frozen-lockfile

COPY . .

RUN sed -i "s/host: localhost/host: db/" config/database.yml || true

EXPOSE 3000 4200

CMD ["bash", "-lc", "bundle exec bin/dev"]

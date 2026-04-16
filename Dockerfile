# syntax=docker/dockerfile:1.7

FROM ruby:3.4.2-bookworm AS build
WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    git \
    curl \
    ca-certificates \
    python3 \
    nodejs \
    npm \
    libpq-dev \
    libvips-dev \
    libc6-dev \
    shared-mime-info \
  && rm -rf /var/lib/apt/lists/*

ENV COREPACK_INTEGRITY_KEYS=0
RUN npm install -g corepack@latest \
  && corepack enable \
  && corepack prepare pnpm@10.28.0 --activate

ENV BUNDLE_WITHOUT="development:test" \
    BUNDLE_DEPLOYMENT="true" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_JOBS="4" \
    BUNDLE_RETRY="3" \
    RAILS_ENV="production" \
    NODE_ENV="production"

COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY versions.json tsconfig.json tsconfig-base.json eslint.config.mjs stylelint.config.mjs lefthook.yml translator.yml ./
COPY .npmrc* ./

RUN gem install bundler -v 2.6.4 -N \
  && bundle install

RUN pnpm install --frozen-lockfile --ignore-scripts

COPY . .

RUN mkdir -p log tmp/pids tmp/cache tmp/sockets public/assets

RUN pnpm run build || true

FROM ruby:3.4.2-bookworm AS runtime
WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    nodejs \
    npm \
    git \
    curl \
    ca-certificates \
    tzdata \
    libpq5 \
    libvips \
    shared-mime-info \
  && rm -rf /var/lib/apt/lists/*

ENV COREPACK_INTEGRITY_KEYS=0
RUN npm install -g corepack@latest \
  && corepack enable \
  && corepack prepare pnpm@10.28.0 --activate

ENV RAILS_ENV="production" \
    NODE_ENV="production" \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_DEPLOYMENT="true" \
    BUNDLE_PATH="/usr/local/bundle" \
    LANG="C.UTF-8" \
    RAILS_LOG_TO_STDOUT="1"

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

RUN mkdir -p log tmp/pids tmp/cache tmp/sockets public/assets \
  && sed -i 's/  -it \\/  -i \\/' bin/docker/exec

EXPOSE 3000

CMD ["bundle", "exec", "pitchfork", "-E", "production", "-c", "config/pitchfork.conf.rb", "config.ru"]

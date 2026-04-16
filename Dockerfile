FROM ruby:3.4.7-slim AS base

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    RAILS_ENV=production \
    RACK_ENV=production \
    NODE_ENV=production \
    DISCOURSE_RUNNING_IN_RACK=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      libpq-dev \
      pkg-config \
      curl \
      ca-certificates \
      gnupg \
    && rm -rf /var/lib/apt/lists/*

FROM base AS bundler

COPY Gemfile Gemfile.lock ./

RUN gem update --system && gem install bundler -v 2.6.4
RUN rm -f Gemfile.lock && bundle install --without development test

FROM base AS assets

RUN apt-get update && apt-get install -y --no-install-recommends \
      nodejs \
      npm \
    && npm install -g pnpm@10.28.0 \
    && rm -rf /var/lib/apt/lists/*

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY tsconfig.json tsconfig-base.json ./
COPY eslint.config.mjs stylelint.config.mjs lefthook.yml versions.json translator.yml ./
COPY patches ./patches
COPY Gemfile Gemfile.lock ./

RUN pnpm install --frozen-lockfile --ignore-scripts

COPY . .

RUN bundle install --without development test
RUN pnpm run build || true

FROM ruby:3.4.7-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_WITHOUT=development:test \
    RAILS_ENV=production \
    RACK_ENV=production \
    NODE_ENV=production \
    DISCOURSE_RUNNING_IN_RACK=1 \
    PATH=/bundle/bin:$PATH

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      libpq5 \
      curl \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=bundler /bundle /bundle
COPY --from=assets /app /app

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]

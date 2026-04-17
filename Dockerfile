FROM ruby:3.4.7-bookworm AS base

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    libpq-dev \
    pkg-config \
    shared-mime-info \
    ca-certificates \
    curl \
  && rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    RACK_ENV=production \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH=/bundle \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    NODE_ENV=production \
    PNPM_HOME=/pnpm \
    PATH=/pnpm:/usr/local/bundle/bin:/bundle/bin:$PATH \
    COREPACK_INTEGRITY_KEYS=0 \
    NPM_CONFIG_STRICT_PEER_DEPS=false

FROM base AS deps

COPY --from=node:20-bookworm /usr/local/ /usr/local/

RUN npm install -g corepack@latest && corepack enable

COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v 2.6.4
RUN bundle config set --local without '' \
 && bundle config set --local deployment false \
 && bundle install

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY patches ./patches
COPY frontend ./frontend
COPY plugins ./plugins
COPY themes ./themes
RUN pnpm install --no-frozen-lockfile --strict-peer-dependencies=false

COPY . .

FROM deps AS build

ENV SKIP_DB_AND_REDIS=1 \
    DISCOURSE_SERVE_STATIC_ASSETS=true \
    DISCOURSE_HOSTNAME=localhost \
    DISCOURSE_DB_HOST=localhost \
    DISCOURSE_DB_NAME=discourse_production \
    DISCOURSE_DB_USERNAME=postgres \
    DISCOURSE_DB_PASSWORD=postgres \
    DISCOURSE_REDIS_HOST=localhost \
    DISCOURSE_REDIS_PORT=6379 \
    SECRET_KEY_BASE_DUMMY=1 \
    DISCOURSE_SECRET_KEY_BASE=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

RUN bundle exec rake assets:precompile

FROM ruby:3.4.7-bookworm AS runtime

WORKDIR /app

COPY --from=node:20-bookworm /usr/local/bin/node /usr/local/bin/node
COPY --from=node:20-bookworm /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -sf /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack \
 && ln -sf /usr/local/lib/node_modules/corepack/dist/pnpm.js /usr/local/bin/pnpm

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    libpq5 \
    shared-mime-info \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    RACK_ENV=production \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH=/bundle \
    BUNDLE_DEPLOYMENT=1 \
    PATH=/bundle/bin:/usr/local/bundle/bin:$PATH

COPY --from=deps /bundle /bundle
COPY --from=build /app /app

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]

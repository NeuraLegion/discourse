FROM ruby:3.4.7-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH="/bundle" \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    RAILS_ENV=production \
    RACK_ENV=production \
    NODE_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    COREPACK_INTEGRITY_KEYS=0

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      libyaml-dev \
      libxml2-dev \
      libxslt-dev \
      git \
      curl \
      ca-certificates \
      libpq-dev \
      pkg-config \
    && rm -rf /var/lib/apt/lists/*

COPY --from=node:20-bookworm-slim /usr/local/bin /usr/local/bin
COPY --from=node:20-bookworm-slim /usr/local/lib /usr/local/lib
COPY --from=node:20-bookworm-slim /usr/local/include /usr/local/include
COPY --from=node:20-bookworm-slim /usr/local/share /usr/local/share

RUN npm install -g corepack@latest

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

RUN corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && pnpm config set auto-install-peers true \
    && pnpm install --no-frozen-lockfile \
    && bundle exec rake assets:precompile || true

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]

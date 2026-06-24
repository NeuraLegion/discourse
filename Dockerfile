FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_PATH=/bundle \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    COREPACK_INTEGRITY_KEYS=0

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
      libsqlite3-dev \
      pkg-config \
      shared-mime-info \
      nodejs \
      npm \
    && npm install -g corepack@latest \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

RUN pnpm install --frozen-lockfile

RUN pnpm --dir=frontend/discourse build || true

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]

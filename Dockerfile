FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_WITHOUT="production" \
    SKIP_ENFORCE_HOSTNAME=1 \
    RAILS_ENV=development \
    NODE_ENV=development

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      git \
      gnupg \
      libpq-dev \
      libyaml-dev \
      libxml2-dev \
      libxslt1-dev \
      pkg-config \
      python3 \
      shared-mime-info \
      xz-utils \
    && rm -rf /var/lib/apt/lists/*

COPY --from=node:22.22.2-bookworm-slim /usr/local/ /usr/local/
COPY --from=node:22.22.2-bookworm-slim /opt/ /opt/

WORKDIR /app

COPY Gemfile Gemfile.lock ./
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml .npmrc .pnpmfile.cjs ./
COPY patches ./patches
COPY frontend ./frontend
COPY plugins ./plugins
COPY themes ./themes
COPY docs ./docs

RUN bundle config set path "$BUNDLE_PATH" && \
    bundle config set without "$BUNDLE_WITHOUT" && \
    bundle install && \
    corepack pnpm install --frozen-lockfile

COPY . .

RUN mkdir -p tmp/pids tmp/cache tmp/sockets && \
    bundle exec rake assets:precompile || true

EXPOSE 3000

CMD ["bash", "-lc", "corepack enable >/dev/null 2>&1 || true; bundle exec rails server -b 0.0.0.0 -p 3000"]

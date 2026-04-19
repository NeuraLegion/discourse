FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_WITHOUT="production" \
    RAILS_ENV=development \
    NODE_ENV=development \
    PATH="/usr/local/bundle/bin:/usr/local/node/bin:${PATH}"

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    pkg-config \
    postgresql-client \
    sqlite3 \
    libsqlite3-dev \
    redis-tools \
    && rm -rf /var/lib/apt/lists/*

# Node.js for Rails asset build and frontend tooling
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@10.28.0 --activate

COPY Gemfile Gemfile.lock pnpm-workspace.yaml pnpm-lock.yaml package.json tsconfig.json tsconfig-base.json eslint.config.mjs stylelint.config.mjs lefthook.yml ./
COPY frontend ./frontend
COPY plugins ./plugins
RUN rm -rf /app/plugins/discourse-ai.disabled
COPY themes ./themes
COPY config.ru Rakefile README.md ./
COPY . .
RUN rm -rf /app/plugins/discourse-ai.disabled

RUN bundle install && pnpm install --frozen-lockfile

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails server -b 0.0.0.0 -p 3000"]

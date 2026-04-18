FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_WITHOUT="production" \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_PATH=/bundle \
    GEM_HOME=/bundle \
    PATH=/bundle/bin:/app/node_modules/.bin:$PATH \
    RAILS_ENV=development \
    NODE_ENV=development

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    pkg-config \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    libpq-dev \
    libffi-dev \
    libgmp-dev \
    libjemalloc2 \
    imagemagick \
    sqlite3 \
    libsqlite3-dev \
    postgresql-client \
    redis-tools \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get update && apt-get install -y --no-install-recommends \
    nodejs \
  && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@10.28.0 --activate

COPY . .

RUN gem install bundler -v 2.6.4 --no-document \
  && bundle _2.6.4_ config set path "$BUNDLE_PATH" \
  && bundle _2.6.4_ install

RUN pnpm install --frozen-lockfile

EXPOSE 3000

CMD ["bash", "-lc", "bundle _2.6.4_ exec rails server -b 0.0.0.0 -p 3000"]

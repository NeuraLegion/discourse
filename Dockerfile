FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_BIN=/bundle/bin \
    PATH=/bundle/bin:/usr/local/bundle/bin:/app/node_modules/.bin:$PATH \
    RAILS_ENV=development \
    NODE_ENV=development \
    PNPM_HOME=/usr/local/share/pnpm \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      git \
      gnupg \
      pkg-config \
      python3 \
      libpq-dev \
      libyaml-dev \
      libxml2-dev \
      libxslt1-dev \
      libssl-dev \
      libreadline-dev \
      zlib1g-dev \
      libffi-dev \
      libgmp-dev \
      libvips-dev \
      libjemalloc2 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && rm -rf /var/lib/apt/lists/*

COPY . .

RUN gem update --system \
    && gem install bundler -N \
    && bundle config set path "$BUNDLE_PATH" \
    && bundle config set without "production" \
    && bundle install

RUN node -e "const fs=require('fs'); const p='package.json'; const pkg=JSON.parse(fs.readFileSync(p,'utf8')); pkg.pnpm = pkg.pnpm || {}; pkg.pnpm.allowUnusedPatches = true; fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');" \
    && pnpm install --no-frozen-lockfile

EXPOSE 3000 4200

CMD ["bash", "-lc", "bundle exec rails db:prepare && pnpm dev"]

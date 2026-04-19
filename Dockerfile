FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PATH=/app/bin:/bundle/bin:$PATH \
    RAILS_ENV=development \
    NODE_ENV=development \
    DISCOURSE_RUNNING_IN_RACK=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    libgmp-dev \
    libpq-dev \
    libvips \
    pkg-config \
    python3 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY . .

RUN bundle config set path "$BUNDLE_PATH" \
    && bundle install \
    && pnpm install --frozen-lockfile

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rake db:prepare && bin/rails server -b 0.0.0.0 -p 3000"]

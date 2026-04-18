FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_APP_CONFIG=/app/.bundle \
    RAILS_ENV=development \
    NODE_ENV=development

WORKDIR /app

# System dependencies for Rails + native gems + JS toolchain
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    build-essential \
    pkg-config \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    libgmp-dev \
    libpq-dev \
    libsqlite3-dev \
    zlib1g-dev \
    libffi-dev \
    libreadline-dev \
    libssl-dev \
    libvips \
    imagemagick \
    tzdata \
  && rm -rf /var/lib/apt/lists/*

# Install the Bundler version required by Gemfile.lock
RUN gem install bundler -v 2.6.4

# Node.js + pnpm for the frontend
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get update && apt-get install -y --no-install-recommends nodejs \
  && corepack enable \
  && corepack prepare pnpm@10.28.0 --activate \
  && rm -rf /var/lib/apt/lists/*

# Copy files needed to resolve Ruby and JS dependencies first
COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY patches ./patches

# Install Ruby dependencies
RUN bundle _2.6.4_ config set --local path "$BUNDLE_PATH" \
  && bundle _2.6.4_ install

# Install JS dependencies
RUN pnpm install --frozen-lockfile

# Copy the rest of the application source
COPY . .

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails server -b 0.0.0.0 -p 3000"]

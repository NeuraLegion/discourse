FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_BIN=/bundle/bin \
    PATH=/bundle/bin:/usr/local/bundle/bin:$PATH \
    RAILS_ENV=development \
    NODE_ENV=development \
    DISCOURSE_RUNNING_IN_RACK=1

WORKDIR /app

# System deps for Rails, native gems, and JS tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    pkg-config \
    libpq-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    libffi-dev \
    libgmp-dev \
    liblz4-dev \
    libvips-dev \
    imagemagick \
    postgresql-client \
    redis-tools \
    && rm -rf /var/lib/apt/lists/*

# Node.js for frontend build/test tasks
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && rm -rf /var/lib/apt/lists/*

# Ruby deps first for caching
COPY Gemfile Gemfile.lock ./
RUN bundle config set without 'production' \
    && bundle install

# Copy the full source tree before pnpm install because the workspace lockfile
# references many package.json files under plugins/themes and patchedDependencies
# under patches/, which must exist during installation.
COPY . .

RUN pnpm install --frozen-lockfile

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails db:prepare && bin/rails server -b 0.0.0.0 -p 3000"]

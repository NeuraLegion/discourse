FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    RAILS_ENV=development \
    NODE_ENV=development \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PATH="/app/node_modules/.bin:${PATH}"

WORKDIR /app

# System dependencies for Rails, native gems, image processing, and JS tooling.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    pkg-config \
    libpq-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    libvips-dev \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libgmp-dev \
    libffi-dev \
    tzdata \
    xz-utils \
  && rm -rf /var/lib/apt/lists/*

# Node.js 20 for pnpm / Ember / asset builds.
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get update && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@10.28.0 --activate

# Copy the full workspace before pnpm install so patched workspace dependencies
# are visible to pnpm. Installing from only the root manifests causes
# ERR_PNPM_UNUSED_PATCH in this repo because several patched packages are only
# referenced by workspace packages.
COPY . .

# Install Ruby gems.
RUN gem update --system && \
    bundle config set path "${BUNDLE_PATH}" && \
    bundle config set without 'production' && \
    bundle install

# Install JS dependencies for the full workspace.
RUN pnpm install --no-frozen-lockfile

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails db:prepare && pnpm dev"]

FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    RAILS_ENV=development \
    NODE_ENV=development \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PATH=/bundle/bin:/app/node_modules/.bin:$PATH

WORKDIR /app

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
      libvips \
      imagemagick \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends \
      nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@10.28.0 --activate

# Install Ruby gems first for caching
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy the full repository before pnpm install so workspace package manifests
# and patch files referenced by the lockfile are available.
COPY . .

# Install JS dependencies from the workspace root
RUN pnpm install --frozen-lockfile

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails server -b 0.0.0.0 -p ${PORT:-3000}"]

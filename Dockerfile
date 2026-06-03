FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_WITHOUT="production" \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PNPM_HOME=/pnpm \
    PATH=/pnpm:$PATH

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      curl \
      ca-certificates \
      brotli \
      libyaml-dev \
      libxml2-dev \
      libxslt1-dev \
      libpq-dev \
      libvips-dev \
      pkg-config \
      python3 \
      python-is-python3 \
      shared-mime-info \
      bash \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 is required for the frontend toolchain
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@10.28.0 --activate

# Copy the full source tree before dependency installation because pnpm workspace
# packages and patchedDependencies are referenced from many subdirectories.
COPY . .

# Install Ruby dependencies
RUN bundle config set path "$BUNDLE_PATH" \
    && bundle install

# Install JS dependencies
RUN pnpm install --frozen-lockfile

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails server -b 0.0.0.0 -p 3000"]

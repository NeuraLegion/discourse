FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    BUNDLE_PATH=/bundle \
    BUNDLE_BIN=/bundle/bin \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_WITHOUT= \
    NODE_ENV=development \
    RAILS_ENV=development \
    DISCOURSE_RUNNING_IN_RACK=1 \
    PNPM_HOME=/usr/local/share/pnpm \
    PATH=/bundle/bin:/usr/local/share/pnpm:$PATH

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    pkg-config \
    ca-certificates \
    gnupg \
    shared-mime-info \
    libssl-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    libpq-dev \
    zlib1g-dev \
    libffi-dev \
    libgmp-dev \
    libvips-dev \
    imagemagick \
    libjemalloc2 \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get update \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@10.28.0 --activate

COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY patches ./patches
COPY frontend ./frontend
COPY plugins ./plugins
COPY themes ./themes
COPY docs ./docs

RUN gem install bundler:2.6.4 \
  && bundle _2.6.4_ config set path "$BUNDLE_PATH" \
  && bundle _2.6.4_ config set without "$BUNDLE_WITHOUT" \
  && bundle _2.6.4_ install \
  && pnpm install --frozen-lockfile

COPY . .

EXPOSE 3000

CMD ["bash", "-lc", "bin/rails server -b 0.0.0.0 -p ${PORT:-3000}"]

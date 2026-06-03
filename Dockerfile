FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    RAILS_ENV=development \
    RACK_ENV=development \
    NODE_ENV=development \
    BUNDLE_PATH=/bundle \
    BUNDLE_WITHOUT=production \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PNPM_HOME=/pnpm \
    PATH=/pnpm:/usr/local/bundle/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    pkg-config \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    libpq-dev \
    libvips-dev \
    imagemagick \
    shared-mime-info \
    python3 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && rm -rf /var/lib/apt/lists/*

COPY . .

RUN gem update --system \
    && gem install bundler -N \
    && bundle config set path "${BUNDLE_PATH}" \
    && bundle config set without "${BUNDLE_WITHOUT}" \
    && bundle install \
    && pnpm install --frozen-lockfile

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails db:prepare && pnpm dev"]

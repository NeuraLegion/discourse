FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_WITHOUT=production \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    NODE_ENV=development \
    RAILS_ENV=development \
    DISCOURSE_RUNNING_IN_RACK=1 \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    libxml2-dev \
    libxslt1-dev \
    libyaml-dev \
    pkg-config \
    postgresql-client \
    redis-tools \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends \
        nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable

COPY . .

RUN gem update --system --no-document \
    && gem install bundler --no-document \
    && bundle config set path "$BUNDLE_PATH" \
    && bundle install \
    && pnpm install --frozen-lockfile --recursive

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails server -b 0.0.0.0 -p 3000"]

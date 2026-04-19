FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_BIN=/bundle/bin \
    GEM_HOME=/bundle \
    PATH=/bundle/bin:/usr/local/bundle/bin:$PATH \
    RAILS_ENV=development \
    NODE_ENV=development

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    pkg-config \
    libpq-dev \
    libssl-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    zlib1g-dev \
    libreadline-dev \
    libffi-dev \
    libgmp-dev \
    imagemagick \
    shared-mime-info \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get update && apt-get install -y --no-install-recommends \
    nodejs \
  && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@10.28.0 --activate

COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY . .

RUN bundle install && pnpm install --frozen-lockfile

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails server -b 0.0.0.0 -p 3000"]

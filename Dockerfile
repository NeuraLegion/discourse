FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_WITHOUT=production \
    NODE_ENV=development \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    SKIP_ENFORCE_HOSTNAME=1 \
    DISCOURSE_HOSTNAME=localhost

WORKDIR /src

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      pkg-config \
      curl \
      ca-certificates \
      bash \
      libpq-dev \
      postgresql-client \
      redis-tools \
      libyaml-dev \
      libxml2-dev \
      libxslt1-dev \
      zlib1g-dev \
      libgmp-dev \
      libffi-dev \
      libssl-dev \
      shared-mime-info \
      imagemagick \
      graphviz \
      wkhtmltopdf \
      libcairo2-dev \
      libpango1.0-dev \
      libjpeg62-turbo-dev \
      libpng-dev \
      libvips-dev \
      fonts-liberation \
      && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g pnpm@10.28.0

# Copy full source before installing JS deps because the pnpm workspace
# references many plugin/theme/frontend package manifests and local patches.
COPY . .

RUN bundle config set path "$BUNDLE_PATH" \
    && bundle install \
    && pnpm install --frozen-lockfile

# Ensure dev/test Docker networking works out of the box
RUN sed -i \
      -e "s/\\<localhost\\>/db/g" \
      -e "s/127\\.0\\.0\\.1/db/g" \
      -e "s/\\<redis\\>/redis/g" \
      config/database.yml || true

# Optional: preinstall Playwright browser dependencies for JS/system tests
RUN pnpm playwright-install || true

EXPOSE 3000 4200

CMD ["bash", "-lc", "bundle exec rails db:prepare && concurrently \"bundle exec rails server -b 0.0.0.0 -p 3000\" \"pnpm --dir=frontend/discourse ember serve --port 4200 --host 0.0.0.0\""]

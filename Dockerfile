FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_WITHOUT="production" \
    BUNDLE_PATH="/bundle" \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PATH="/usr/local/bundle/bin:/usr/local/bin:/usr/bin:/bin" \
    NODE_ENV=development \
    RAILS_ENV=development \
    DISCOURSE_HOSTNAME=localhost \
    DISCOURSE_DEV_DB=discourse_development \
    UNICORN_PORT=3000 \
    UNICORN_BIND_ALL=1 \
    npm_config_update_notifier=false \
    npm_config_fund=false \
    npm_config_audit=false

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      gnupg \
      build-essential \
      pkg-config \
      libyaml-dev \
      libxml2-dev \
      libxslt1-dev \
      libpq-dev \
      liblz4-dev \
      libzstd-dev \
      libvips-dev \
      libjpeg62-turbo-dev \
      libpng-dev \
      libwebp-dev \
      libffi-dev \
      libreadline-dev \
      libsqlite3-dev \
      shared-mime-info \
      imagemagick \
      ffmpeg \
      rsync \
      python3 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && rm -rf /var/lib/apt/lists/*

# Copy the full source before installing JS deps so pnpm can see local patch files
# and every workspace package referenced by pnpm-workspace.yaml.
COPY . .

RUN bundle config set path "${BUNDLE_PATH}" \
    && bundle config set without "${BUNDLE_WITHOUT}" \
    && bundle install \
    && pnpm install --frozen-lockfile=false

RUN sed -i 's/127\.0\.0\.1:/0.0.0.0:/g' config/pitchfork.conf.rb

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec bin/pitchfork"]

FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    COREPACK_ENABLE_STRICT=0 \
    DISCOURSE_DEV_DB=discourse_development \
    DISCOURSE_HOSTNAME=localhost \
    RAILS_ENV=development \
    RACK_ENV=development \
    NODE_ENV=development \
    PATH=/usr/local/bin:/root/.cache/node/corepack/v1/pnpm/10.28.0:$PATH

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
      libxslt-dev \
      libvips-dev \
      imagemagick \
      libsqlite3-dev \
      libffi-dev \
      libgmp-dev \
      libssl-dev \
      tzdata \
      xz-utils \
    && rm -rf /var/lib/apt/lists/*

COPY --from=node:20-bookworm /usr/local/ /usr/local/
COPY --from=node:20-bookworm /opt/yarn-v1.22.22 /opt/yarn-v1.22.22

RUN corepack prepare pnpm@10.28.0 --activate && \
    ln -sf /root/.cache/node/corepack/v1/pnpm/10.28.0/bin/pnpm.cjs /usr/local/bin/pnpm && \
    ln -sf /root/.cache/node/corepack/v1/pnpm/10.28.0/bin/pnpx.cjs /usr/local/bin/pnpx

COPY . .

RUN bundle config set without 'production' && \
    bundle install && \
    pnpm install --frozen-lockfile --ignore-scripts

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails server -b 0.0.0.0 -p 3000"]

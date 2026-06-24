FROM ruby:3.4-bookworm AS base

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development test" \
    RAILS_ENV=production \
    NODE_ENV=production

RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      build-essential \
      libyaml-dev \
      libxml2-dev \
      libxslt-dev \
      libpq-dev \
      pkg-config \
      curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

FROM base AS deps

COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./

# corepack is not available in the ruby image; install Node.js with corepack/pnpm support
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate

COPY . .
RUN pnpm install --frozen-lockfile --ignore-scripts

FROM deps AS build

RUN pnpm run build || true

FROM ruby:3.4-bookworm AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development test" \
    RAILS_ENV=production \
    NODE_ENV=production \
    DISCOURSE_RUNNING_IN_RACK=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      libpq5 \
      curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=deps /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]

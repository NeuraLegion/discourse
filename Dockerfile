FROM ruby:3.4.7-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH="/bundle" \
    BUNDLE_JOBS="4" \
    BUNDLE_RETRY="3" \
    PATH="/bundle/bin:${PATH}" \
    COREPACK_INTEGRITY_KEYS=0

WORKDIR /app

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

RUN gem install bundler -v 2.6.4

# Install Node.js 20+ and pnpm
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get update && apt-get install -y --no-install-recommends nodejs \
  && corepack enable \
  && npm install -g corepack@latest \
  && corepack prepare pnpm@10.28.0 --activate \
  && rm -rf /var/lib/apt/lists/*

# Copy the full repository so workspace packages and patched dependencies are available
COPY . .

# Install Ruby dependencies
RUN rm -f Gemfile.lock && bundle install

# Install JavaScript dependencies with patch application enabled
RUN pnpm install

# Build assets / frontend
RUN pnpm run build || true

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]

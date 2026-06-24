FROM ruby:3.4-bookworm

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  git \
  libpq-dev \
  postgresql-client \
  redis-tools \
  && rm -rf /var/lib/apt/lists/*

# Install a Node.js version that satisfies package.json engines.node (>= 20)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get update && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

RUN gem install bundler -v 2.6.9
RUN npm install -g pnpm@10.28.0

COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.json tsconfig-base.json eslint.config.mjs stylelint.config.mjs lefthook.yml ./
COPY . ./

RUN bundle install
RUN pnpm install --frozen-lockfile

EXPOSE 3000
CMD ["bash", "-lc", "bundle exec rails server -b 0.0.0.0 -p 3000"]

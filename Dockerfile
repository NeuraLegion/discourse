FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    RAILS_ENV=development \
    RACK_ENV=development \
    NODE_ENV=development \
    BUNDLE_WITHOUT="production" \
    BUNDLE_PATH=/bundle \
    GEM_HOME=/bundle \
    PATH=/bundle/bin:/usr/local/bundle/bin:/usr/local/node/bin:$PATH \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    DISCOURSE_RUNNING_IN_RACK=1 \
    SKIP_ENFORCE_HOSTNAME=1 \
    DISCOURSE_REDIS_HOST=redis \
    DISCOURSE_MESSAGE_BUS_REDIS_HOST=redis \
    DISCOURSE_DB_HOST=db

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    pkg-config \
    libpq-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    libffi-dev \
    libgmp-dev \
    libreadline-dev \
    libssl-dev \
    zlib1g-dev \
    libvips-dev \
    chromium \
    shared-mime-info \
    xdg-utils \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get update && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@10.28.0 --activate

WORKDIR /app

COPY . .
RUN bundle install && pnpm install --frozen-lockfile

RUN mkdir -p tmp/pids tmp/cache log && \
    if [ -f config/database.yml ]; then \
      ruby -e 'path="config/database.yml"; s=File.read(path); s.gsub!(/^(\s*)(development|test):(\s*)\n((?:\1  .*(?:\n|$))*)/m) do |m| \
        env=$2; body=$4; \
        if body =~ /host:/; m; \
        else \
          m.sub(/\n$/, "\n") + "  host: db\n"; \
        end \
      end; File.write(path, s)'; \
    fi && \
    if [ -f config/discourse_defaults.conf ]; then \
      sed -i 's/^redis_host *=.*/redis_host = redis/' config/discourse_defaults.conf && \
      sed -i 's/^message_bus_redis_host *=.*/message_bus_redis_host = redis/' config/discourse_defaults.conf && \
      sed -i 's/^db_host *=.*/db_host = db/' config/discourse_defaults.conf; \
    fi

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails db:prepare && bundle exec rails server -b 0.0.0.0 -p 3000"]

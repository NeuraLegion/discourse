FROM ruby:3.4.7-slim-bookworm AS base

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH="/bundle" \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    RAILS_ENV=production \
    RACK_ENV=production

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

FROM base AS bundler

COPY Gemfile Gemfile.lock ./

RUN gem install bundler -v 2.6.4 && \
    bundle install

FROM base AS runtime

ENV PATH="/bundle/bin:${PATH}"

COPY --from=bundler /bundle /bundle
COPY . .

RUN bundle exec rake assets:precompile

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]

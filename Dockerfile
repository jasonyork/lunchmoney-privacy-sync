# syntax=docker/dockerfile:1
# Runs bin/sync-privacy-lm once and exits. Intended for a scheduled job
# (e.g. a Fly.io scheduled Machine); see "Running on a schedule" in README.md.

ARG RUBY_VERSION=3.3

FROM ruby:${RUBY_VERSION}-slim AS build
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV BUNDLE_WITHOUT="development:test" \
    BUNDLE_FROZEN="1"
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 \
 && rm -rf /usr/local/bundle/cache

FROM ruby:${RUBY_VERSION}-slim
WORKDIR /app
ENV BUNDLE_WITHOUT="development:test" \
    BUNDLE_FROZEN="1"
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY Gemfile Gemfile.lock ./
COPY bin ./bin
COPY lib ./lib
RUN useradd --system --uid 1000 app
USER app
CMD ["bundle", "exec", "bin/sync-privacy-lm"]

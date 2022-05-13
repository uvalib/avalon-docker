FROM avalonmediasystem/avalon:7.3 as base
USER root
RUN  apt-get install -y  --fix-missing --no-install-recommends shared-mime-info \
  build-essential \
  pkg-config \
  libyaz-dev
COPY --chown=app:app ./avalon /home/app/avalon

RUN  touch cdn-signing-private-key.pem
# hd_toggle is not used but is auto loaded, causing issues
RUN rm app/assets/javascripts/media_player_wrapper/mejs4_plugin_hd_toggle.es6

USER app

RUN yarn add @uvalib/web-styles@1.3.15
RUN bundle config unset --local with
RUN bundle config unset --local without

FROM base AS dev
USER root
RUN  apt-get install -y --no-install-recommends vim
#USER app
ENV  RAILS_ENV=development
RUN bundle config set --local with 'development postgres zoom aws' without production \
      && bundle update

FROM base as prod
ENV  RAILS_ENV=production
RUN  bundle config set --local without 'development test' \
      && bundle config set --local with 'production postgres zoom aws' \
      && bundle update
RUN  SECRET_KEY_BASE=$(ruby -r 'securerandom' -e 'puts SecureRandom.hex(64)') bundle exec rake webpacker:compile
RUN  SECRET_KEY_BASE=$(ruby -r 'securerandom' -e 'puts SecureRandom.hex(64)') bundle exec rake assets:precompile
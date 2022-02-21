FROM avalonmediasystem/avalon:7.2.1 as base
USER root
RUN  apt-get install -y --no-install-recommends shared-mime-info build-essential
COPY --chown=app:app ./avalon /home/app/avalon
RUN  touch cdn-signing-private-key.pem
USER app

RUN yarn add @uvalib/web-styles@1.3.15

FROM base AS dev
USER root
RUN  apt-get install -y --no-install-recommends vim
USER app
ENV  RAILS_ENV=development
RUN bundle install --with development postgres zoom

FROM base as prod
ENV  RAILS_ENV=production
RUN  bundle install --without development test --with aws production postgres zoom
RUN  SECRET_KEY_BASE=$(ruby -r 'securerandom' -e 'puts SecureRandom.hex(64)') bundle exec rake webpacker:compile
RUN  SECRET_KEY_BASE=$(ruby -r 'securerandom' -e 'puts SecureRandom.hex(64)') bundle exec rake assets:precompile
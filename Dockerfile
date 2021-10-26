FROM avalonmediasystem/avalon:7.2.1 as base
USER root
RUN  apt-get install -y --no-install-recommends shared-mime-info
COPY --chown=app:app ./avalon /home/app/avalon
USER app


FROM base AS dev
USER root
RUN  apt-get install -y --no-install-recommends \
      build-essential  vim
USER app
RUN bundle install --with development postgres zoom
RUN cp /home/app/avalon/config/environments/development.rb /home/app/avalon/config/environments/production.rb

FROM base as prod
ENV  RAILS_ENV=production
RUN  bundle install --without development test --with aws production postgres zoom
RUN  SECRET_KEY_BASE=$(ruby -r 'securerandom' -e 'puts SecureRandom.hex(64)') bundle exec rake webpacker:compile
RUN  SECRET_KEY_BASE=$(ruby -r 'securerandom' -e 'puts SecureRandom.hex(64)') bundle exec rake assets:precompile
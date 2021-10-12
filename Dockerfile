FROM avalonmediasystem/avalon:7.2.1 as prod
USER root
RUN  apt-get install -y --no-install-recommends shared-mime-info
COPY --chown=app:app ./avalon /home/app/avalon
USER app

FROM prod AS dev
USER root
RUN  apt-get install -y --no-install-recommends \
      build-essential cmake vim
USER app
RUN bundle install --with development postgres
RUN cp /home/app/avalon/config/environments/development.rb /home/app/avalon/config/environments/production.rb
# avalon-docker
The project contains the Dockerfiles for all the necessary components of [Avalon Media System](https://github.com/avalonmediasystem/avalon). For developing with Avalon, the docker-compose script in [Avalon](https://github.com/avalonmediasystem/avalon) and [Avalon Bundle](https://github.com/samvera-labs/avalon-bundle) are recommended.

## Prerequisite

### Linux
1. Install [Docker](https://docs.docker.com/engine/installation/linux/centos/)
2. Install [Docker-Compose](https://docs.docker.com/compose/install/)

### MacOS
* Install [Docker Desktop for Mac](https://docs.docker.com/docker-for-mac/install/)
* `docker compose` is built into docker now. Don't use `docker-compose` on macOS.

## Usage
1. Clone this Repo
3. From inside the avalon-docker directory
  * `sudo chmod a+w masterfiles` to setup write permission for shared directory
  * `docker compose build` to get the prebuilt images from [Dockerhub](dockerhub.com)
  * `docker compose up` to stand up the stack. `-d` option to run in background
  * `docker compose up --build` to build and run in one command
  * `docker exec -it avalon-docker-uva-avalon-1 bundle exec rake uva:migrate:all_derivatives` example to run rake tasks

To access the site, visit http://localhost in your browser.

### Notes
* `docker compose logs <service_name>` to see the container(s) logs
* `docker compose build --no-cache <service_name>` to build the image(s) from scratch
* `docker ps` to see all running containers
* `docker exec -it avalon-docker-uva-avalon-1 /bin/bash` to log into Avalon docker container
* `docker compose exec uva-avalon /bin/bash` This also connects to the running container
* `docker compose exec uva-avalon bundle exec rails c` is also very useful
* `docker system prune` is handy if you start running low on disk space

### Local Development
* The docker-compose.yml file in this project is for local development only and is pre-configured for use without additional environment variables.
* UVA customizations should go into avalon/ and:
  * will be copied into the container when built, replacing files from the standard avalon app
  * should mirror the [Avalon repo](https://github.com/avalonmediasystem/avalon)
* docker-compose.yml mounts the local ./masterfiles/  into the container.
* ./masterfiles/dropbox is the local dropbox directory
* other persistent storage uses standard docker volumes called:
  - streaming: nginx streaming files
  - storage: supplemental files stored by activerecord
  - database: the local db
  - fedora: fedora files
  - solr: solr files
* Vim is available in the container
* The first page load takes quite a while as webpacker builds the js assets allowing live code reloading
* Attach to the container to edit the live instance, final changes need to go in `./avalon`.
* `docker compose up --build` will refresh the container with the contents of `./avalon` and start up the stack, but can be slow

### Upgrade Notes

#### Upgrade to Avalon 7.7.2
* required solr upgrade to 9.x
* reindex with `docker exec containerID nohup bundle exec rake avalon:reindex[threads] &`
* `bundle exec rake avalon:migrate:collection_managers`
* `bundle exec rake avalon:migrate:caption_files`

#### Upgrade to Avalon 8.1.1
* created bin/yaz-config to allow zoom gem to build
* updated active_encode_uva for active-encode 1.3.0
* updated db/Dockerfile to Postgres 14
* updated solr/Dockerfile to Solr 9

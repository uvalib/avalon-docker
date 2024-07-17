#!/bin/bash

set -m

./docker_init.sh
bundle exec rails server -b 0.0.0.0 &

./bin/shakapacker-dev-server

fg %1
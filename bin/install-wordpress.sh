#!/bin/bash

# credit: "https://github.com/WordPress/gutenberg"
# under GPL license

# Exit if any command fails.
set -e

# Elementor script includes.
. "$(dirname "$0")/includes.sh"

# Set up environment variables
. "$(dirname "$0")/bootstrap-env.sh"

# These are the containers and values for the development site.
CLI='cli_e2e_tests'
CONTAINER='wordpress_e2e_tests'
SITE_TITLE='Elementor Dev e2e'
HOST_IP='localhost'

# If we're installing/re-installing the test site, change the containers used.
if ! docker ps | grep -q $CONTAINER; then
	echo -e $(error_message "WordPress e2e tests run in their own Docker container, but that container wasn't found.")
	echo "Please restart your Docker containers by running 'docker-compose $DOCKER_COMPOSE_FILE_OPTIONS down && docker-compose $DOCKER_COMPOSE_FILE_OPTIONS up -d' or"
	echo "by running './bin/setup-local-env.sh' again."
	echo ""
	exit 1
fi

if is_windows; then
	HOST_IP=$(docker-machine ip default)
fi
# Get the host port for the WordPress container.
HOST_PORT=$(docker-compose $DOCKER_COMPOSE_FILE_OPTIONS port $CONTAINER 80 | awk -F : '{printf $2}')

# Wait until the Docker containers are running and the WordPress site is
# responding to requests.
echo -en $(status_message "Attempting to connect to WordPress...")
until $(curl -L http://$HOST_IP:$HOST_PORT -so - 2>&1 | grep -q "WordPress"); do
    echo -n '.'
    sleep 5
done
echo ''

# If this is the test site, we reset the database so no posts/comments/etc.
# dirty up the tests.
echo -e $(status_message "Resetting test database...")
docker-compose $DOCKER_COMPOSE_FILE_OPTIONS run --rm -u 33:33 $CLI db reset --yes >/dev/null

# Install WordPress.
echo -e $(status_message "Installing WordPress...")
# The `-u 33` flag tells Docker to run the command as a particular user and
# prevents permissions errors. See: https://github.com/WordPress/gutenberg/pull/8427#issuecomment-410232369
docker-compose $DOCKER_COMPOSE_FILE_OPTIONS run --rm -u 33 $CLI core install --title="$SITE_TITLE" --admin_user=admin --admin_password=password --admin_email=admin@localhost.local --skip-email --url=http://localhost:$HOST_PORT >/dev/null

if [ "$WP_VERSION" == "latest" ]; then
	# Check for WordPress updates, to make sure we're running the very latest version.
	docker-compose $DOCKER_COMPOSE_FILE_OPTIONS run --rm -u 33 $CLI core update >/dev/null
fi

# If the 'wordpress' volume wasn't during the down/up earlier, but the post port has changed, we need to update it.
CURRENT_URL=$(docker-compose $DOCKER_COMPOSE_FILE_OPTIONS run -T --rm $CLI option get siteurl)
if [ "$CURRENT_URL" != "http://$HOST_IP:$HOST_PORT" ]; then
	docker-compose $DOCKER_COMPOSE_FILE_OPTIONS run --rm $CLI option update home "http://$HOST_IP:$HOST_PORT" >/dev/null
	docker-compose $DOCKER_COMPOSE_FILE_OPTIONS run --rm $CLI option update siteurl "http://$HOST_IP:$HOST_PORT" >/dev/null
fi

CURRENT_URL="http://$HOST_IP:$HOST_PORT"

# Activate Elementor.
echo -e $(status_message "Activating Elementor...")
docker-compose $DOCKER_COMPOSE_FILE_OPTIONS run --rm $CLI plugin activate elementor >/dev/null

# Justfile for Glue Unity Catalog Sync POC

# Default recipe
default: status

# Bring up all services in detached mode
build:
    @echo "Building all the images..."
    docker compose build

# Bring up all services in detached mode
up:
    @echo "Starting all services in detached mode..."
    docker compose up -d

# Wipe out containers and volumes, but KEEP images, then start fresh
reset:
    @echo "Resetting containers and volumes (keeping images)..."
    docker compose down -v --remove-orphans
    docker compose up -d

# Bring down all services
down:
    @echo "Stopping all services..."
    docker compose down

# Show the status of all services
status:
    @echo "Checking service status..."
    docker compose ps

# Follow the logs of all services
logs:
    @echo "Following logs for all services..."
    docker compose logs -f

# Nuke all containers, images, volumes, and orphans
nuke:
    @echo "Nuking all containers, images, volumes, and orphans..."
    docker compose down -v --rmi all --remove-orphans

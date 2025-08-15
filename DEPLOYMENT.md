# Deploying Archon to Production

This guide provides instructions for building the production Docker images for Archon, tagging them, and pushing them to a Docker registry like Docker Hub.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) must be installed and running on your system.
- You must have a Docker Hub account and be logged in. You can log in from your terminal with the command:
  ```bash
  docker login
  ```

## 1. Building the Production Images

The `docker-compose.prod.yml` file is configured to build production-ready images for all of Archon's services. To build the images, run the following command from the root of the repository:

```bash
docker-compose -f docker-compose.prod.yml build
```

This will build the following images with the `kdegeek/` prefix, ready to be pushed to Docker Hub:
- `kdegeek/archon-server:latest`
- `kdegeek/archon-mcp:latest`
- `kdegeek/archon-agents:latest`
- `kdegeek/archon-ui:latest`

## 2. Pushing the Images to Docker Hub

Once the images are built, you can push them to Docker Hub:

```bash
docker push kdegeek/archon-server:latest
docker push kdegeek/archon-mcp:latest
docker push kdegeek/archon-agents:latest
docker push kdegeek/archon-ui:latest
```

After these steps, your production-ready Docker images will be available on your Docker Hub repository, ready to be used in a production environment like Unraid.

# Dockerfile for n8n optimized for AWS deployment (ECR, ECS/EKS)

#############################################
# Stage 1: Builder - Install n8n dependencies
#############################################
# Use a lightweight Node.js Long Term Support (LTS) Alpine image.
# Alpine is chosen for its minimal size, contributing to smaller final images.
FROM node:lts-alpine AS builder

# Set the working directory inside this builder container.
WORKDIR /app

# Install n8n globally within this builder stage.
# We're installing the latest stable version. For production, you might consider pinning
# to a specific n8n version (e.g., `n8n@1.40.0`) to ensure consistent deployments.
# `--unsafe-perm`: Sometimes necessary for packages with native dependencies.
# `--no-audit`, `--no-update-notifier`: Reduce log noise during the build.
RUN npm install -g n8n@latest --unsafe-perm --no-audit --no-update-notifier

#############################################
# Stage 2: Production/Runtime - Create the final minimal image
#############################################
# Use the same lightweight Node.js LTS Alpine image for the final runtime.
# This ensures a consistent environment with the builder but starts clean.
FROM node:lts-alpine

# Set environment variables for n8n's configuration.
# These values can be overridden via environment variables in your Terraform
# ECS Task Definition or Kubernetes Deployment.
# N8N_HOST: '0.0.0.0' makes n8n listen on all available network interfaces,
# which is essential for containerized environments.
ENV N8N_HOST=0.0.0.0
# N8N_PORT: The default port n8n listens on. This *must* match the port
# exposed by the container and configured in your AWS Load Balancer/Service.
ENV N8N_PORT=5678

# Set the working directory for the n8n application within the final container.
WORKDIR /usr/local/bin/n8n

# Create a non-root user and group for enhanced security.
# Running applications as non-root is a critical security best practice in Docker.
RUN addgroup --system n8n && adduser --system --ingroup n8n n8n

# Copy only the necessary n8n installation artifacts from the 'builder' stage.
# This ensures that build tools and development dependencies from the 'builder'
# stage are NOT included in the final runtime image, significantly reducing its size.
COPY --from=builder /usr/local/bin/n8n /usr/local/bin/n8n
COPY --from=builder /usr/local/lib/node_modules/n8n /usr/local/lib/node_modules/n8n

# Ensure the non-root user owns the n8n installation directories.
# This is crucial for the n8n application to run successfully as the 'n8n' user.
RUN chown -R n8n:n8n /usr/local/bin/n8n /usr/local/lib/node_modules/n8n

# Switch to the non-root user. All subsequent commands (and the CMD) will run as 'n8n'.
USER n8n

# Expose the port that n8n listens on.
# This informs Docker (and AWS services like ECS) that this port is used.
EXPOSE ${N8N_PORT}

# Define the command to run n8n when the container starts.
# This is the entry point for your n8n application.
CMD ["n8n", "start"]

# Healthcheck for robust deployments on ECS/EKS.
# This regularly checks if the n8n service inside the container is responsive.
# If the healthcheck fails, ECS/EKS will mark the container as unhealthy and can
# replace it, improving application reliability.
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD wget --spider -q http://localhost:${N8N_PORT}/healthz || exit 1

# Optional: Add labels for image metadata (useful for tracing/management)
LABEL org.opencontainers.image.source="https://github.com/your-org/your-n8n-repo"
LABEL org.opencontainers.image.description="n8n instance deployed on AWS"
LABEL org.opencontainers.image.licenses="MIT" # Or your actual license
# Start with a builder stage to install n8n
FROM node:lts-alpine AS builder

# Set the working directory for n8n installation to /usr/local.
# This allows 'npm install -g' to install into /usr/local/bin and /usr/local/lib/node_modules naturally.
WORKDIR /usr/local

# Install n8n globally in this builder stage
RUN npm install -g n8n@latest --unsafe-perm --no-audit --no-update-notifier

# --- Final Stage for the N8n Application ---
FROM node:lts-alpine

# Set the working directory for the final n8n application
# This is where the application will run from in the final image
WORKDIR /usr/local/bin/n8n # Changed this WORKDIR to be the actual N8N installation path for clarity

# Create a non-root user for security best practice
RUN addgroup --system n8n && adduser --system --ingroup n8n n8n

# Copy the installed n8n application and its modules from the builder stage
# /usr/local/bin/n8n contains the executable symlink/script
# /usr/local/lib/node_modules/n8n contains the main n8n package
COPY --from=builder /usr/local/bin/n8n /usr/local/bin/n8n
COPY --from=builder /usr/local/lib/node_modules/n8n /usr/local/lib/node_modules/n8n

# Set ownership of the n8n installation to the new non-root user
RUN chown -R n8n:n8n /usr/local/bin/n8n /usr/local/lib/node_modules/n8n

# Switch to the non-root user
USER n8n

# Expose the port n8n listens on (default is 5678)
EXPOSE 5678

# Command to run n8n when the container starts
CMD ["n8n"]
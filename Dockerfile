# builder stage
FROM node:lts-alpine AS builder

WORKDIR /usr/local/bin/n8n

RUN npm install -g n8n@latest --unsafe-perm --no-audit --no-update-notifier

# final stage
FROM node:lts-alpine

WORKDIR /usr/local/bin/n8n

# Add n8n user and group
RUN addgroup --system n8n && adduser --system --ingroup n8n n8n

# Copy n8n from builder stage
COPY --from=builder /usr/local/bin/n8n /usr/local/bin/n8n
COPY --from=builder /usr/local/lib/node_modules/n8n /usr/local/lib/node_modules/n8n

# Set permissions
RUN chown -R n8n:n8n /usr/local/bin/n8n /usr/local/lib/node_modules/n8n

# Switch to n8n user
USER n8n

# Expose the port n8n listens on
EXPOSE 5678

# Command to run n8n
CMD ["n8n"]
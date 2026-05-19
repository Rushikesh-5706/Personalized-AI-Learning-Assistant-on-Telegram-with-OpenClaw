FROM node:20-alpine AS base

LABEL maintainer="rushi5706"
LABEL description="OpenClaw Telegram Learning Assistant — self-hosted AI agent"

RUN apk add --no-cache \
    curl \
    bash \
    tzdata \
    && rm -rf /var/cache/apk/*

RUN npm install -g openclaw --no-audit --no-fund

RUN addgroup -S openclaw && adduser -S openclaw -G openclaw

USER openclaw

WORKDIR /home/openclaw

RUN mkdir -p /home/openclaw/.openclaw/skills/user-onboarding \
             /home/openclaw/.openclaw/skills/daily-quiz \
             /home/openclaw/.openclaw/memory

COPY --chown=openclaw:openclaw skills/user-onboarding/SKILL.md \
    /home/openclaw/.openclaw/skills/user-onboarding/SKILL.md

COPY --chown=openclaw:openclaw skills/daily-quiz/SKILL.md \
    /home/openclaw/.openclaw/skills/daily-quiz/SKILL.md

COPY --chown=openclaw:openclaw config/openclaw.json \
    /home/openclaw/.openclaw/openclaw.json

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

CMD ["openclaw", "gateway", "start"]

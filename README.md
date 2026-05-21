# Personalized AI Learning Assistant on Telegram

A self-hosted Telegram bot powered by OpenClaw that learns your technical background
and delivers a curated daily brief every evening — five interview questions and three
to five technical tidbits pulled from the live web, tailored to your domains and
experience level.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Setup and Installation](#setup-and-installation)
- [Running with Docker](#running-with-docker)
- [Running Locally Without Docker](#running-locally-without-docker)
- [How the Onboarding Works](#how-the-onboarding-works)
- [How the Daily Brief Works](#how-the-daily-brief-works)
- [Design Decisions](#design-decisions)
- [Environment Variables](#environment-variables)
- [Verifying the Setup](#verifying-the-setup)
- [Troubleshooting](#troubleshooting)

---

## Overview

This assistant solves a specific problem: staying sharp technically requires consistency,
but sourcing fresh practice questions and keeping up with rapidly evolving domains takes
time most engineers do not have. This bot handles that entirely.

The first time you message the bot, it walks you through a short onboarding conversation
to understand your domains, experience level, goals, and timezone. It stores your profile
in OpenClaw's persistent memory. Every evening at 9 PM in your timezone, it searches
the web for recent content in your areas of interest, synthesizes what it finds, generates
five calibrated interview questions, and sends the formatted brief directly to your Telegram.

The entire system runs on your own hardware. No cloud subscription, no data leaving your
machine (unless you opt for a cloud LLM provider).

---

## Architecture

The system follows a layered agent architecture. The OpenClaw Gateway acts as the central
orchestrator, routing messages from Telegram through the agent's reasoning engine, which
consults skill definitions, calls external tools, and reads and writes persistent memory.

```
 ┌─────────────────────┐                        ┌──────────────────────┐
 │     User Device     │                        │     External Web     │
 │  ─────────────────  │                        │  ──────────────────  │
 │    Telegram App     │                        │  DuckDuckGo Search   │
 └──────────┬──────────┘                        └──────────┬───────────┘
            │ (1) send message                             │ (5) results
            ▼                                              │
 ┌──────────────────────┐                      ┌──────────┴───────────┐
 │    Telegram API      │                      │   web_search tool    │
 │    (cloud / ext.)    │                      │   web_fetch tool     │
 └──────────┬───────────┘                      └──────────┬───────────┘
            │ (2) forward to gateway                      │ (4) invoked by agent
            ▼                                             │
 ┌──────────────────────────────────────────────────────────────────────┐
 │                  OpenClaw Gateway  ─  Your Machine                   │
 │                                                                      │
 │  ┌──────────────────┐    ┌─────────────────────────────────────┐     │
 │  │  Cron Scheduler  │    │           Agent Core (LLM)          │ ◄───┤
 │  │  ─────────────── │───►│         Ollama · gemma2:2b          │     │
 │  │  0 21 * * *      │    │                                     │     │ 
 │  │  per user TZ     │    └──────┬──────────────────────┬───────┘     │
 │  └──────────────────┘           │                      │             │
 │                                 │ (3) reads skill      │ (6) r/w     │
 │  ┌──────────────────┐           ▼                      ▼             │
 │  │ Telegram Plugin  │  ┌─────────────────┐   ┌───────────────────┐   │
 │  │ ───────────────  │  │  Skill Registry │   │ Persistent Memory │   │
 │  │ persistent conn  │  │ ─────────────── │   │ ───────────────── │   │
 │  │ recv / send msgs │  │ user-onboarding │   │ user_profile_{id} │   │
 │  └────────┬─────────┘  │ SKILL.md        │   │ recent_topics_{id}│   │
 │           │            │                 │   │                   │   │
 │           │            │ daily-quiz      │   │ persisted to disk │   │
 │           │            │ SKILL.md        │   │ survives restarts │   │
 │           │            └─────────────────┘   └───────────────────┘   │
 └───────────┼──────────────────────────────────────────────────────────┘
             │ (7) send formatted brief
             ▼
 ┌──────────────────────┐
 │    Telegram API      │
 └──────────┬───────────┘
            │
            ▼
 ┌─────────────────────┐
 │     User Device     │
 │    Telegram App     │
 └─────────────────────┘
```

| Component | Responsibility |
|---|---|
| **Telegram Plugin** | Maintains a persistent long-poll connection to Telegram API. Receives inbound messages and routes them into the agent context. Sends outbound messages back to the user. |
| **Agent Core** | LLM-powered reasoning engine running on Ollama with gemma2:2b locally. Parses skill instructions, decides which tools to call, and assembles final responses. |
| **Skill Registry** | Reads SKILL.md files from the configured skill directories and makes their instructions available to the agent as behavioral context on each invocation. |
| **Persistent Memory** | Key-value store backed by disk storage. Survives gateway restarts. Holds `user_profile_{id}` and `recent_topics_{id}` entries per user. |
| **web_search** | Queries DuckDuckGo for recent content matching the user's configured domains. Used in the daily brief workflow to ensure freshness. |
| **web_fetch** | Fetches and parses the full content of a given URL. Used to go beyond search snippets and extract detailed, synthesizable information from articles. |
| **Cron Scheduler** | Built-in OpenClaw scheduler. Triggers the daily brief generation at 9:00 PM in the user's configured IANA timezone on the `0 21 * * *` schedule. |
| **Standing Order** | Evaluates a memory condition on every inbound message. Fires the user-onboarding skill exactly once — when `user_profile_{id}` does not yet exist in memory. |

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Node.js | 20 LTS or higher | Required for OpenClaw |
| npm | 10 or higher | Installed with Node.js |
| Ollama | Latest | For local LLM inference |
| Docker | 24 or higher | Required for containerized deployment |
| Docker Compose | 2.20 or higher | Included in Docker Desktop |
| Telegram account | — | Required to create and use the bot |
| Git | 2.40 or higher | For repository management |

---

## Project Structure

```
.
├── skills/
│   ├── user-onboarding/
│   │   └── SKILL.md          # Sequential onboarding interview flow and memory schema
│   └── daily-quiz/
│       └── SKILL.md          # Daily brief generation: web search, questions, Telegram send
├── config/
│   └── openclaw.json         # Full gateway config: Ollama, DuckDuckGo, Telegram plugin, cron
├── Dockerfile                # node:20-alpine image, non-root user, health check
├── docker-compose.yml        # Orchestrates openclaw-agent + openclaw-ollama with volumes
├── .env.example              # Documents required env vars — safe to commit, no real values
├── .gitignore                # Excludes .env, node_modules, runtime data, OS artifacts
├── .dockerignore             # Excludes .env, .git, node_modules from build context
└── README.md                 # This file
```

---

## Setup and Installation

### Step 1 — Clone the Repository

```bash
git clone https://github.com/Rushikesh-5706/Personalized-AI-Learning-Assistant-on-Telegram-with-OpenClaw.git
cd Personalized-AI-Learning-Assistant-on-Telegram-with-OpenClaw
```

### Step 2 — Create Your Environment File

```bash
cp .env.example .env
```

Open `.env` in any text editor and fill in your values:

```
TELEGRAM_BOT_TOKEN=your_actual_token_from_botfather
USER_TIMEZONE=Asia/Kolkata
```

Your Telegram Bot Token comes from @BotFather. Start a conversation with @BotFather on
Telegram, send `/newbot`, follow the prompts, and copy the token it gives you.

### Step 3 — Create Your Telegram Bot

1. Open Telegram and search for `@BotFather`
2. Send `/newbot`
3. Provide a display name and a username ending in `bot`
4. Copy the API token provided and paste it into your `.env` file

---

## Running with Docker

This is the recommended approach. It handles all dependencies including Ollama.

### Step 1 — Pull the LLM Model

Before starting, pull the required model into Ollama:

```bash
docker compose run --rm ollama ollama pull gemma2:2b
```

### Step 2 — Build and Start All Services

```bash
docker compose up --build -d
```

This starts two services:
- `openclaw-ollama`: local LLM inference server
- `openclaw-agent`: the OpenClaw gateway with Telegram and skills loaded

### Step 3 — Verify the Agent is Running

```bash
docker compose logs -f agent
```

You should see log output showing the gateway started, the Telegram plugin connected, and
the skills loaded from the skills directory. If you see a line indicating the Telegram
connection is established, the setup is complete.

### Step 4 — Test the Bot

Open Telegram, find your bot by its username, and send any message. The onboarding flow
should start automatically within a few seconds.

---

## Running Locally Without Docker

If you prefer to run without containers:

### Step 1 — Install Ollama

```bash
curl -fsSL https://ollama.ai/install.sh | sh
ollama pull gemma2:2b
```

Start the Ollama server in a separate terminal and leave it running:

```bash
ollama serve
```

### Step 2 — Install OpenClaw

```bash
npm install -g openclaw
```

### Step 3 — Run the Initial OpenClaw Onboarding

```bash
openclaw onboard
```

When prompted, select Ollama as the model provider and gemma2:2b as the model. Select
DuckDuckGo for web search. This creates `~/.openclaw/openclaw.json`.

### Step 4 — Copy Skills into the OpenClaw Directory

```bash
mkdir -p ~/.openclaw/skills/user-onboarding ~/.openclaw/skills/daily-quiz
cp skills/user-onboarding/SKILL.md ~/.openclaw/skills/user-onboarding/SKILL.md
cp skills/daily-quiz/SKILL.md ~/.openclaw/skills/daily-quiz/SKILL.md
```

### Step 5 — Configure the Telegram Plugin

Open `~/.openclaw/openclaw.json` and add the Telegram plugin configuration. Reference the
`config/openclaw.json` file in this repository for the exact structure. Replace the
`botToken` value with your environment variable reference:

```json
"botToken": "${env.TELEGRAM_BOT_TOKEN}"
```

### Step 6 — Set Up the Standing Order and Cron Job

```bash
openclaw standing-orders add \
  --name "trigger-user-onboarding" \
  --if "memory.user_profile_{{user.id}} does not exist" \
  --run-skill "user-onboarding"

openclaw cron add \
  --name "nightly-tech-brief" \
  --cron "0 21 * * *" \
  --tz "${USER_TIMEZONE}" \
  --session isolated \
  --message "Run the daily-quiz skill for the primary user. Retrieve their stored profile and generate and send the daily tech brief to them on Telegram." \
  --announce \
  --channel telegram
```

### Step 7 — Start the Gateway

```bash
openclaw gateway start
```

---

## How the Onboarding Works

When a user sends their first message to the bot and no profile exists for their user ID
in memory, the Standing Order rule fires and the agent executes the `user-onboarding` skill.

The skill guides the agent through a sequential four-question interview:

| Question | What It Collects | Memory Field |
|----------|-----------------|--------------|
| Technical domains | Languages and areas of interest | `domains` |
| Experience level | Career stage | `level` |
| Learning goals | What they are working toward | `goals` |
| Timezone | For scheduling the daily brief | `timezone` |

After all answers are collected, the agent stores the profile under the key
`user_profile_{user_id}` in persistent memory. The stored schema is:

```json
{
  "domains": ["Go", "distributed systems"],
  "level": "senior",
  "goals": ["interview preparation", "staying current"],
  "timezone": "Asia/Kolkata"
}
```

The agent then reads the profile back to the user and confirms their setup is complete.

---

## How the Daily Brief Works

At 9:00 PM in the user's configured timezone, the cron job triggers the agent to execute
the `daily-quiz` skill. The workflow proceeds as follows:

| Step | Action |
|------|--------|
| 1 | Retrieve user profile from memory |
| 2 | Run web_search for each domain, fetch recent articles with web_fetch |
| 3 | Retrieve recent topic history to avoid repetition |
| 4 | Synthesize three to five technical tidbits from article content |
| 5 | Generate exactly five interview questions calibrated to the user's level |
| 6 | Update topic history in memory |
| 7 | Format and send the message via Telegram |

The message format is fixed and uses Telegram Markdown:

```
🦞 Your Daily Tech Brief — Date

━━━━━━━━━━━━━━━━━━━━
🧠 Interview Questions
━━━━━━━━━━━━━━━━━━━━

Q1 [Type — Domain]
Question text

Q2 [Type — Domain]
Question text

Q3 [Type — Domain]
Question text

Q4 [Type — Domain]
Question text

Q5 [Type — Domain]
Question text

━━━━━━━━━━━━━━━━━━━━
💡 Today's Tidbits
━━━━━━━━━━━━━━━━━━━━

Tidbit one

Tidbit two

Tidbit three

━━━━━━━━━━━━━━━━━━━━
Reply answers to get feedback, or more for extra questions.
```

---

## Design Decisions

### Onboarding Trigger: Standing Order over Webhook

The onboarding trigger is implemented as a Standing Order rather than a webhook for
three reasons.

First, Standing Orders in OpenClaw evaluate against the agent's memory state on every
incoming message, which means the check is built into the agent's reasoning loop. There is
no separate HTTP endpoint to deploy, no network exposure to manage, and no additional
service to keep healthy.

Second, the condition `memory.user_profile_{{user.id}} does not exist` is precisely what
we need: it fires exactly once per user, the first time they message the bot, and never
again after onboarding is complete. A webhook would require implementing this state check
externally.

Third, Standing Orders survive gateway restarts without additional setup, whereas a webhook
integration would require persistent routing configuration that adds operational complexity
without adding functionality.

A webhook-based approach would be preferable if onboarding needed to integrate with an
external CRM or identity system. For this use case, the Standing Order is the cleaner,
more maintainable choice.

### Local LLM by Default

The configuration defaults to Ollama with gemma2:2b. This keeps all data private, avoids
API costs during development, and makes the project runnable without any accounts or
subscriptions beyond Telegram. Switching to a cloud provider (OpenAI, Anthropic, Google)
requires only changing the `defaultModel` field in `openclaw.json` and providing the
corresponding API key as an environment variable.

### Isolated Cron Sessions

The cron job uses `--session isolated`, which runs the daily brief generation in a fresh
agent context with no conversation history from previous sessions. This prevents the agent
from being influenced by earlier conversations and ensures that each brief is generated
cleanly from the stored memory profile and live web search results.

---

## Environment Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| TELEGRAM_BOT_TOKEN | Yes | Token from @BotFather for your Telegram bot | 123456:ABC-DEF... |
| USER_TIMEZONE | Yes | IANA timezone string for the daily brief schedule | Asia/Kolkata |

All variables must be defined in a `.env` file at the root of the project. The `.env` file
is excluded from version control by `.gitignore`. The `.env.example` file documents the
required variables without real values and is safe to commit.

---

## Verifying the Setup

### Check the Gateway is Running

```bash
# Docker
docker compose logs agent

# Local
openclaw gateway status
```

### Verify Memory After Onboarding

After completing the onboarding conversation, verify your profile was stored:

```bash
# Docker
docker compose exec agent openclaw memory get "user_profile_TELEGRAM_USER_ID"

# Local
openclaw memory get "user_profile_TELEGRAM_USER_ID"
```

Replace `TELEGRAM_USER_ID` with your actual Telegram user ID, which appears in the gateway
logs when you first send a message.

### Trigger the Daily Brief Manually

You do not need to wait until 9 PM to test the daily brief generation:

```bash
# Docker
docker compose exec agent openclaw cron trigger "nightly-tech-brief"

# Local
openclaw cron trigger "nightly-tech-brief"
```

The brief should appear in your Telegram within thirty to sixty seconds depending on
web search and LLM inference speed.

### List All Configured Cron Jobs

```bash
openclaw cron list
```

You should see `nightly-tech-brief` with schedule `0 21 * * *` and the configured timezone.

---

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| Bot does not respond at all | Telegram plugin not connected | Check `TELEGRAM_BOT_TOKEN` in `.env`, restart the agent |
| Onboarding does not start | Standing Order not registered | Re-run the `openclaw standing-orders add` command |
| Cron job does not run at 9 PM | Timezone misconfigured or wrong cron expression | Run `openclaw cron list` and verify the schedule and timezone |
| Agent gives wrong or irrelevant answers | Model too small or context too short | Switch from a smaller model to gemma2:2b or a cloud provider |
| Memory not persisting after restart | Volume not mounted correctly (Docker) | Verify `agent_memory` volume in `docker-compose.yml` |
| Ollama connection refused | Ollama not running | Run `ollama serve` locally or ensure the `ollama` service is healthy in Docker |
| Skill not being followed | Model ignoring instructions | Use a more capable model; gemma2:2b is the minimum recommended |

---

## License

MIT

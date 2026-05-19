# SKILL: Daily Technical Brief and Quiz Generation

## GOAL

Generate a high-quality, personalized daily technical brief for a user and deliver it via
Telegram. The brief must contain exactly five interview questions and between three and five
technical tidbits, all tailored to the user's stored profile. The entire process must be
fully autonomous with no human intervention required.

## CONTEXT

This skill is triggered automatically every evening at 9:00 PM in the user's local timezone
by a scheduled cron job. The agent is provided with the user's unique ID. All content must
be derived from the user's stored preferences and supplemented by live web search results
for freshness and relevance.

## GENERATION WORKFLOW

### Step 1 — Retrieve User Profile

Use the `memory_store` tool to fetch the user's profile using the key
`user_profile_{{user.id}}`. Extract the following fields for use in all subsequent steps:
- `domains`: list of technical areas of interest
- `level`: the user's experience tier
- `goals`: the user's learning objectives
- `timezone`: the user's local timezone (already handled by the scheduler)

If the profile does not exist or cannot be retrieved, halt execution and log an error. Do
not send a partial or empty message to the user.

### Step 2 — Conduct Web Search

For each domain in the user's `domains` list, perform a `web_search` call. The search query
must follow this pattern:

`<domain> latest techniques best practices <current_year>`

For example:
- "Go programming language concurrency patterns 2025"
- "distributed systems consensus algorithms recent developments 2025"
- "Python async performance optimization 2025"

Use the freshness or recency parameter if available to prioritize results from the past
thirty days. Collect the top three to five results per domain. Use the `web_fetch` tool
to read the full content of at least one article per domain to ensure depth of information
beyond the snippet.

Do not rely solely on search snippets for tidbit generation. At least one fetched article
per domain must inform the tidbits.

### Step 3 — Retrieve Recently Asked Topics

Use the `memory_store` tool to fetch the key `recent_topics_{{user.id}}`. This key contains
a list of topics that were covered in previous daily briefs. If the key does not exist,
treat the list as empty. Use this list to avoid repeating the same question topics in
consecutive briefs.

### Step 4 — Synthesize Technical Tidbits

Based on the web search results and fetched articles, synthesize between three and five
technical tidbits. Each tidbit must meet all of the following criteria:

- It must be a concrete, actionable, or genuinely surprising insight — not a generic
  definition or introductory statement
- It must be directly relevant to one of the user's specified domains
- It must be written in one to three sentences
- It must be accurate and verifiable from the source material retrieved in Step 2
- It must not repeat a tidbit from the previous brief (check recent_topics memory)

### Step 5 — Generate Interview Questions

Generate exactly five interview questions. Each question must satisfy all of the following
criteria:

Relevance: The question must relate to one or more of the user's stored domains.

Difficulty calibration:
- junior: conceptual understanding, basic syntax, common patterns, no system design
- mid-level: applied knowledge, moderate algorithmic complexity, component-level design
- senior: deep architectural trade-offs, performance at scale, cross-system reasoning
- staff: organizational impact, platform design, cross-team technical decision-making

Variety: The five questions must cover at least three of the following four types:
- Conceptual (understanding of principles, terminology, mechanisms)
- Coding or algorithmic (produce or analyze code, time/space complexity)
- System design (architect a component or service)
- Behavioral (situational, past experience, decision-making — phrased technically)

Novelty: Cross-reference the `recent_topics_{{user.id}}` memory key. Do not generate a
question on any topic that appeared in the last seven days of briefs.

Each question must be self-contained and answerable. Do not generate trick questions or
intentionally ambiguous questions.

### Step 6 — Update Topic Memory

After generating the questions and tidbits, update the `recent_topics_{{user.id}}` memory
key using the `memory_store` tool. Append the topics covered in today's brief to the
existing list. Retain only the last fourteen days of topic entries to prevent unbounded
growth. Store the updated list before sending the message.

### Step 7 — Format and Send the Message

Assemble the final Telegram message using the following exact format. Do not deviate from
this structure. The separators, the bold markers, and the section headers must match exactly.

```
🦞 *Your Daily Tech Brief* — {{current_date}}

━━━━━━━━━━━━━━━━━━━━
🧠 *Interview Questions*
━━━━━━━━━━━━━━━━━━━━

*Q1 [{{type}} — {{domain}}]*
{{question_1_text}}

*Q2 [{{type}} — {{domain}}]*
{{question_2_text}}

*Q3 [{{type}} — {{domain}}]*
{{question_3_text}}

*Q4 [{{type}} — {{domain}}]*
{{question_4_text}}

*Q5 [{{type}} — {{domain}}]*
{{question_5_text}}

━━━━━━━━━━━━━━━━━━━━
💡 *Today's Tidbits*
━━━━━━━━━━━━━━━━━━━━

• {{tidbit_1}}

• {{tidbit_2}}

• {{tidbit_3}}

━━━━━━━━━━━━━━━━━━━━
Reply *answers* to get feedback, or *more* for extra questions.
```

The `{{type}}` label for each question must be one of: Conceptual, Coding, System Design,
Behavioral.

The `{{domain}}` label must match the relevant domain from the user's profile.

The `{{current_date}}` must be formatted as: Day, DD Month YYYY (example: Tuesday, 20 May 2025).

## CONSTRAINTS

- The entire workflow must be fully autonomous. No clarification messages, no prompts to
  the user mid-generation.
- A minimum of three tidbits and exactly five questions must be present in every message.
  If generation fails to meet this threshold, retry once before logging an error.
- The Telegram message must use Markdown formatting compatible with Telegram's MarkdownV2
  parser. Bold uses single asterisks. No raw HTML.
- Memory updates in Step 6 must complete before the message is sent in Step 7. If memory
  update fails, log the error but proceed with sending the message.
- Web search must be invoked. Static or hardcoded question banks are not acceptable.
  The freshness of content is part of the evaluation criteria.
- The message must be readable and well-spaced on a mobile screen. Do not produce walls
  of text within individual questions or tidbits.

# Task Template — ITSM Build Doc Review Run

**Use with:** `helix-reviewer.md` system prompt
**Version:** 1.0

---

## Task

Perform a second-opinion review of the ITSM build documentation in `./inputs-raw/` using the rubric in `prompts/agents/helix-reviewer.md`.

---

## Inputs

- **Documents:** `./inputs-raw/` — all `.docx` and `.xlsx` files
- **Rubric:** `prompts/agents/helix-reviewer.md`

---

## MANDATORY PRE-FLIGHT (Sanitize First)

Before analysis, create a sanitized working set of each DOCX/XLSX by redacting:
- emails, names, phone numbers
- internal URLs, hostnames, server names, file shares
- tenant/org identifiers, environment IDs
- API keys, tokens, secrets

Replace all sensitive values with typed placeholders:
`<REDACTED:EMAIL>`, `<REDACTED:URL>`, `<REDACTED:HOST>`, `<REDACTED:TENANT>`, `<REDACTED:TOKEN>`, `<REDACTED:USER>`

Only use sanitized content in **all** outputs. Do not repeat sensitive strings.

---

## Review Scope

- Provide a second opinion only. **Do NOT rewrite the integrator docs.**
- Produce one review per document with all 7 sections from the rubric:
  1. Manager Summary (Green/Yellow/Red + why + go/no-go triggers)
  2. What Looks Strong
  3. Observations & Risks (P0/P1/P2 - include Owner split for all P0 items)
  4. Assumptions & Hidden Dependencies
  5. UAT Checklist (Minimum UAT Must-Pass first)
  6. Questions for the Integrator (8-15 max)
  7. If I Were Owning This Later...

---

## Output Format (Produce Both)

### A) Markdown - source of truth
- One `.md` file per module review
- One `00_Manager_Rollup.md` synthesizing all modules
- Save to: `./reviews/md/`

### B) Word - shareable deliverable
- Matching `.docx` for each review + rollup
- Formatting: Heading 1/2/3 + bullets only (no complex tables unless necessary)
- Save to: `./reviews/docx/`

---

## Filename Convention

Use the same base name for both `.md` and `.docx`:

```
00_Manager_Rollup
01_[Module_Name]
02_[Module_Name]
...
```

---

## Priority Order

If time is limited, prioritize: **Integrations -> CMDB -> Data Migration** first.
Notification and Major Incident modules are lower risk if deferred.

---

## Finishing Step — Manager Rollup

In `00_Manager_Rollup`, include:
- Cross-doc themes (top 5)
- Top 5 P0 risks across all docs with owner split
- Recommended next actions (Integrator vs Client owners)
- Minimum UAT "must-pass" summary (10 bullets max)

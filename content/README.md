# Versioned content inputs

This directory contains the smallest reviewed, non-secret inputs needed for a
clean checkout to run the student-content contract tests.

- `scope/out_of_scope_patterns.csv` is the audited recall list used by
  `scripts/validate-zero-forgetting-content.mjs`. Source SHA-256:
  `6eb2382503b989b7e7c46b167259576cf4368b560116255204bff59ab9b64803`.
- `knowledge/h1_opening_knowledge_cards.json` contains the two approved v4
  structured H1 cards already active in production. Source SHA-256:
  `46b465ee3840d62b35ea32bc2498e09b86c8952282d927c7c4fecbee96ed5460`.

The source files came from the read-only handoff media. Raw papers, student
data, access codes, teacher-only analysis images, and unpublished candidates
are deliberately excluded.

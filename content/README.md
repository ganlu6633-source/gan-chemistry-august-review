# Versioned content inputs

This directory contains the smallest reviewed, non-secret inputs needed for a
clean checkout to run the student-content contract tests.

- `scope/out_of_scope_patterns.csv` is the audited recall list used by
  `scripts/validate-zero-forgetting-content.mjs`. Source SHA-256:
  `6eb2382503b989b7e7c46b167259576cf4368b560116255204bff59ab9b64803`.
- `knowledge/h1_opening_knowledge_cards.json` contains the two approved v4
  structured H1 cards already active in production. Source SHA-256:
  `46b465ee3840d62b35ea32bc2498e09b86c8952282d927c7c4fecbee96ed5460`.
- `junior/keyue_9up_1_1_day1.audit.json` contains only the versioned audit
  manifest for the verified Keyue Grade 9 upper-volume section 1.1 day-one
  candidate: IDs, counts, fingerprints, rights status, and source/hash
  statuses. It contains no knowledge-card prose, question text, options,
  answers, explanations, hints, source paths, or source locators.

The source evidence came from the private local material sets on the computer
and, where applicable, read-only handoff media. Raw papers, student data,
access codes, teacher-only analysis images, and unpublished candidates are
deliberately excluded.

The complete junior import payload and its local validator belong under the
gitignored `private-import/junior/` directory. The tracked audit manifest has
`auto_publish: false`; publishing requires an explicit private import,
release review, and separate redistribution-rights decision.

The day-one card fingerprints use the same UTF-8 byte-length-framed runtime
payload that the private release migration verifies. The private validator
maps the eight reviewed student-card fields into the exact database card row,
recomputes all three digests, and keeps the complete prose outside Git.

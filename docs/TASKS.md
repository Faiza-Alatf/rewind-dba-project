# Team tasks – Rewind

The baseline project (SQL + GUI) is already in `main`. Each member owns one area, must understand it
fully (the viva will ask), and completes the branch tasks below.

| Member | Branch prefix | Area owned |
|---|---|---|
| **Faiza Altaf** | `feature/faiza-*` | Database design, sample data, ER diagram, project report |
| **Mahnoor Sharif** | `feature/mahnoor-*` | Audit triggers (`04`, `05`) and suspicious-activity rules |
| **Hadiqa Mehmood** | `feature/hadiqa-*` | Recovery package (`06`), transactions/rollback, tests (`08`) |
| **Abdullah Zia Satti** | `feature/abdullah-*` | Security (`01`, `07`), reports/views, Streamlit GUI, final demo |

## Day-by-day plan (10 days)
| Day | Faiza | Mahnoor | Hadiqa | Abdullah |
|---|---|---|---|---|
| 1 | Install Oracle XE, run scripts `01`–`07`; fix errors | Same setup; read `04`/`05` and explain trigger flow | Same setup; read `06` | Same setup; run the GUI and log in as all 4 users |
| 2 | Draw ER diagram (draw.io) → `docs/er_diagram.png` | Run trigger tests: INSERT/UPDATE/DELETE and check `audit_log` | Run `08_tests.sql`; list any failures | Screenshot every GUI screen |
| 3 | Data dictionary (`docs/data_dictionary.md`) for all tables | Add rule: *salary changed twice in one day for same employee* | Write `restore_inserted` (undo an INSERT = delete) | Add Oracle password-complexity check / test profile lockout |
| 4 | Script `09_more_sample_data.sql` (100+ employees) | Add rule: *mass delete (5+ deletes in 1 min)* | Write `restore_change_group` (restore all columns of one change) | GUI: add date filter to Timeline & Change History |
| 5 | Extend audit trigger idea to `DEPARTMENTS` (new branch for trigger + view) | Unit tests for every rule in `docs/rules_tests.sql` | Test rollback: force an error mid-restore, prove nothing is left half-done | GUI: report page using `activity_report()` + CSV export |
| 6 | Report chapter 1–2 (intro, requirements, design) | Report chapter: triggers & detection rules | Report chapter: recovery & transactions | Report chapter: security & GUI |
| 7 | Review teammates' PRs (read + comment) | Review PRs | Review PRs | Review PRs |
| 8 | Fix review comments; merge-ready | Fix review comments | Fix review comments | Fix review comments |
| 9 | Presentation slides 1–5 | Slides 6–10 | Demo script + test evidence | Demo rehearsal on a clean machine |
| 10 | Final check, report PDF | Final check | Final check | Tag release `v1.0` |

## Daily status message (post in the group every day)
```
Name:
Done today (with PR link):
Plan for tomorrow:
Blocked on:
```
Paste the group's updates to Claude and say "Day N update" to get review feedback and tomorrow's tasks.

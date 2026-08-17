# Contributing to Scribe

Thank you for helping make private meeting notes accessible to more Mac users.

1. Fork the repository and create a focused branch.
2. Run `sh scripts/check-no-runtime-network.sh` and `swift test`.
3. For capture changes, complete the relevant cases in `MANUAL-TEST.md` on a
   real Mac; automated tests cannot grant or validate macOS audio permissions.
4. Open a pull request that explains the user problem, behavior change, and
   privacy impact.

Please preserve Scribe's product constraints: explicit recording consent,
local files as the source of truth, no account requirement, and no silent
network fallback.

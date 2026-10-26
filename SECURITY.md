# Security policy

## Supported versions

Only the latest release receives fixes. Please check that a problem is still present in the latest version before reporting it.

## Reporting a vulnerability

Please do **not** open a public issue for a security problem.

Use GitHub's private reporting: on the repository page open **Security › Report a vulnerability**. If that option is not available, open a public issue titled "Security" **without any details** and ask for a private way to talk.

Please include: the version of Intermezzo, your macOS version, what you found, how to reproduce it and what an attacker could do with it.

This is a personal project, so I cannot promise a response time, but I read every report and will answer as soon as I can. Please give me reasonable time to fix a problem before you make it public.

## What is in scope

Intermezzo runs locally, has no server and no account. Areas where a problem would matter:

- the `intermezzo://` URL commands, which can be opened by any web page (the README lists this as a known limitation, and each command can be turned off);
- AppleScript rule scripts and the gallery scripts, which run on your Mac;
- the optional AI features: how the API key is stored (macOS Keychain), what is sent to the chosen server, and how answers of a model are handled (they must never be run or applied without the user's approval);
- the sync folder files and the diagnostic log;
- the release build and its provenance attestation.

The app is not notarised and is signed ad hoc, which the README explains. That is a known, documented trade-off, not a vulnerability by itself.

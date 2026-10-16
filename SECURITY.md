# Security Policy

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Report them privately through GitHub instead: open the repository's
**Security** tab and choose **Report a vulnerability**. Only the maintainer can
see the report, and we can discuss and fix it there before anything is made
public.

Helpful details to include:

- what the problem is and what an attacker could do with it
- steps to reproduce, or a proof of concept
- the macOS version and the commit you tested

## Supported versions

Only the latest commit on `main` receives security fixes.

## Scope

MicrophonePicker never records audio; it only changes which input device macOS
uses and that device's level and mute state. Of particular interest are issues
that could let another app or user abuse it to switch, unmute or turn up a
microphone without the user's knowledge.

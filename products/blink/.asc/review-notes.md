# Blink Mobile — App Review notes draft

## Reviewer-facing draft

Blink for iPhone and iPad is a read-only companion to the Blink Mac app. It does
not use accounts or sign-in credentials.

To pair and sync:

1. Put the iPhone or iPad and a Mac running Blink on the same local network.
2. Open Blink on mobile and open Settings.
3. Choose the nearby Mac.
4. Approve the device in Blink on the Mac.
5. The mobile app receives an end-to-end encrypted note snapshot and remains
   readable offline after the Mac disconnects.

The app asks for Local Network permission only to discover and connect to the
Mac. Mobile notes are read-only in this release. Use Settings → Remove Offline
Notes to clear the on-device cache.

## Required before submission

This draft is not sufficient by itself because App Review cannot normally reach
Art's Mac on its LAN. Before submission, choose one:

- provide an explicit reviewer-accessible Mac/pairing arrangement and attach a
  short review video, or
- add a deliberate App Review/demo mode that exercises the shipped read-only UI
  without weakening the production pairing path.

Also provide the App Review contact phone number. Suggested known contact fields
(to confirm, not yet uploaded):

- First name: Arach
- Last name: Tchoupani
- Email: arach@tchoupani.com
- Phone: **PENDING**
- Demo account required: false

The simulator-only fixture at `apps/ios/Fixtures/demo-snapshot.json` was used to
capture truthful screenshots of the real UI. It is not bundled in the production
IPA and must not be represented to App Review as a production demo path.

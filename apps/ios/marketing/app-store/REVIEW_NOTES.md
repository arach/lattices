# App Review notes

Lats Deck does not require an account or sign-in.

The app is an iPad companion for the Lattices macOS menu bar app. The reviewer can inspect every cockpit deck without a Mac by launching the app and using the built-in preview mode. To test live control:

1. Install and launch Lattices on a Mac from https://lattices.dev.
2. Keep the Mac and iPad on the same local network.
3. In Lattices settings on the Mac, enable the Companion bridge.
4. In Lats Deck, choose the discovered Mac and approve the pairing request on the Mac.

The app uses local-network discovery and local HTTP transport only. Pairing requires explicit approval on the Mac. Protected bridge requests are signed and their payloads are encrypted. Pairing keys and trusted-Mac records are stored locally in the iPad Keychain and app preferences.

No user data is collected by the developer, no third-party analytics or advertising SDKs are included, and there are no in-app purchases in version 1.0.

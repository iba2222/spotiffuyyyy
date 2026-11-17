# Iayxify

Spotify 9.1.0 with the Iayxify tweak (6.7.0) injected, built into a sideloadable IPA and
hosted on this repository's Releases.

- **Install page:** https://iba2222.github.io/spotiffuyyyy/
- **SideStore / AltStore source:** https://iba2222.github.io/spotiffuyyyy/source.json
- **Builds:** https://github.com/iba2222/spotiffuyyyy/releases

Every IPA here is unsigned — SideStore/AltStore sign it on the device with your Apple ID,
or Sideloadly signs it on a computer.

## Publishing a build

Run **Build IPA (PATCHED)** in Actions with the URL of a decrypted Spotify IPA and upload
method `release`; the workflow publishes the IPA and refreshes the SideStore source.

An IPA you already built locally can be published the same way:

```sh
GH_TOKEN=<token with Contents: read and write> Tools/publish-ipa.sh Outputs/IPAS/Iayxify-6.7.0-9.1.0.ipa
```

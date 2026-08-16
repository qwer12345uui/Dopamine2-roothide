
# How To Build Your Own tipa on github action

fork this repo then goto tab [Actions] -> [All Workflows] -> [build tip file] -> [Run Workflow] to build tipa file.

- step 1: Login your github account and fork this project

![text](/.pictures/m1.png)
![text](/.pictures/m2.png)


- step 2: Goto the github Actions tab of your forked project and run workflow to build tip file

![text](/.pictures/m3.png)
![text](/.pictures/m4.png)


- step 3: Refresh the page and you will see the progress of the build, wait a few minutes

![text](/.pictures/m5.png)


- step 4: when the build is complete, go to the bottom of the build page to download the tipa file.
  
  (***NOTE: The downloaded file is in zip format, you need to unzip it on your device to get the tipa file***)

![text](/.pictures/m6.png)


***and you will get the contributor with your name on Credits***

![text](/.pictures/m7.png)

## Verified Build and Release Workflow

The `Build and verify roothide Dopamine IPA` workflow builds the revision checked out from this repository, including its pinned submodules. It restores the cached Theos SDK and trustcache toolchain when their build inputs are unchanged, then creates a `.tipa` artifact and validates both the archive structure and required iOS 15 safety regression guards.

| Trigger | Result |
| --- | --- |
| Push or pull request on `2.x` | Builds and uploads a verified artifact retained for 30 days. |
| Manual run without publishing | Builds and uploads a verified artifact only. |
| Push of a `v*` tag | Builds, validates, uploads, and creates a GitHub Release. |
| Manual run with `publish=true` and `release_tag` | Builds, validates, and creates a GitHub Release under the supplied tag. |

The build artifact remains a `.tipa` file inside the downloaded workflow archive. The full investigation and verification boundary for the iOS 15 watchdog/spinlock work are recorded in [`docs/development-log-2026-08-16-ios15-watchdog.md`](docs/development-log-2026-08-16-ios15-watchdog.md).

# Chameleon Ultra GUI
A GUI for the Chameleon Ultra/Chameleon Lite written in Flutter for cross platform operation

[![Auto build](https://github.com/GameTec-live/ChameleonUltraGUI/actions/workflows/build-app.yml/badge.svg)](https://github.com/GameTec-live/ChameleonUltraGUI/actions/workflows/build-app.yml) 
[![Open collective](https://opencollective.com/chameleon-ultra-gui/tiers/badge.svg)](https://opencollective.com/chameleon-ultra-gui#support)
[![Crowdin](https://badges.crowdin.net/chameleonultragui/localized.svg)](https://crowdin.com/project/chameleonultragui)

### [Full documentation here](https://github.com/GameTec-live/ChameleonUltraGUI/tree/main/docs)

## Installation

#### Windows

Download the installer [here](https://nightly.link/GameTec-live/ChameleonUltraGUI/workflows/build-app/main/windows-installer.zip)

Or, [portable version](https://nightly.link/GameTec-live/ChameleonUltraGUI/workflows/build-app/main/windows.zip)


#### Linux

Download the Linux build

- [Debian-based (.deb)](https://nightly.link/GameTec-live/ChameleonUltraGUI/workflows/build-app/main/linux-debian.zip)
- [Arch-based](https://aur.archlinux.org/packages/chameleonultragui-git)
- [Other](https://nightly.link/GameTec-live/ChameleonUltraGUI/workflows/build-app/main/linux.zip)
- [Other (legacy, built on Ubuntu 20.04 LTS)](https://nightly.link/GameTec-live/ChameleonUltraGUI/workflows/build-app/main/linux-legacy.zip)

#### macOS / iOS / iPadOS

Download it from Apple App Store: [Chameleon Ultra GUI](https://apps.apple.com/app/chameleon-ultra-gui/id6462919364)

Or, you can join TestFlight to get builds earlier: [Chameleon Ultra GUI - TestFlight](https://testflight.apple.com/join/UgwgfMqo)

#### Android

Download it from Google Play Store: [Chameleon Ultra GUI](https://play.google.com/store/apps/details?id=io.chameleon.ultra)

Or, plain [APK](https://nightly.link/GameTec-live/ChameleonUltraGUI/workflows/build-app/main/apk.zip)

#### Pending stores:
- F-Store: not yet
- Flathub: not yet
- Chocolatey (Windows): not yet

Note: Under some Linux systems, especially ones running KDE desktop environments, you may need to install the `zenity` package for the file picker to work correctly.

Key:
- apk: Android APK, download and install either via ADB or your app/file manager of choice
- linux: zip file containing the linux build, either run the binary manually or install using cmake
- linux-legacy: same as `linux`, but built on Ubuntu 20.04 LTS. Suited for users on old glibc
- linux-debian: Debian Auto Packaging, download and install with dpkg or apt
- windows: zip file containing windows build, run the binary manually
- windows-installer: NSIS based Windows Installer, Installs the Windows build and creates Shortcuts

#### Note for Linux users:
You might need to add your user to the `dialout` or, on Arch Linux, to the `uucp` group for the app to talk to the device. If your user is not in this group, you may get serial or permission errors.
It is also highly recommended to either uninstall or disable ModemManager (`sudo systemctl disable --now modemmanager`) as many distros ship ModemManager and it may interfere with communication.

## Buy a Chameleon Ultra
- [Sneak Tech](https://sneaktechnology.com/product/chameleon-ultra/)
- [KSEC](https://labs.ksec.co.uk/product/proxgrind-chameleon-ultra/)
- [Lab401](https://lab401.com/products/chameleon-ultra)

## Contributing
Contributions are welcome, most stuff that needs to be done can either be found in our [issues](https://github.com/GameTec-live/ChameleonUltraGUI/issues) or on the [Project board](https://github.com/users/GameTec-live/projects/2)

### Special thanks to [St.Ricky](https://github.com/Saint-Ricky) for designing the App icons

## Translations

If you want to collaborate by adding your language to the application, you can do it through [our Crowdin project](https://crowdin.com/project/chameleonultragui). Do not contribute files into `chameleonultragui/lib/l10n/app_*.arb`. All translations should be added only to Crowdin. If your language is missing, you can create issue and ask to enable it. "Chameleon Ultra GUI", "Chameleon" and other trademarks should not be translated.

## Screenshots
![Connect Page](/screenshots/1.png)
![Home Page](/screenshots/2.png)
![Home Page Settings](/screenshots/3.png)
![Slot Manager Page](/screenshots/4.png)
![Slot Manager Saved Cards](/screenshots/5.png)
![Saved Cards Page](/screenshots/6.png)
![Read Card Page](/screenshots/7.png)
![Read Card Page Mifare Classic](/screenshots/8.png)

## Donate
You want to support us and donate? Thank you, you make it possible for us to keep this app free and make it easier to publish this app on the Apple App Store.

You have the following options:

Open Collective: [Chameleon Ultra GUI](https://opencollective.com/chameleon-ultra-gui)

Crypto Currencies if your into that jam (Although open collective is preferred):
- BTC: bc1qrcd4ctxagaxsetyhpzc08d2upl0mh498gp3lkl
- ETH: 0x0f20e505E9e534236dF4390DcFfD5C4A03C0eec7


## Star History

<a href="https://star-history.com/#GameTec-live/ChameleonUltraGUI&Timeline">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=GameTec-live/ChameleonUltraGUI&type=Timeline&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=GameTec-live/ChameleonUltraGUI&type=Timeline" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=GameTec-live/ChameleonUltraGUI&type=Timeline" />
  </picture>
</a>

# Chameleon Ultra GUI
A GUI for the Chameleon Ultra/Chameleon Lite written in Flutter for cross platform operation

[![Autobuild](https://github.com/GameTec-live/ChameleonUltraGUI/actions/workflows/buildapp.yml/badge.svg)](https://github.com/GameTec-live/ChameleonUltraGUI/actions/workflows/buildapp.yml) 
[![Open collective](https://opencollective.com/chameleon-ultra-gui/tiers/badge.svg)](https://opencollective.com/chameleon-ultra-gui#support)

## Installation
You can download the latest builds from GitHub Actions [here](https://github.com/GameTec-live/ChameleonUltraGUI/actions/workflows/buildapp.yml?query=branch%3Amain) under the artifacts section.

App available in those stores:
- Google Play: https://play.google.com/store/apps/details?id=io.chameleon.ultra
- F-Store: not yet
- App Store: not yet
- Arch Linux (AUR): not yet
- Flathub: not yet
- Chocolatey (Windows): not yet
- Web (for Chromium-based browsers): not yet

Note: Under some Linux systems, especially ones running KDE desktop environments, you may need to install the `zenity` package for the file picker to work correctly.

Key:
- apk: Android APK, download and install either via ADB or your app/file manager of choice
- appbundle: Android Appbundle, unsigned Appbundle, used for Google Play publishing
- linux: zip file containing the linux build, either run the binary manually or install using cmake
- linux-debian: Debain Auto Packaging, Download and install with either apt, apt-get or dpkg.
- windows: zip file containing windows build, run the binary manually
- windows-installer: NSIS based Windows Installer, Installs the Windows build and creates Shortcuts

#### Note for Linux users:
You might need to add your user to the `dialout` or, on Arch Linux, to the `uucp` group for the app to talk to the device. If your user is not in this group, you may get serial or permission errors.
It is also highly recommended to either uninstall or disable ModemManager (`sudo systemctl disable --now modemmanager`) as many distros ship ModemManager and it may interfere with communication.

#### Note for Web users:

You need to pair your Chameleon first before it shows up on the connect page, click on the handshake icon and select the relevant serial devices.

*Known issues*
- Chameleon Lite's are displayed as Ultra's on the connect page (but are correct after connecting)
> This is because the Web Serial API is quite limited with the [device information](https://developer.mozilla.org/en-US/docs/Web/API/SerialPort/getInfo) it returns as it only returns an usb vendor id & product id (which are the same for Ultra's & Lite's). So on the connect page any device will be displayed as an Ultra, after you connect to a specific device the correct device type will be detected by checking if the device supports reader mode (=Ultra) or not (=Lite)
- key recovery is not supported (yet)
- cannot download firmware due to CORS issue with nightly.link

## Contributing
Contributions are welcome, most stuff that needs to be done can either be found in our [issues](https://github.com/GameTec-live/ChameleonUltraGUI/issues) or on the [Project board](https://github.com/users/GameTec-live/projects/2)

## Screenshots
![Connect Page](/screenshots/connect.png)
![Home Page](/screenshots/home.png)
![Slot Manager Page](/screenshots/smanager.png)
![Saved Cards Page](/screenshots/saved.png)
![Read Card Page](/screenshots/rcard.png)
![Settings Page](/screenshots/settings.png)
![Dev Page](/screenshots/devpage.png)

<details>
  <summary>Mac and IOS</summary>

  ### Mac and IOS
  Why are there no macOS and iOS builds?
  
  Currently, we missing two essential parts:
  1. Apple Developer account
  2. Recovery library bindings 

  As Flutter apps don't work in VM environment, we unfortunately can't develop and test ourself
</details>

## Donate
You want to support us and donate? Thank you, you make it possible for us to keep this app free and make it easier to publish this app on the Apple App Store.

You have the following options:

Open Collective: [ChameleonUltraGUI](https://opencollective.com/chameleon-ultra-gui)

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

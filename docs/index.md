# ChamaleonUltraGUI Documentation
## Table of Contents
- [ChamaleonUltraGUI Documentation](#chamaleonultragui-documentation)
  - [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Installation](#installation)
    - [Windows, Linux](#windows-linux)
    - [MacOS](#macos)
    - [Android](#android)
    - [iOS / iPadOS](#ios--ipados)
    - [Web](#web)
  - [Usage](#usage)
  - [Contributing](#contributing)
  - [Translations](#translations)
  - [License](#license)
  - [Credits](#credits)

## Introduction

Welcome to the user documentation for the Chamaleon Ultra GUI, a powerful software tool designed to enhance the usability and functionality of your Chamaleon Ultra device. This comprehensive guide is intended to provide you with the necessary information to make the most out of your experience with this innovative software.

Chamaleon Ultra GUI brings a new dimension of user-friendliness to the management and utilization of your Chamaleon Ultra device. Designed with both beginners and advanced users in mind, this graphical user interface empowers you to harness the full potential of your device's features without the need for extensive technical knowledge.

In this documentation, we will explore the various components and functionalities of the Chamaleon Ultra GUI. From the initial setup and configuration to advanced customization options, you will find step-by-step instructions, visual aids, and tips to ensure a smooth and efficient experience.

Whether you are new to the world of Chamaleon Ultra or a seasoned user looking to maximize your efficiency, this documentation is your gateway to unlocking the capabilities of your device. Let's embark on a journey of discovery and empowerment as we delve into the features and functionalities of the Chamaleon Ultra GUI.

Please refer to the following sections for in-depth information on how to get started, navigate the interface, and make the most of your Chamaleon Ultra device. If you have any questions or encounter difficulties along the way, feel free to reach out to our support team for assistance.

Thank you for choosing Chamaleon Ultra GUI. Let's explore together the world of seamless control and enhanced performance.

## Installation
This section of the documentation will guide you through the process of installing the Chamaleon Ultra GUI software on your system. Whether you are a new user excited to explore the capabilities of Chamaleon Ultra or an existing user upgrading to the latest version, the installation process is the first step toward enhancing your experience.

The installation process is designed to be intuitive and straightforward. We'll provide you with clear instructions and visual aids to help you complete each step efficiently. If you encounter any issues during installation, we've included troubleshooting tips to assist you in resolving common challenges.

### Windows, Linux
[Follow this link](https://github.com/GameTec-live/ChameleonUltraGUI/actions/workflows/build-app.yml) and download the latest build for your system. You can find the installer in the `Artifacts` section of a `Workflow`.

### MacOS
Download it on Apple App Store: [Chamaleon Ultra GUI](https://apps.apple.com/app/chameleon-ultra-gui/id6462919364)

### Android
Download it on Google Play Store: [Chamaleon Ultra GUI](https://play.google.com/store/apps/details?id=io.chameleon.ultra)

### iOS / iPadOS
Download it on Apple App Store: [Chamaleon Ultra GUI](https://apps.apple.com/app/chameleon-ultra-gui/id6462919364)

### Web
**Not available yet**

## Usage
## Contributing
## Translations

To traslate the app to your language, please follow the next steps (example with Spanish):
1. Go our Crowdin project: [Chamaleon Ultra GUI](https://crowdin.com/project/chameleon-ultra-gui), join it and start translating.
2. When you finish the translation, [fork the repository](https://github.com/GameTec-live/ChameleonUltraGUI).
3. On your forked repository, create a new branch with the name of your language in English (e.g. `translate-spanish`).
4. Download the file with the translations from Crowdin and put it in the `chameleonultragui/lib/l10n` folder. Maybe you need to modify the name of the file to match the name of your language in English (e.g. `app_es.arb`). Inside this file, `@@locale` must be the same as the name of the file (e.g. `es`).
5. Go `chameleonultragui/sharedprefsprovider.dart` and inside `getFlag` function add a case with your language (e.g. `case 'es': return 'Español';`).
6. Remove the files inside `.dart_tool/flutter_gen/gen_i10n` and run `flutter pub add intl:any`
7. PR your changes to the `main` branch of the original project.

## License
## Credits


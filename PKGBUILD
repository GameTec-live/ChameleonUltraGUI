pkgname=chameleonultragui-git
pkgver=0.0.0
pkgrel=1
pkgdesc='PKGBUILD for the Chameleon Ultra GUI'
arch=('x86_64')
url="https://github.com/GameTec-live/ChameleonUltraGUI"
depends=('gtk3' 'zenity')
makedepends=('flutter' 'clang' 'cmake' 'ninja' 'pkgconf' 'xz')
source=("git+https://github.com/GameTec-live/ChameleonUltraGUI.git#branch=main")
sha256sums=('SKIP')

pkgver() {
    cd "$pkgname"
    printf "r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short=7 HEAD)"
}

prepare(){
    cd "ChameleonUltraGUI/chameleonultragui"
    flutter --no-version-check config --no-analytics
    flutter --no-version-check config --enable-linux-desktop
    flutter --no-version-check pub get
}

build() {
    cd "ChameleonUltraGUI/chameleonultragui"
    flutter --no-version-check build linux --release
}

package() {
    cd "ChameleonUltraGUI/chameleonultragui/build/linux/x64/release/bundle/"
    # create the target folders
    install -dm 755 "$pkgdir/opt/$pkgname" "$pkgdir/usr/bin/"
    install -Dm644 "../../../../../aur/chameleonultragui.desktop" \
    "${pkgdir}/usr/share/applications/chameleonultragui.desktop"
    install -Dm644 "../../../../../aur/chameleonultragui.png" \
    "${pkgdir}/usr/share/pixmaps/chameleonultragui.png"
    # copy the bundled output to /opt
    cp -rdp --no-preserve=ownership . "$pkgdir/opt/$pkgname/"
    # symlink to /usr/bin so the app can be found in PATH
    ln -s "/opt/$pkgname/chameleonultragui" "$pkgdir/usr/bin/$pkgname"
}
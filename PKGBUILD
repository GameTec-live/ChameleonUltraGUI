pkgname=chameleonultragui
pkgver=0.0.0
pkgrel=1
pkgdesc='PKGBUILD for the Chameleon Ultra GUI'
arch=('x86_64')
url="https://github.com/GameTec-live/ChameleonUltraGUI"
depends=('gtk3' 'zenity')
makedepends=('flutter' 'clang' 'cmake' 'ninja' 'pkgconf' 'xz')
source=("https://github.com/GameTec-live/ChameleonUltraGUI/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('')

prepare(){
    cd "$pkgname-$pkgver"
    flutter --no-version-check config --no-analytics
    flutter --no-version-check config --enable-linux-desktop
    flutter --no-version-check pub get
}

build() {
    cd "$pkgname-$pkgver"
    flutter --no-version-check build linux --release
}

package() {
    cd "$pkgname-$pkgver/build/linux/x64/release/bundle/"
    # create the target folders
    install -dm 755 "$pkgdir/opt/$pkgname" "$pkgdir/usr/bin/"
    # copy the bundled output to /opt
    cp -rdp --no-preserve=ownership . "$pkgdir/opt/$pkgname/"
    # symlink to /usr/bin so the app can be found in PATH
    ln -s "/opt/$pkgname/flutterapp" "$pkgdir/usr/bin/$pkgname"
}
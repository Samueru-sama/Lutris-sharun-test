#!/bin/sh

set -eu

ARCH=$(uname -m)
VERSION=$(pacman -Q lutris | awk '{print $2; exit}') # example command to get version of application here
export ARCH VERSION
export OUTPATH=./dist
export ADD_HOOKS="self-updater.bg.hook"
export UPINFO="gh-releases-zsync|${GITHUB_REPOSITORY%/*}|${GITHUB_REPOSITORY#*/}|latest|*$ARCH.AppImage.zsync"
export ICON=/usr/share/icons/hicolor/128x128/apps/net.lutris.Lutris.png
export DESKTOP=/usr/share/applications/net.lutris.Lutris.desktop
export DEPLOY_LOCALE=1
export DEPLOY_GTK=1
export GTK_DIR=gtk-3.0
export DEPLOY_OPENGL=1
export DEPLOY_VULKAN=1
export DEPLOY_SYS_PYTHON=1

# Deploy dependencies
quick-sharun \
	/usr/bin/lutris     \
	/usr/share/lutris   \
	/usr/bin/wine*      \
	/usr/lib/wine       \
	/usr/bin/msidb      \
	/usr/bin/msiexec    \
	/usr/bin/notepad    \
	/usr/bin/regedit    \
	/usr/bin/regsvr32   \
	/usr/bin/widl       \
	/usr/bin/wmc        \
	/usr/lib/libavcodec.so*

# alright here the pain starts
ln -sr ./AppDir/lib/wine/x86_64-unix/*.so* ./AppDir/bin

# this gets broken by sharun somehow
kek=.$(tr -dc 'A-Za-z0-9_=-' < /dev/urandom | head -c 10)
rm -f ./AppDir/lib/wine/x86_64-unix/wine
cp /usr/lib/wine/x86_64-unix/wine ./AppDir/lib/wine/x86_64-unix/wine
patchelf --set-interpreter /tmp/"$kek" ./AppDir/lib/wine/x86_64-unix/wine
patchelf --add-needed anylinux.so ./AppDir/shared/lib/wine/x86_64-unix/wine

cat <<EOF > ./AppDir/bin/random-linker.src.hook
#!/bin/sh
cp -f "\$APPDIR"/shared/lib/ld-linux*.so* /tmp/"$kek"
EOF
chmod +x ./AppDir/bin/*.hook

# Set the lib path to also use wine libs
echo 'LD_LIBRARY_PATH=${APPDIR}/lib:${APPDIR}/lib/pulseaudio:${APPDIR}/lib/alsa-lib:${APPDIR}/lib/wine/x86_64-unix' >> ./AppDir/.env

# lib/wine/x86_64-unix/wine will try to execute a relative ../../bin/wineserver
# which resolves to shared/bin/wineserver and it is wrong
# so we have to make AppDir/shared/lib the symlink and AppDir/lib the real directory
# that way ../../bin/wineserver resolves to the sharun hardlink
if [ -L ./AppDir/lib ]; then
	rm -f ./AppDir/lib
	mv ./AppDir/shared/lib ./AppDir
	ln -sr ./AppDir/lib ./AppDir/shared
fi

# remove wine static libs
find ./AppDir/lib/ -type f -name '*.a'
find ./AppDir/lib/ -type f -name '*.a' -delete

# Turn AppDir into AppImage
quick-sharun --make-appimage

# Test the app for 12 seconds, if the test fails due to the app
# having issues running in the CI use --simple-test instead
quick-sharun --test ./dist/*.AppImage

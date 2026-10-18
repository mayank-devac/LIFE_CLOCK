# Life Clock workflow

After changing app or widget source/configuration, run `./build.sh` before reporting completion. Mayank explicitly authorises this command to run the focused tests, build, back up and replace the local app, verify signatures, register the widget and launch Life Clock. Use the sandbox approval mechanism when system access is required.

Keep the desktop card and widget settings independent. This project uses local ad-hoc signing without App Groups or a paid Apple developer account.

macOS does not provide a supported CLI for placing widgets on the desktop. Report that manual step honestly; do not treat successful registration as proof that the widget is visible and configured.

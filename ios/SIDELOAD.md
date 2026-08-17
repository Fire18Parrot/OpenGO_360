# Getting GoControl onto your iPhone (Windows + free Apple ID)

The CI produces an **unsigned** IPA. iOS will not install it as-is — it has to be re-signed
against a certificate tied to your Apple ID and a provisioning profile listing your phone.
Sideloadly does both on Windows.

## 1. Get the IPA

Push the repo, let `.github/workflows/ios.yml` run, then on the Actions run page download
the **`GoControl-unsigned-ipa`** artifact. Unzip it — GitHub wraps artifacts in a `.zip`, so
you want the `GoControl-unsigned.ipa` inside.

If the workflow fails at **Compile for simulator**, that is expected on the first run: the
Swift has never been compiled. The log will name the file and line. Send me the errors and
I'll fix them.

## 2. Install the tooling on Windows

1. **iTunes** — get it from Apple's website, *not* the Microsoft Store. The Store build
   lacks the device drivers Sideloadly needs.
2. **Sideloadly** — <https://sideloadly.io>

Reboot after installing iTunes so the Apple Mobile Device Service starts.

## 3. Sideload

1. Plug the iPhone in via USB. Unlock it and tap **Trust**.
2. Open Sideloadly.
3. Drag `GoControl-unsigned.ipa` onto the window.
4. Enter your Apple ID. Sideloadly uses it to request a free development certificate; the
   password goes to Apple, not to Sideloadly.
   - If you have 2FA on (you should), you'll be asked for an
     [app-specific password](https://appleid.apple.com) instead of your real one.
5. Leave **Bundle ID** as `com.gocontrol.app`.
6. Click **Start**.

## 4. Trust the developer on the phone

Settings → General → VPN & Device Management → your Apple ID → **Trust**.

Until you do this the app is installed but refuses to launch.

## 5. First launch

The app starts scanning immediately and iOS will ask for Bluetooth permission — allow it, or
the scan silently finds nothing.

Wake the camera before launching. You should see "Looking for your camera", then the camera
name, then the control screen about a second after connecting.

## Caveats of the free-Apple-ID route

- **The app stops working after 7 days.** Free certificates expire. Re-run Sideloadly to
  refresh — reinstalling over the top keeps the app's data.
- **Three apps maximum** sideloaded per Apple ID at once.
- **Ten devices per week** limit on registering new UDIDs.

A paid developer account ($99/yr) raises the expiry to a year and lets CI sign the IPA
directly, so you could install from Linux with `ideviceinstaller` and skip Windows. Worth it
only if you end up iterating on this a lot.

## If it fails to install

| Symptom | Cause |
|---|---|
| "Could not find device" | iTunes came from the Microsoft Store, or you skipped the reboot |
| "Unable to install" / provisioning error | Bundle ID already used by another sideloaded app — change it in Sideloadly and in `ios/project.yml` |
| Installs, then crashes instantly on launch | Missing `NSBluetoothAlwaysUsageDescription`. It is set in `project.yml`, so this would mean the project was built some other way |
| Sits on "Bluetooth LE not supported" | You're on a Simulator, not hardware. CoreBluetooth doesn't exist in the Simulator |
| Sits on "Looking for your camera" | Camera asleep, or it isn't advertising a name starting with `"GO "` — check `BleClient.namePrefix` |

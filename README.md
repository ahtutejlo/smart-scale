# Smart Scale

An iPhone app for the Active Era BF-06 smart scale. It replaces the vendor app.

- It gets the weight and the body impedance from the scale over Bluetooth.
- It calculates the body composition: fat, muscle, water and more.
- It keeps a history for several people and finds who stood on the scale.
- It can write the weighings to Apple Health.

The app text is in Ukrainian.

## What you need

- A Mac with Xcode for iOS 18 or later. We test with Xcode 27.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen). It makes the Xcode project from `project.yml`.
- For a real scale: an iPhone with iOS 18 or later and an Apple ID. A free Apple ID is sufficient.

```bash
brew install xcodegen
```

Git does not keep the Xcode project. Run `xcodegen generate` again after each change to `project.yml`.

## Run on the simulator

The simulator has no Bluetooth, so it cannot connect to the scale. Use demo mode to see the app with sample data.

1. Get the code and make the Xcode project:

   ```bash
   git clone https://github.com/ahtutejlo/smart-scale.git
   cd smart-scale
   xcodegen generate
   open SmartScale.xcodeproj
   ```

2. In Xcode, select **Product → Scheme → Edit Scheme → Run → Arguments**.
3. Add `-demo` to **Arguments Passed On Launch**.
4. Select a simulator and click **Run**.

Demo mode works only in Debug builds. The app keeps the sample data in memory only.

## Run on your iPhone

Your signing settings go in `Config/Local.xcconfig`. Git ignores this file, so your personal values stay on your Mac.

1. In Xcode, open **Settings → Accounts** and add your Apple ID.
2. Click **Manage Certificates** and add an **Apple Development** certificate. Skip this step if you have one.
3. Get your team ID. It is the 10-character value after `OU=`:

   ```bash
   security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
   ```

4. Make your local settings file:

   ```bash
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

5. In `Config/Local.xcconfig`, set these values:
   - `DEVELOPMENT_TEAM`: your team ID.
   - `PRODUCT_BUNDLE_IDENTIFIER`: an ID that nobody else uses, for example `com.yourname.smartscale`.
6. On the iPhone, turn on **Settings → Privacy & Security → Developer Mode**. The iPhone restarts.
7. Connect the iPhone to the Mac with a cable. Select the iPhone in Xcode and click **Run**.
8. With a free Apple ID, iOS blocks the first launch. Go to **Settings → General → VPN & Device Management** and trust your developer certificate.
9. Open the app again. Allow Bluetooth and Apple Health.

The scale connects to only one app at a time. If the Active Era app is open on a phone, close it or turn off Bluetooth on that phone.

## Reinstall the app automatically (free Apple ID)

With a free Apple ID, the app signature is valid for 7 days only. After that, the app does not open. `scripts/refresh-iphone.sh` builds the app again and installs it when less than 3 days remain.

1. Find the ID of your iPhone. It is in the **Identifier** column:

   ```bash
   xcrun devicectl list devices
   ```

2. Set `IPHONE_UDID` in `Config/Local.xcconfig` to this ID.
3. Keep the iPhone and the Mac on the same Wi-Fi network.
4. Keep your Apple ID in Xcode **Settings → Accounts**.
5. Install the background job. It runs the script every 4 hours:

   ```bash
   scripts/install-refresh-agent.sh
   ```

The script shows a macOS notification when it reinstalls the app or when it fails. The log is in `~/Library/Logs/smartscale-refresh.log`. To reinstall now, run `scripts/refresh-iphone.sh --force`.

## Tests

The tests use real Bluetooth packets from the scale. They check the packet decoder and the body composition formulas.

```bash
swift test --package-path ScaleKit
```

## Read raw data from the scale (optional)

`scripts/probe.sh` connects the Mac to the scale and shows the raw Bluetooth packets. It saves each weighing to `captures/`.

1. Turn off Bluetooth on your phone, so the scale is free for the Mac.
2. Run the probe and stand on the scale:

   ```bash
   scripts/probe.sh --height 180 --age 30 --sex male --weight 80
   ```

The probe uses the height, age, sex and weight to calculate the body composition. On the first run, macOS asks for Bluetooth access. To calculate a saved weighing again, use `--replay captures/<file>.jsonl`.

## App icon

The source is `design/AppIcon.svg`. To make the PNG again:

```bash
brew install librsvg imagemagick
scripts/make-icon.sh
```

## Credits

The Bluetooth protocol and the body composition formulas come from [openScale](https://github.com/oliexdev/openScale).

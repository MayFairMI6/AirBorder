# Build and Test AirBorder

AirBorder can be built from this repository in Xcode. An Apple Developer Program membership is not required to run it in Simulator or to install it on your own iPhone for personal testing.

## What you need

- A Mac running a current version of Xcode with iOS 18 or later support.
- Git and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- An Apple Account signed in to Xcode for iPhone testing.

## Get the project

```bash
git clone https://github.com/MayFairMI6/AirBorder.git
cd AirBorder
./Scripts/generate.sh
```

Open `AirBorder.xcodeproj` in Xcode after generating it.

## Run in Simulator

1. In Xcode, choose the **AirBorder** scheme.
2. Choose an iPhone simulator, such as **iPhone 17 Pro**.
3. Press Run (`⌘R`).
4. To run the test suite, press `⌘U`.

You can also run the project checks from Terminal:

```bash
./Scripts/build.sh
./Scripts/test.sh
```

## Run on your iPhone

1. Connect your iPhone to your Mac and unlock it.
2. In Xcode, open **Settings → Apple Accounts** and sign in with your Apple Account.
3. Select the **AirBorder** target, open **Signing & Capabilities**, and choose your **Personal Team**.
4. Keep **Automatically manage signing** enabled. If Xcode asks for a unique bundle identifier, change `com.example.AirportXRCompanion` to one you control, such as `com.yourname.AirBorder`.
5. Select your iPhone as the run destination and press Run (`⌘R`).
6. If prompted on the phone, enable Developer Mode and trust the development certificate.

The personal-team route is for installing and testing the app on your own devices. It does not upload the app to TestFlight or the App Store. Apple documents the personal-team setup and its renewal limits in its [developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account) and [physical-device testing guide](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

## Demo ticket

For the included proof-of-concept transfer flow, import the sample ticket at:

`AirportXRCompanionTests/Fixtures/sample-self-transfer-ticket.txt`

Its route is BKK → HND → NRT → LAX. The app reads the airport change and bag instruction, then shows collection at HND, the transfer to NRT, and recheck for LAX.

## Device features to check

- Import a ticket in **Flights** and confirm the route and baggage plan.
- Open **AR Guide** for terminal guidance and the city transfer map.
- Use **Navigate in Apple Maps** from the city transfer guide.
- Test camera and AR features on an iPhone; these features are not fully reproduced in Simulator.

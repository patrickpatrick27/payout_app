# 💰 Pay Tracker

**Pay Tracker** is a robust, cloud-synced payroll assistant built with **Flutter**. It is designed for employees who need more than just a simple timer—providing a custom-built calculation engine that handles strict rounding rules, automatic break deductions, and real-time overtime/late tracking.

With **Google Drive integration**, your data stays private and stays with you, across any device.

---

## ✨ Key Features

### ☁️ Cloud Sync & Privacy
* **Google Drive Integration**: Securely backup and sync your shift data across devices using your private Google Drive storage.
* **Privacy First**: Data is stored in your personal cloud; no third-party servers ever see your financial information.
* **Offline-First**: Log shifts without internet; the app caches data locally and syncs when you're back online.

### ⚙️ Precision Calculation Engine
The app automates complex payroll rules to eliminate manual errors:
1. **Smart Time Rounding**: 
    * **Time In**: Snaps forward to the nearest 30-min mark (e.g., 8:05 AM becomes 8:30 AM).
    * **Time Out**: Snaps backward to the nearest 30-min mark (e.g., 5:25 PM becomes 5:00 PM).
2. **Automated Deductions**: 
    * **Lunch Break**: Automatic 1-hour deduction if the shift spans the 12:00 PM – 1:00 PM window.
3. **Late & OT Logic**: 
    * **Late Tracking**: Calculates "Late" minutes if arriving after the set start time.
    * **Overtime (OT)**: Automatic **1.25x multiplier** for any hours worked past your global Shift End.

### 🎨 Modern User Experience
* **Dark Mode**: High-contrast dark theme for easy viewing during late-night shifts.
* **Global Configuration**: Set your Base Pay, Shift Start, and Shift End once, and the app applies them to all calculations.
* **Data Management**: Instantly export reports to your clipboard or wipe local data for a fresh start.

---

## 📱 Tech Stack

* **Framework**: [Flutter](https://flutter.dev/) (Dart)
* **Cloud Backend**: Google Drive API (`googleapis` & `google_sign_in`)
* **Persistence**: `shared_preferences` (JSON-based local caching)
* **Formatting**: `intl` (Currency and Date localization)
* **Utilities**: `uuid` (Unique ID generation)

---

## 🚀 Getting Started

### 1. Prerequisites
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.10.0 or higher)
* A Google Cloud Project (for Drive Sync functionality)

### 2. Installation
```bash
# Clone the repository
git clone [https://github.com/patrickpatrick27/payout_app.git](https://github.com/patrickpatrick27/payout_app.git)

# Navigate to directory
cd payout_app

# Install dependencies
flutter pub get

# Run the app
flutter run

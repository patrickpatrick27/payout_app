# 💰 Pay Tracker

**Pay Tracker** is a robust, offline-first mobile application built with **Flutter** designed to help employees track their work shifts, calculate real-time salary estimates, and manage overtime hours with precision.

It features a custom-built payroll engine that handles time rounding, automatic break deductions, and differential overtime rates.

---

## ✨ Key Features

### 📅 Advanced Shift Management
* **Pay Period Tracking**: Create and manage distinct pay periods (e.g., Nov 1 - Nov 15).
* **Smart Sorting**: Sort periods by **Newest**, **Oldest**, or **Recently Edited**.
* **Manual Pay Injection**: Support for flat-rate payments (bonuses, adjustments) that bypass hourly calculations.
* **Shift Editing**: Modify existing shifts or retroactive entries with a custom date picker.

### ⚙️ Global Settings & Customization
* **Custom Schedule**: Define your specific **Shift Start** (e.g., 8:00 AM) and **Shift End** (e.g., 5:00 PM) times.
* **Theme Support**: Toggle between **Light Mode** and **Dark Mode**.
* **Time Format**: Full support for **12-hour (AM/PM)** or **24-hour** clock formats.
* **Data Management**: Options to **Export Data** (copy report to clipboard) or **Wipe Data** locally.

### 🧠 The Calculation Engine (How it Works)
The app uses a specific set of logic to ensure payroll accuracy:

1.  **Regular vs. Overtime**:
    * **Regular Hours**: Time worked from *Shift Start* to *Shift End*.
    * **Overtime Hours**: Any time worked *after* the global Shift End time.
    * **Multiplier**: Overtime is automatically calculated at **1.25x** the hourly rate.
2.  **Lunch Break Logic**:
    * The app automatically detects if a shift spans across **12:00 PM – 1:00 PM**.
    * If covered, **1 hour is automatically deducted** from the total duration.
3.  **Smart Time Rounding**:
    * **Time In**: Rounds forward to the nearest 30-minute mark (e.g., 8:10 AM becomes 8:30 AM).
    * **Time Out**: Rounds backward to the nearest 30-minute mark.
    * *Note: Arrivals before the Shift Start time are snapped to the Shift Start time (no early overtime).*

---

## 📱 Tech Stack

* **Framework**: [Flutter](https://flutter.dev/) & Dart
* **Architecture**: MVC Pattern with native `setState` management.
* **Persistence**: [`shared_preferences`](https://pub.dev/packages/shared_preferences) (Local JSON storage).
* **Utilities**:
    * [`intl`](https://pub.dev/packages/intl) for Date/Currency formatting.
    * [`uuid`](https://pub.dev/packages/uuid) for unique ID generation.

---

## 🚀 Installation & Setup

1.  **Clone the repository**
    ```bash
    git clone [https://github.com/patrickpatrick27/payout_app.git](https://github.com/patrickpatrick27/payout_app.git)
    ```

2.  **Navigate to the project directory**
    ```bash
    cd payout_app
    ```

3.  **Install dependencies**
    ```bash
    flutter pub get
    ```

4.  **Run the application**
    ```bash
    flutter run
    ```

---

## 👤 Author

**Dave Patrick I. Bulaso**
* GitHub: [@patrickpatrick27](https://github.com/patrickpatrick27)

---

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

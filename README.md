# 🚍 STM Bus Scheduler (iOS)

iOS application for STM Montreal bus scheduling and route optimization, delivering real-time transit insights and efficient route planning.

---

## ✨ Features

- 📍 **Bus Route Visualization** – View routes and stops clearly on map/list  
- ⏱️ **Real-Time Insights** – Track schedules and estimated timings  
- ⚡ **Route Optimization** – Improve travel efficiency with smart routing logic  
- 🧭 **Trip Planning** – Quickly determine optimal routes between locations  
- 📱 **Native iOS Experience** – Smooth and responsive UI  

---

## 🏗️ Architecture

The application follows a clean separation of concerns:

- **UI Layer** – SwiftUI / UIKit views  
- **Business Logic** – Scheduling + routing logic  
- **Data Layer** – Transit data handling (API / local storage)  

This structure keeps the app scalable, testable, and maintainable.

---

## 🛠️ Tech Stack

- **Language:** Swift  
- **Frameworks:** SwiftUI / UIKit  
- **Data Handling:** JSON / REST APIs (STM or simulated data)  
- **Architecture:** MVVM (or MVC — adjust based on your implementation)  

---

## ⚙️ How It Works

1. Loads transit data (routes, stops, schedules)  
2. Processes scheduling constraints and timing  
3. Applies routing / optimization logic  
4. Displays optimal routes and timing insights to the user  

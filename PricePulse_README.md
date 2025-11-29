
# 📉 PricePulse - Price Tracking App

PricePulse is a student-level Flutter app that helps users track product prices from popular Indian e-commerce sites like Amazon and Flipkart. It notifies users of price changes by scraping the product page at regular intervals.

---

## 🌐 Live Demo
🚀 Backend (Render): [https://pricepulse-backend.onrender.com](https://pricepulse-backend.onrender.com)  
📱 Frontend: Flutter Android/Web App (to be deployed)

---

## 📂 Project Structure

```
price_pulse/
├── backend/        # Node.js + Express server
├── frontend/       # Flutter app
└── README.md
```

---

## 🔧 Technologies Used

### Backend
- Node.js
- Express.js
- Cheerio (for web scraping)
- Axios (for HTTP requests)
- Firebase Admin SDK (Firestore DB)
- Render (free backend hosting)
- Render Cron Jobs (for scheduled scraping)

### Frontend
- Flutter (Dart)
- HTTP package
- Provider / State Management (if used)
- Flutter Web Compatible
- Firebase Hosting (if web deployed)

---

## 📡 Backend Details (`/backend`)

### Features
- Scrapes product price from Amazon & Flipkart using Cheerio
- Format for Storing product info in Firestore:
  ```json
  {
    "url": "https://amazon.in/...",
    "price": "₹1,999",
    "lastChecked": "2025-07-22T10:00:00Z"
  }
  ```
- Exposed API Endpoints:
  - `GET /` → Health check
  - `GET /scrape?url=` → Scrape a product and return its price
  - `POST /track-product` → Add and store product URL after scraping
  - `GET /get-products` → Return all stored products
  - `GET /scrape-all` → Refresh all product prices (used in cron)

### Folder Includes
- `index.js` – main server logic
- `firebaseConfig.js` – Firebase admin setup
- Deployed on Render with public base URL

### Scheduled Task (Render Cron Job)
- Route: `GET /scrape-all`
- Frequency: e.g. every 12 or 24 hours
- Render Dashboard → Cron → New Job → GET to backend endpoint

---

## 📱 Frontend Details (`/frontend`)

### Features
- Dark-themed Flutter UI with Glassmorphism designs
- Add Product Screen:
  - Input URL
  - "Track" button → Calls `POST /track-product`
- Home Screen:
  - Displays all products with:
    - Shortened product URL
    - Latest price
    - Last checked timestamp (formatted)
  - Pull-to-refresh or refresh button
- Flutter Web & Android support

### Folder Structure
```
lib/
├── main.dart
├── screens/
│   ├── home_screen.dart
│   └── add_product_screen.dart
├── services/
│   └── api_service.dart
└── widgets/
    └── product_card.dart
```

### Planned Improvements
- Push notifications using Firebase Messaging
- User auth for personal product tracking
- Sort by price or time

---

## ⚙️ How It Works

1. User enters a product URL.
2. Backend scrapes price using `axios` + `cheerio`.
3. Data is saved to Firestore.
4. On home screen, latest data is shown.
5. Cron job regularly updates all tracked products.

---

## 🛠 Setup Instructions

### Backend
```bash
cd backend
npm install
node index.js

```

### Frontend
```bash
cd frontend
flutter pub get
flutter run
```

---

## 🧠 Contributors

- 👨‍💻 Developer: D Muthunilavan (Barath)
- 🔗 [GitHub](https://github.com/Muthunilavan-D)
- 🔗 [LinkedIn](https://www.linkedin.com/in/d-mn-92a1b7341)
---

## 📌 Notes

- Currently supports only public product pages.
- Avoid logging too many product URLs on free Firebase tier.
- Ensure backend server remains active (use cron pings or dummy requests).

---

## 📥 API Reference (Summary)

| Method | Endpoint         | Description                       |
|--------|------------------|-----------------------------------|
| GET    | `/`              | Health check                      |
| GET    | `/scrape?url=`   | Scrape price for single product   |
| POST   | `/track-product` | Add new product to Firestore      |
| GET    | `/get-products`  | Fetch all tracked products        |
| GET    | `/scrape-all`    | Re-scrape all products (cron)     |

---

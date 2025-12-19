# Backend Deployment Guide

This guide will help you deploy the PricePulse backend to **Render** (recommended) or **Railway**.

## 🎯 Recommended: Render

Render is the best option because:
- ✅ Free tier available
- ✅ Supports long-running Node.js processes
- ✅ Easy environment variable management
- ✅ Automatic HTTPS
- ✅ No timeout limits for web services
- ✅ Simple deployment from GitHub

---

## 📋 Pre-Deployment Checklist

### 1. Update package.json

Add a start script to your `package.json`:

```json
{
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  }
}
```

### 2. Create .gitignore

Create a `.gitignore` file in the `backend` folder:

```
node_modules/
serviceAccountKey.json
.env
*.log
.DS_Store
```

### 3. Secure serviceAccountKey.json

**IMPORTANT**: Never commit `serviceAccountKey.json` to GitHub. Instead, we'll use environment variables.

---

## 🚀 Deployment on Render

### Step 1: Prepare Your Code

1. **Update index.js to use environment variables for Firebase:**

   Replace the Firebase initialization section (around line 12-16) with:

   ```javascript
   // Initialize Firebase Admin
   let serviceAccount;
   if (process.env.FIREBASE_SERVICE_ACCOUNT) {
     // Use environment variable (for production)
     serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
   } else {
     // Use local file (for development)
     serviceAccount = require('./serviceAccountKey.json');
   }
   
   admin.initializeApp({
     credential: admin.credential.cert(serviceAccount)
   });
   ```

2. **Commit your changes to GitHub** (make sure `serviceAccountKey.json` is in `.gitignore`)

### Step 2: Create Render Account

1. Go to [render.com](https://render.com)
2. Sign up with GitHub
3. Connect your GitHub account

### Step 3: Create New Web Service

1. Click **"New +"** → **"Web Service"**
2. Connect your repository
3. Select the repository containing your backend
4. Configure the service:
   - **Name**: `price-pulse-backend` (or any name you prefer)
   - **Region**: Choose closest to your users
   - **Branch**: `main` (or your default branch)
   - **Root Directory**: `backend` (important!)
   - **Runtime**: `Node`
   - **Build Command**: `npm install`
   - **Start Command**: `npm start`
   - **Instance Type**: Free (or paid for better performance)

### Step 4: Set Environment Variables

In Render dashboard, go to **Environment** tab and add:

1. **FIREBASE_SERVICE_ACCOUNT**
   - Value: Copy the entire contents of your `serviceAccountKey.json` file
   - Format: Paste as a single-line JSON string (remove all line breaks)

2. **PORT** (optional - Render sets this automatically)
   - Value: `10000` (or leave default)

### Step 5: Deploy

1. Click **"Create Web Service"**
2. Render will automatically:
   - Install dependencies
   - Build your app
   - Start the server
3. Wait for deployment to complete (usually 2-5 minutes)

### Step 6: Get Your Backend URL

After deployment, you'll get a URL like:
```
https://price-pulse-backend.onrender.com
```

### Step 7: Update Flutter App

Update `api_service.dart` to use the new backend URL:

```dart
// Replace this:
static const String PHYSICAL_DEVICE_URL = 'http://192.168.31.248:5000';

// With your Render URL:
static const String PHYSICAL_DEVICE_URL = 'https://price-pulse-backend.onrender.com';
```

---

## 🚂 Alternative: Railway

Railway is also a good option with similar features.

### Step 1: Create Railway Account

1. Go to [railway.app](https://railway.app)
2. Sign up with GitHub

### Step 2: Create New Project

1. Click **"New Project"**
2. Select **"Deploy from GitHub repo"**
3. Choose your repository
4. Select the `backend` folder

### Step 3: Configure

1. Railway auto-detects Node.js
2. Add environment variable:
   - **Key**: `FIREBASE_SERVICE_ACCOUNT`
   - **Value**: Your serviceAccountKey.json content (as JSON string)

### Step 4: Deploy

Railway will automatically deploy. Get your URL from the dashboard.

---

## 🔧 Updating Backend Code

### Option 1: Automatic (Recommended)

Both Render and Railway automatically redeploy when you push to GitHub:
1. Make changes to your code
2. Commit and push to GitHub
3. Deployment happens automatically

### Option 2: Manual

1. Go to your service dashboard
2. Click **"Manual Deploy"** → **"Deploy latest commit"**

---

## 🔐 Security Best Practices

1. ✅ Never commit `serviceAccountKey.json` to GitHub
2. ✅ Use environment variables for sensitive data
3. ✅ Keep your API keys secret
4. ✅ Use HTTPS (automatic on Render/Railway)
5. ✅ Regularly rotate service account keys

---

## 🐛 Troubleshooting

### Issue: "Cannot find module 'serviceAccountKey.json'"

**Solution**: Make sure `FIREBASE_SERVICE_ACCOUNT` environment variable is set correctly.

### Issue: "Port already in use"

**Solution**: Use `process.env.PORT` (Render/Railway sets this automatically).

### Issue: Deployment fails

**Solution**: 
- Check build logs in Render/Railway dashboard
- Ensure `package.json` has a `start` script
- Verify all dependencies are in `package.json`

### Issue: Backend times out

**Solution**: 
- Render free tier has a 15-minute timeout if inactive
- Consider upgrading to paid plan for always-on service
- Or use a cron job to ping your backend every 10 minutes

---

## 📝 Setting Up Cron Job for Background Checks

You can use [cron-job.org](https://cron-job.org) to ping your `/background-check` endpoint:

1. Create account on cron-job.org
2. Create new cron job:
   - **URL**: `https://your-backend-url.onrender.com/background-check?apiKey=YOUR_API_KEY`
   - **Schedule**: Every hour (or as needed)
   - **Request Method**: GET

This will keep your Render service awake and check prices automatically.

---

## 💰 Cost Comparison

| Platform | Free Tier | Paid Plans |
|----------|----------|------------|
| **Render** | ✅ Yes (with limitations) | $7/month+ |
| **Railway** | ✅ $5 credit/month | Pay as you go |
| **Vercel** | ❌ Not suitable (serverless) | - |
| **Heroku** | ❌ No free tier | $7/month+ |

---

## ✅ Post-Deployment Checklist

- [ ] Backend URL is accessible
- [ ] Environment variables are set
- [ ] Flutter app updated with new URL
- [ ] Test all API endpoints
- [ ] Set up cron job for background checks
- [ ] Monitor logs for errors

---

## 📞 Need Help?

Check the deployment logs in Render/Railway dashboard for detailed error messages.


# PricePulse Deployment Guide

## Current Situation Analysis

### Why cron-job.org Shows 404 Errors

1. **Ngrok is Temporary:**
   - Ngrok URLs are temporary and change every time you restart ngrok
   - When your computer sleeps or restarts, ngrok stops
   - The URL `flawless-waylon-unobsessed.ngrok-free.dev` becomes invalid
   - cron-job.org tries to call this URL, but it doesn't exist anymore → 404 error

2. **Backend Console Shows Success:**
   - The success messages you see are from when ngrok WAS active
   - Or from manual testing when you accessed the endpoint directly
   - But cron-job.org can't reach it when ngrok is down

3. **System Sleep Issue:**
   - Yes! When your computer sleeps, ngrok stops
   - The ngrok tunnel closes
   - cron-job.org can't reach your backend → 404 errors

## Permanent Solutions for Production

### Option 1: Deploy Backend to Cloud Platform (RECOMMENDED)

#### A. Railway (Easiest - Free Tier Available)
1. **Sign up:** https://railway.app
2. **Deploy:**
   - Connect your GitHub repo
   - Add new project → Deploy from GitHub
   - Select your backend folder
   - Railway auto-detects Node.js and deploys
3. **Get Permanent URL:**
   - Railway gives you a permanent URL like: `your-app.railway.app`
   - This URL never changes
4. **Update cron-job.org:**
   - Use: `https://your-app.railway.app/background-check?apiKey=YOUR_API_KEY`
   - Works 24/7, even when your computer is off

#### B. Render (Free Tier Available)
1. **Sign up:** https://render.com
2. **Deploy:**
   - New → Web Service
   - Connect GitHub repo
   - Root Directory: `backend`
   - Build Command: `npm install`
   - Start Command: `node index.js`
3. **Get Permanent URL:**
   - Render gives: `your-app.onrender.com`
   - Update cron-job.org with this URL

#### C. Heroku (Paid, but reliable)
1. **Sign up:** https://heroku.com
2. **Deploy:**
   ```bash
   cd backend
   heroku create your-app-name
   git push heroku main
   ```
3. **Get URL:** `https://your-app-name.herokuapp.com`

#### D. AWS/Google Cloud/Azure
- More complex setup
- Better for large-scale applications
- Requires more configuration

### Option 2: Use Cloud Functions (Serverless)

#### AWS Lambda + EventBridge
- Create Lambda function with your background check code
- Use EventBridge (CloudWatch Events) as cron trigger
- No server to manage
- Pay only for execution time

#### Google Cloud Functions + Cloud Scheduler
- Similar to AWS Lambda
- Cloud Scheduler triggers the function
- Good for periodic tasks

### Option 3: VPS/Dedicated Server
- Rent a VPS (DigitalOcean, Linode, etc.)
- Install Node.js
- Use PM2 to keep server running
- Set up reverse proxy (nginx)
- More control, but requires server management

## Recommended Solution: Railway

### Why Railway?
- ✅ Free tier available
- ✅ Easy deployment (GitHub integration)
- ✅ Permanent URLs
- ✅ Auto-deploys on git push
- ✅ Built-in monitoring
- ✅ No credit card required for free tier

### Step-by-Step Railway Deployment

1. **Prepare Backend:**
   ```json
   // backend/package.json - ensure you have:
   {
     "scripts": {
       "start": "node index.js"
     }
   }
   ```

2. **Create Railway Account:**
   - Go to https://railway.app
   - Sign up with GitHub

3. **Deploy:**
   - New Project → Deploy from GitHub
   - Select your repository
   - Select `backend` folder
   - Railway auto-detects and deploys

4. **Get URL:**
   - Go to Settings → Domains
   - Railway provides: `your-app.up.railway.app`
   - Or add custom domain

5. **Set Environment Variables:**
   - In Railway dashboard → Variables
   - Add your Firebase credentials if needed
   - Add PORT (Railway sets this automatically)

6. **Update cron-job.org:**
   - New URL: `https://your-app.up.railway.app/background-check?apiKey=YOUR_API_KEY`
   - Test it first manually
   - Update cron job with new URL

## Why Ngrok Fails

### Problems with Ngrok:
1. ❌ **Temporary URLs** - Change on every restart
2. ❌ **Stops when computer sleeps** - No 24/7 availability
3. ❌ **Free tier limitations** - Connection limits, timeouts
4. ❌ **Not for production** - Designed for development/testing

### When Ngrok Works:
- ✅ Development/testing
- ✅ Quick demos
- ✅ Temporary access
- ✅ When your computer is always on

## Migration Checklist

1. [ ] Choose deployment platform (Railway recommended)
2. [ ] Deploy backend to cloud
3. [ ] Test the permanent URL manually
4. [ ] Update cron-job.org with new URL
5. [ ] Test cron job execution
6. [ ] Monitor for 24 hours to ensure it works
7. [ ] Update Flutter app API base URL if needed

## Testing Your Deployment

### Manual Test:
```bash
curl "https://your-app.up.railway.app/background-check?apiKey=YOUR_API_KEY"
```

### Expected Response:
```json
{
  "message": "Background check started",
  "checked": 9,
  "status": "processing",
  "startedAt": "2025-11-30T17:26:40.753Z"
}
```

## Cost Comparison

| Solution | Cost | Reliability | Setup Difficulty |
|----------|------|-------------|------------------|
| Ngrok | Free | ❌ Low | ✅ Easy |
| Railway | Free tier | ✅ High | ✅ Easy |
| Render | Free tier | ✅ High | ✅ Easy |
| Heroku | $7/month | ✅ High | ✅ Medium |
| AWS Lambda | Pay per use | ✅ Very High | ❌ Complex |
| VPS | $5-20/month | ✅ High | ❌ Complex |

## Next Steps

1. **Immediate:** Deploy to Railway (takes ~10 minutes)
2. **Update:** cron-job.org URL
3. **Test:** Verify cron job works
4. **Monitor:** Check logs for 24 hours
5. **Done:** Your app runs 24/7 automatically!

## Troubleshooting

### cron-job.org Still Shows 404:
- Check if Railway deployment is active
- Verify the URL in Railway dashboard
- Test URL manually in browser
- Check Railway logs for errors

### Background Check Not Running:
- Verify API key is correct
- Check Railway logs
- Ensure Firestore connection works
- Verify cron-job.org is calling correct URL

### High Costs:
- Railway free tier: 500 hours/month
- Render free tier: 750 hours/month
- Monitor usage in dashboard


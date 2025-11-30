# Complete Guide: Setting Up Cron Job at cron-job.org

## ✅ Prerequisites
- ngrok is running: `https://flawless-waylon-unobsessed.ngrok-free.dev -> http://localhost:5000`
- Backend server is running on port 5000
- You have a cron-job.org account (muthunilavand@gmail.com)

---

## 📋 Step-by-Step Instructions

### Step 1: Log in to cron-job.org

1. Go to: **https://cron-job.org**
2. Click **"Login"** (top right)
3. Enter your email: `muthunilavand@gmail.com`
4. Enter your password
5. Click **"Login"**

---

### Step 2: Create New Cron Job

1. After logging in, you'll see your dashboard
2. Click the **"Create cronjob"** button (usually a green button or "+" icon)
3. You'll see a form with multiple fields

---

### Step 3: Fill in the Cron Job Details

#### **Title** (Required)
```
PricePulse Background Check
```
- This is just a name for your reference
- You can use any name you like

#### **URL** (Required)
```
https://flawless-waylon-unobsessed.ngrok-free.dev/background-check?apiKey=2IcwKctWD2JzIqbPxHhcDN68fxDcxXpCLFLdUQKYbf0=
```
- Copy this EXACT URL (including the API key)
- Make sure there are no extra spaces

#### **Request Method** (Required)
- Select: **`GET`** from the dropdown
- This should be a dropdown menu

#### **Schedule** (Required)

You have two options:

**Option A: Use Cron Expression**
- Enter: `0 */2 * * *`
  - This means: Every 2 hours
- Other options:
  - Every 4 hours: `0 */4 * * *`
  - Every 6 hours: `0 */6 * * *`
  - Every 12 hours: `0 */12 * * *`
  - Once daily at midnight: `0 0 * * *`

**Option B: Use Visual Scheduler** (if available)
- Click on the calendar/time picker
- Select "Every 2 hours" or your preferred interval

#### **Headers** (Important!)

This is crucial to bypass ngrok's warning page:

1. Look for the **"Headers"** section
2. You should see "No custom headers defined" or an "Add Header" button
3. Click **"Add Header"** or the **"+"** button
4. In the header fields, enter:
   - **Header Name:** `ngrok-skip-browser-warning`
   - **Header Value:** `true`
5. Click "Add" or "Save" to add the header

**Why this is needed:** Free ngrok shows a warning page that blocks automated requests. This header bypasses it.

#### **Timeout** (Optional but Recommended)
- Set to: **`60`** seconds
- This gives enough time for the background check to complete
- Default is usually 30 seconds, but increase it to be safe

#### **Time Zone** (Optional)
- Leave as **UTC** (default)
- Or select your timezone if you want schedules in local time

#### **Treat redirects with HTTP 3xx status code as success** (Optional)
- Leave this **UNCHECKED** (unchecked by default)

#### **Request Body** (Not Needed)
- Leave this **EMPTY** (we're using GET method)

#### **HTTP Authentication** (Not Needed)
- Leave **Username** and **Password** fields **EMPTY**

---

### Step 4: Save the Cron Job

1. Review all your settings
2. Click the **"Create Cronjob"** or **"Save"** button (usually at the bottom)
3. You should see a success message

---

### Step 5: Test the Cron Job

1. After creating, you'll see your cron job in the list
2. Find your cron job: **"PricePulse Background Check"**
3. Click the **"Test"** button (usually a play icon or "Test" link)
4. Wait a few seconds
5. You should see a response like:
   ```json
   {
     "message": "Background check completed",
     "checked": 6,
     "updated": 6,
     "failed": 0,
     "duration": 42341,
     "errors": []
   }
   ```

**If you see this response, it's working! ✅**

---

### Step 6: Verify It's Scheduled

1. In your cron job list, you should see:
   - Status: **Active** or **Enabled**
   - Next execution time
   - Last execution time (will show after first run)

2. The cron job will now run automatically at your scheduled intervals!

---

## 🔍 Troubleshooting

### Problem: "Connection Failed" or "Timeout"

**Solutions:**
1. **Check if ngrok is still running** - Make sure ngrok terminal is open
2. **Check if backend is running** - Make sure `node index.js` is running
3. **Check the URL** - Make sure it matches exactly (no typos)
4. **Increase timeout** - Try setting timeout to 90 seconds

### Problem: Getting HTML instead of JSON (ngrok warning page)

**Solution:**
- Make sure you added the header: `ngrok-skip-browser-warning: true`
- If header option is not available, you may need to:
  - Upgrade ngrok to paid plan (static domain, no warning)
  - Or deploy backend to cloud service

### Problem: "Unauthorized" Error

**Solution:**
- Check the API key in the URL - it must be exactly: `2IcwKctWD2JzIqbPxHhcDN68fxDcxXpCLFLdUQKYbf0=`
- Make sure there are no extra spaces or characters

### Problem: ngrok URL Changed

**Solution:**
- If you restart ngrok, you'll get a new URL
- Update the URL in cron-job.org:
  1. Click "Edit" on your cron job
  2. Update the URL field with the new ngrok URL
  3. Save

---

## 📊 Monitoring Your Cron Job

### View Execution History

1. Go to your cron job dashboard
2. Click on your cron job name
3. You should see:
   - **Execution history** - List of past runs
   - **Status** - Success/Failed
   - **Response** - What was returned
   - **Duration** - How long it took

### Check Logs

- **Backend logs:** Check your `node index.js` terminal for:
  ```
  🔄 Starting background price check...
  📦 Found 6 product(s) to check
  ✅ Updated: Product Name - ₹Price
  ```

---

## ⚙️ Recommended Settings Summary

| Setting | Value |
|---------|-------|
| **Title** | PricePulse Background Check |
| **URL** | `https://flawless-waylon-unobsessed.ngrok-free.dev/background-check?apiKey=2IcwKctWD2JzIqbPxHhcDN68fxDcxXpCLFLdUQKYbf0=` |
| **Method** | GET |
| **Schedule** | `0 */2 * * *` (Every 2 hours) |
| **Header** | `ngrok-skip-browser-warning: true` |
| **Timeout** | 60 seconds |
| **Time Zone** | UTC |

---

## 🎯 What Happens Next

Once set up, your cron job will:

1. ✅ Run automatically every 2 hours (or your chosen interval)
2. ✅ Check all products in your database
3. ✅ Update prices and maintain price history
4. ✅ Send FCM push notifications for price drops
5. ✅ Send special notifications when thresholds are reached
6. ✅ Work even when your app is closed

---

## 💡 Pro Tips

1. **Start with frequent checks** (every 2 hours) to test, then reduce frequency if needed
2. **Monitor the first few runs** to ensure everything works
3. **Check execution history** regularly to catch any issues
4. **For production:** Consider deploying to cloud (Railway, Render) for permanent URL
5. **Keep ngrok running:** The cron job only works when ngrok is active

---

## ✅ Checklist

Before you finish, make sure:

- [ ] ngrok is running and forwarding to port 5000
- [ ] Backend server is running (`node index.js`)
- [ ] Cron job is created with correct URL
- [ ] Header `ngrok-skip-browser-warning: true` is added
- [ ] Test button shows successful JSON response
- [ ] Cron job status shows "Active" or "Enabled"
- [ ] Next execution time is displayed

**If all checked, you're all set! 🎉**


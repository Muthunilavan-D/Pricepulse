# Deploy Firestore Security Rules

## Issue Fixed
The `userProfiles` collection was missing from Firestore security rules, causing permission-denied errors when updating profile information.

## Solution Applied
Added security rules for the `userProfiles` collection in `firestore.rules`:
- Users can read/write their own profile document
- Users can create their own profile document
- All operations require authentication

## How to Deploy

### Option 1: Using Firebase CLI (Recommended)
```bash
firebase deploy --only firestore:rules
```

### Option 2: Using Firebase Console
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: `pricepulse-e7f39`
3. Navigate to **Firestore Database** → **Rules** tab
4. Copy the updated rules from `firestore.rules`
5. Paste them into the rules editor
6. Click **Publish**

### Option 3: Using FlutterFire CLI
```bash
flutterfire configure
# Then deploy rules
firebase deploy --only firestore:rules
```

## Updated Rules
The rules now include:
```javascript
// User Profiles collection - users can read/write their own profile
match /userProfiles/{userId} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
  allow create: if request.auth != null && request.auth.uid == userId;
}
```

## Verification
After deploying:
1. Try updating your profile in the app
2. The permission error should be resolved
3. Profile updates should work correctly

---

**Note:** The rules file has been updated locally. You must deploy it to Firebase for the changes to take effect.


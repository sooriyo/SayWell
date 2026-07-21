# SayWell App Store Privacy Labels Configuration

**When submitting to App Store, fill out the "Data & Privacy" form in App Store Connect:**

## Step 1: Data Collection Questions

### ✅ Does your app collect, use, or share user data?
- **Answer:** YES

### ✅ Data types collected

Check the following:

#### 1. **Device ID** ✓
- Type: Identifier (UUID)
- Linked to user: **NO**
- Used for tracking: **NO**
- Purpose: App Functionality (rate limiting)

#### 2. **User Input (Text)** ✓
- Type: Other User Input (text for translation)
- Linked to user: **NO**
- Used for tracking: **NO**
- Purpose: App Functionality (translation service)

#### ✗ Do NOT check
- Name / Email
- Photo / Video
- Audio
- Location data
- Health / Fitness
- Financial info
- Browsing history
- Any advertising data

## Step 2: Data Linked to User
- **Answer:** NO for all types

## Step 3: Data Tracking
- **App Tracking Transparency:** NO
- **SKAdNetwork:** NO

## Step 4: Third-Party Sharing
- **Answer:** YES - Google Gemini API for translation

## Submission Checklist
- [ ] Privacy Manifest added to SayWell target
- [ ] Privacy Manifest added to SayWellKeyboard target  
- [ ] Privacy Disclosure view integrated
- [ ] App Store labels filled out
- [ ] NO App Tracking Transparency calls
- [ ] Full Access used ONLY for network

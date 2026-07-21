# SayWell iOS Privacy Manifest

**For App Store Submission (iOS 17+)**

## Overview

iOS 17+ requires apps to declare privacy practices via a Privacy Manifest. This document guides the configuration.

## Privacy Manifest File

**Location:** `ios/SayWell/PrivacyInfo.xcprivacy`

This is an XML property list that declares:
1. Tracked data types
2. Data collection purposes
3. User-linked data
4. Data sharing practices

## SayWell Privacy Classification

### Data Collected

#### 1. Device ID
```
Type: Device ID (random, non-persistent UUID)
Tracked: NO
Linked to User: NO
Purpose: Rate limiting only
```

#### 2. User Input (Text for Translation)
```
Type: User Input
Tracked: YES (cached for 30 days)
Linked to User: NO (no user account)
Purpose: Translation service + algorithm improvement
Third Parties: Google Gemini API
```

### Privacy Manifest Entries

#### App Intent Usage
- **AppIntents:** Not used
- **HealthKit:** Not used
- **HomeKit:** Not used

#### Network APIs
- **URLSession:** Used (translation requests to backend)
- **WebKit:** Not used
- **Network framework:** Not used

#### File APIs
- **FileManager:** Not used for sensitive data
- **UserDefaults:** Used for device ID + cached translations (App Group only)

### Privacy Manifest XML Structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- Tracked Data Types -->
  <key>NSPrivacyTrackedDataTypes</key>
  <array>
    <!-- User Input (text sent for translation) -->
    <string>NSPrivacyTrackedDataTypeOtherUserInput</string>
  </array>

  <!-- Data Collection Reasons -->
  <key>NSPrivacyTrackedDataCollection</key>
  <array>
    <dict>
      <key>NSPrivacyTrackedDataType</key>
      <string>NSPrivacyTrackedDataTypeOtherUserInput</string>
      <key>NSPrivacyTrackedDataLinked</key>
      <false/>
      <key>NSPrivacyTrackedDataLinkedTracking</key>
      <false/>
      <key>NSPrivacyTrackedDataCategory</key>
      <array>
        <!-- Service Provider: translation via Google Gemini -->
        <string>NSPrivacyTrackedDataCategoryAppFunctionality</string>
      </array>
    </dict>
  </array>

  <!-- Data Use Purposes -->
  <key>NSPrivacyCollectedDataTypes</key>
  <array>
    <!-- Device ID for rate limiting -->
    <dict>
      <key>NSPrivacyCollectedDataType</key>
      <string>NSPrivacyCollectedDataTypeDeviceID</string>
      <key>NSPrivacyCollectedDataTypeLinked</key>
      <false/>
      <key>NSPrivacyCollectedDataTypeTracking</key>
      <false/>
      <key>NSPrivacyCollectedDataTypePurposes</key>
      <array>
        <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
      </array>
    </dict>
    
    <!-- User Input (text for translation) -->
    <dict>
      <key>NSPrivacyCollectedDataType</key>
      <string>NSPrivacyCollectedDataTypeOtherUserInput</string>
      <key>NSPrivacyCollectedDataTypeLinked</key>
      <false/>
      <key>NSPrivacyCollectedDataTypeTracking</key>
      <false/>
      <key>NSPrivacyCollectedDataTypePurposes</key>
      <array>
        <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
      </array>
    </dict>
  </array>

  <!-- Third-Party Data Sharing -->
  <key>NSThirdPartyIsSharingUserData</key>
  <true/>
  
  <!-- Domains with Tracking -->
  <key>NSThirdPartyIsTrackingUser</key>
  <false/>

  <!-- Third Party Domains -->
  <key>NSPrivacyTracking</key>
  <false/>

  <!-- Minimum Required Keys (No NSUserTrackingUsageDescription needed) -->
  <key>NSUserTrackingUsageDescription</key>
  <string>SayWell does not track users across apps or websites.</string>

</dict>
</plist>
```

### App Store Data & Privacy Form

When submitting to App Store, fill out "Data & Privacy" form:

#### Data Collected
- ☑ Device ID (identifier)
- ☑ User Input (text for translation)

#### Data Not Collected
- ☐ Name / Email
- ☐ Photo / Video
- ☐ Audio
- ☐ Location
- ☐ Health / Fitness
- ☐ Financial Info
- ☐ Precise Location

#### Data Linked to User
- ☐ No - data NOT linked to user

#### Data Tracking (IDFA)
- ☐ We do NOT request App Tracking Transparency permission
- ☐ No tracking across apps/websites

#### Data Sharing with Third Parties
- ☑ Google Gemini API (for translation service)
  - Purpose: Service Functionality
  - Sharing User Data: Yes (normalized text only)
  - Tracking: No

#### Data Retention
- **Device ID:** Until app uninstall
- **User Input:** 30 days (auto-expires in cache)

#### User Privacy Controls
- ☑ User can delete cached data via app settings
- ☑ User can request data deletion
- ☑ No user account / profiling

### Implementation Checklist

- [ ] Create `PrivacyInfo.xcprivacy` with above XML
- [ ] Add to Xcode project (both SayWell target and SayWellKeyboard target)
- [ ] Verify privacy settings in Target → Build Settings
- [ ] Test privacy manifest validation: `plutil -lint PrivacyInfo.xcprivacy`
- [ ] Submit with accurate Data & Privacy form in App Store Connect

### Key Points for Reviewers

1. **No Tracking:** SayWell does not track users across apps or websites
2. **Minimal Data:** Only device ID + text for translation collected
3. **Not Linked:** Data is NOT linked to user identity
4. **Transparent:** Third-party sharing (Google Gemini) is disclosed
5. **User Control:** Users can delete cached data anytime

---

## References

- [Apple Privacy Manifest Documentation](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
- [App Store Connect Privacy Overview](https://developer.apple.com/app-store/app-privacy-details/)
- [NSPrivacy Keys Reference](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/nsprivacy)

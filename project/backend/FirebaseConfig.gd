class_name FirebaseConfig
extends RefCounted

## Fill these in once the Firebase project exists:
## Firebase Console → Project Settings → General → Web API Key, and Project ID.
## These are public client identifiers, not secrets — access is enforced by
## firestore.rules, not by hiding this key.

const PROJECT_ID := "fitarcade-app"
const API_KEY := "AIzaSyD_kM-u7mFiOEPDXJ4FFNGMXI2xNc6SnaE"

## Google Sign-In / OAuth credentials:
## Public Web / Desktop Client ID (safe to commit; public client identifier).
## Client secrets must NEVER be committed to Git. Public clients (Android/iOS/Desktop)
## authenticate via SHA-1 fingerprints or PKCE.
const GOOGLE_CLIENT_ID := "1062625300261-bqaalsrd03ttvs98cg9agnjhbj5ahgrj.apps.googleusercontent.com"
const GOOGLE_DESKTOP_CLIENT_ID := "1062625300261-jb4570r4ikf5kpsaokscic8t06lvj34f.apps.googleusercontent.com"
const GOOGLE_CLIENT_SECRET := ""

static func is_configured() -> bool:
	return PROJECT_ID != "" and API_KEY != ""

static func is_google_configured() -> bool:
	return GOOGLE_CLIENT_ID != ""

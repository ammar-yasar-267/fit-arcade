class_name FirebaseConfig
extends RefCounted

## Fill these in once the Firebase project exists:
## Firebase Console → Project Settings → General → Web API Key, and Project ID.
## These are public client identifiers, not secrets — access is enforced by
## firestore.rules, not by hiding this key.

const PROJECT_ID := "fitarcade-app"
const API_KEY := "AIzaSyD_kM-u7mFiOEPDXJ4FFNGMXI2xNc6SnaE"

static func is_configured() -> bool:
	return PROJECT_ID != "" and API_KEY != ""

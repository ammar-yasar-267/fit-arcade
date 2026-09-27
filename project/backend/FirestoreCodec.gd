class_name FirestoreCodec
extends RefCounted

## Converts between plain GDScript Dictionaries and Firestore's typed REST
## document format (https://firestore.googleapis.com/v1/.../documents).

static func to_value(v) -> Dictionary:
	match typeof(v):
		TYPE_STRING:
			return {"stringValue": v}
		TYPE_INT:
			return {"integerValue": str(v)}
		TYPE_FLOAT:
			return {"doubleValue": v}
		TYPE_BOOL:
			return {"booleanValue": v}
		TYPE_DICTIONARY:
			var fields := {}
			for k in v.keys():
				fields[k] = to_value(v[k])
			return {"mapValue": {"fields": fields}}
		TYPE_ARRAY:
			var values := []
			for item in v:
				values.append(to_value(item))
			return {"arrayValue": {"values": values}}
		_:
			return {"nullValue": null}

static func from_value(fv: Dictionary):
	if fv.has("stringValue"):
		return fv["stringValue"]
	if fv.has("integerValue"):
		return int(fv["integerValue"])
	if fv.has("doubleValue"):
		return float(fv["doubleValue"])
	if fv.has("booleanValue"):
		return fv["booleanValue"]
	if fv.has("timestampValue"):
		return fv["timestampValue"]
	if fv.has("mapValue"):
		var result := {}
		var fields = fv["mapValue"].get("fields", {})
		for k in fields.keys():
			result[k] = from_value(fields[k])
		return result
	if fv.has("arrayValue"):
		var result := []
		var values = fv["arrayValue"].get("values", [])
		for item in values:
			result.append(from_value(item))
		return result
	return null

## Dictionary -> Firestore document body, for create/patch requests.
static func encode_fields(data: Dictionary) -> Dictionary:
	var fields := {}
	for k in data.keys():
		fields[k] = to_value(data[k])
	return {"fields": fields}

## Firestore document response -> plain Dictionary.
static func decode_document(doc: Dictionary) -> Dictionary:
	var result := {}
	if doc == null or not doc.has("fields"):
		return result
	var fields = doc["fields"]
	for k in fields.keys():
		result[k] = from_value(fields[k])
	return result

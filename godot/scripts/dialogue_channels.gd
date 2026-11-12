class_name DialogueChannels
extends RefCounted
## Channel data is independent of the resident roster, model provider and widgets.
const ALL := "group:all"
const HISTORY_LIMIT := 200
var histories: Dictionary = {}
var drafts: Dictionary = {}
var unread: Dictionary = {}
var statuses: Dictionary = {}

static func direct(actor_id: String) -> String:
	return "direct:" + actor_id

func append(channel: String, actor_id: String, text: String, kind := "message", request_id := "") -> Dictionary:
	var entry := {"message_id": Crypto.new().generate_random_bytes(12).hex_encode(),
		"channel_id": channel, "sender_id": actor_id, "text": text, "kind": kind}
	if not request_id.is_empty(): entry["request_id"] = request_id
	if not histories.has(channel): histories[channel] = []
	histories[channel].append(entry)
	if histories[channel].size() > HISTORY_LIMIT: histories[channel].pop_front()
	return entry

func context(channel: String, recipients: Array, message_id: String, excluded_ids:Array=[]) -> Dictionary:
	var recent: Array = []
	var records: Array = histories.get(channel, [])
	for entry in records.slice(maxi(0, records.size() - 12)):
		if entry.message_id in excluded_ids:continue
		if entry.kind not in ["message", "question", "answer", "autonomy"] or entry.message_id == message_id: continue
		recent.append({"sender_id": entry.sender_id, "text": str(entry.text).left(600), "kind": entry.kind})
	return {"channel_id": channel, "mode": "group" if channel == ALL else "direct",
		"message_id": message_id, "sender_id": "human", "recipient_ids": recipients.duplicate(), "recent_messages": recent}

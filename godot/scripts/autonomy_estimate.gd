extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
static func usage_reference(config: Dictionary) -> String:
	var sample: Dictionary=config.get("measured_usage",{})
	if int(sample.get("sample_count",0))<1 or float(sample.get("average_total_tokens",0))<=0:return ""
	var mean:=int(ceil(float(sample.average_total_tokens)))
	return LocalText.text("system.autonomy_estimate.measured_mean_d_tokens_per_autonomous_turn_s")%[mean,str(sample.get("level","")),int(sample.sample_count),mean*int(config.levels.ultra.hourly)]
static func tokens(config: Dictionary,context: Dictionary) -> int:
	var estimate: Dictionary=config.get("estimate",{})
	if estimate.is_empty():return 0
	var text: String=JSON.stringify(JSON.stringify(context));var ascii_count:=0
	for index in range(text.length()):
		if text.unicode_at(index)<128:ascii_count+=1
	return int(ceil((float(estimate.base_ascii)+ascii_count)/float(estimate.ascii_per_token)+(float(estimate.base_non_ascii)+text.length()-ascii_count)/float(estimate.non_ascii_per_token)))+int(estimate.protocol_tokens)+int(estimate.output_tokens)

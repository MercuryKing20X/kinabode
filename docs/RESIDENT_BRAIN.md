# Resident brain / 伙伴大脑

The live game gives each stable resident one utility brain. `brain.json` holds new needs, rates, activity prerequisites, durations, preferences and text in Chinese and English. Existing hunger, personality packs, relationships, schedules, weather, work yield and movement speeds remain authoritative. Raw legacy engine fixtures retain the compatibility projection; Main activates the brain with the existing intelligence presets.

大脑每隔数秒按需要、性格、环境、社交、新鲜度和本人独立随机源挑选。跟随时保留原选择，在主角附近做小事；玩家安排和托管派活经同一入口，先让出原自主动作，任务结束后重新选择。很饿时只留下找主角等开饭；不会自行劳动、取食或加关系分。

World remains the sole route owner. Work, Farm, Fireside and the intention executor retain all permissions and physical commits. LocalCompanion retains speech and delegated executors; Playground and LivelyCompanions no longer run competing idle decisions in the live game. Original day events, island stories and Dark Island behavior enter through brain candidates. The steward retains its planning tables and watchdogs; dispatch now runs inside each recipient brain (see round two below).

Right-click a companion, or click the portrait in their details, to open **On my mind**. It shows the current wish and reasons, needs as words and five recent choices. Lifeblood's existing inner voice page is separate. No model is called by a local decision or this panel.

右键伙伴或点击居民详情头像可看“心里话”，包含当前选择及原因、需要的文字状态、最近五次选择。面板不显示需要分数，不替生命孕育发言，不调用模型。

`brain-traces/brain-trace-YYYY-MM-DD.jsonl` in the game data directory records choices, the top three scores and outcomes. Only the latest three calendar days are retained. Logs contain activity IDs, local reasons and authored local interaction lines, with no connection details or private conversation content. Decisions are session-only and never resume work after loading. `HABITAT_BRAIN_SEED` optionally selects a reproducible per-resident seed; reproducing an entire simulation also requires identical initial world state, weather, elapsed steps and player input.

## Round two / 互动与托管

Each stable resident has one session-only ResidentBrain. World owns routes and
Work/Farm/Fireside own physical commits. Needs and utility choices read the
original hunger, personality, schedule and weather rules.

Player orders and stewardship arrangements enter `mandate`; group dispatches
enter `team`, which obtains each selected resident's brain execution before the
original executor runs once. Steward questions and reports enter `effect` as
high-priority speech/UI candidates without cancelling an existing physical job.
Trace dispatch receipts identify `via: ResidentBrain`. Goal planning, receipts,
watchdogs and the steward timeline remain in their existing modules.

`brain-interactions.json` contains authored Chinese and English lines and only
new interaction settings. BrainInteractions observes actual host movement,
coast, weather, daylight, conversation, work, gifts and meals. Sustained
conditions have bounded stages; elapsed time alone does not produce a scene.
Candidates approach through the original World route. Delivered lines alone
consume daily deduplication and produce interaction receipts. Existing speech,
held, assembly, stop, personality and hunger gates remain authoritative.
Daily line receipts use the existing local-dialogue preference store, not world
memories or save backfill. The mind panel shows authored lines and their reasons.

Only social invitations pass through personality willingness. Work, meals and
assembly never call that policy. Original material, hunger, target, permission
and busy validation still apply to every command. A valid work order can have an
authored acknowledgement; a blocked or partial job is never called complete.
Peer invitations share an actual destination and activity, can be declined with
a reason, and yield to real commands. Sweeping and tidying poses remain cosmetic.

## Regression repair / 接管后的回归

Frozen migration worlds may lack a session generation; brain initialization uses
zero until a live world supplies it. Daily gestures, relationship seats and work
companionship use brain provider candidates and retain the original executor,
claims and speech gates. Free schedules and wandering retain their original
opportunity clock. Disabled chatter cannot reserve a speaking interaction.

Explicit following keeps the original HungerSystem queue and bridge executor,
including when daily activities are disabled. Following shelter targets obey the
existing nearby radius. Free return visits retain both the regular interval and
the original far-away grace condition. These changes grant no work or resources.

Disabled routines skip unnecessary brain sampling. Accepted scenes and their
original speech retry opportunities continue to advance each frame. Brain
microsecond counters are diagnostic only
and never enter scores, saved state or deterministic trace comparisons.

Hungry uninvited onlookers are a stationary food candidate: the existing
read-only fire/seat/distance/settling validator supplies the cue. The brain may
choose its original look pose at that spot; it creates no approach, invitation,
food or speech. Host feedback keeps its original local speech window before
new brain interaction lines can consume the same opportunity.

An accepted brain scene starts only when both speakers can use the existing
personal speech window. Its peer lines use `brain_pair` through the same pair
validation; they do not spend the separate LocalDialogue three-old-lines quota.
Due scene replies compete before new idle lines, without bypassing any gap.

The original resident clock advances once before the shared speech window, so
anniversary and retained preference reminders can use an opening cooldown.
The later routine pass receives zero elapsed time for active brains; it does
not advance that same clock twice. Clickable need bubbles avoid the fire's
actual hit rectangle, preserving separate fire and need input.

## Remaining speech regressions / 发言回归收尾

Need bubbles retain the ordinary local speech outlet. Within an existing idle
speech opportunity, a due need competes before generic fact reminders; special
retained-memory windows and already accepted peer replies keep their priority.
The original earned three-old-lines LocalDialogue substitution still precedes
this ordinary old-line opportunity. A real newly held catch may deliver
`need_satisfied` through the original
thank-you exception even while pending fish blocks idle movement. Clicking the
bubble still invokes the original host command and real fishing executor.

Host interaction observations remain pending while the original personal or
village speech gate is closed. They become activity candidates when that gate
will open by the next decision, allowing the existing short approach without
reserving the resident's body for a full cooldown. Real committed host-event
feedback retains its original priority. This keeps ordinary rhythm activities available without changing utility scores,
weights, gaps, scene limits or content. Delivery still repeats the original
validation; a candidate is never proof of delivered speech.

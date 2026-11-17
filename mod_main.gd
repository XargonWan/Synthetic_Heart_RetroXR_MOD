## Synthetic Heart Rift -- a RetroXR mod.
##
## Adds the Synthetic Heart Rift Summoner: switch it on and Synthetic Heart (SyntH)
## steps into the room through the Rift Vessel on its server. The mod is a CLIENT:
## it connects to the SyntH server the player names, never hosts one.
##
## The type string is written into save slots; it is permanent once anyone has
## used it.
extends RetroMod

const SUMMONER_TYPE := "xenu.synth_rift:rift_summoner"
const RiftFollow := preload("res://mods/xenu.synth_rift/scripts/rift_follow.gd")


func register(api: ModApi) -> void:
	api.log_line("registering")
	api.register_object(SUMMONER_TYPE, "res://mods/xenu.synth_rift/scenes/rift_summoner.tscn",
		{"label": "Synthetic Heart Rift Summoner"})
	# "Follow me": told whenever a room is up, to bring Synth into one that has no Summoner of its own. A RetroXR without
	# the hook keeps the pods' own answer (their _ready takes the call).
	if api.has_method("on_scene_content_ready"):
		api.on_scene_content_ready(Callable(RiftFollow, "on_room_ready"))

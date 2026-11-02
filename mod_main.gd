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


func register(api: ModApi) -> void:
	api.log_line("registering")
	api.register_object(SUMMONER_TYPE, "res://mods/xenu.synth_rift/scenes/rift_summoner.tscn",
		{"label": "Synthetic Heart Rift Summoner"})

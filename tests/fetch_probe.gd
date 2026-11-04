## AssetFetcher against a slow server (driven by fetch_probe.py, which starts one): a download that keeps arriving is
## never cut off however long it takes, one that stops is given up on after `stall_sec`, an answer is not retried.
extends SceneTree

const AssetFetcher := preload("res://mods/xenu.synth_rift/scripts/asset_fetcher.gd")


func _initialize() -> void:
	var f := AssetFetcher.new()
	root.add_child(f)
	await process_frame
	f.setup("127.0.0.1:%s" % OS.get_environment("FETCH_PORT"), "")
	f.stall_sec = 2.0
	f.progress.connect(func(p: String, got: int, total: int) -> void:
		if got % 4 == 0:
			print("[probe] progress %s %d/%d" % [p, got, total]))
	var t0 := Time.get_ticks_msec()
	var steady: PackedByteArray = await f.get_fresh("/steady.bin")
	print("[probe] steady size=%d in %.1f s" % [steady.size(), float(Time.get_ticks_msec() - t0) / 1000.0])
	t0 = Time.get_ticks_msec()
	var stalled: PackedByteArray = await f.get_fresh("/stall.bin")
	print("[probe] stall size=%d in %.1f s" % [stalled.size(), float(Time.get_ticks_msec() - t0) / 1000.0])
	var missing: PackedByteArray = await f.get_fresh("/missing.bin")
	print("[probe] missing size=%d" % missing.size())
	quit(0)

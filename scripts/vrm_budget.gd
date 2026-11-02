## VrmBudget -- what a body is allowed to cost, so any VRM can be thrown at a Quest.
##
## A player can put ANY .vrm on the server. The ones in Synth's skins measure (Godot's own counts, after import):
## 33-70k vertices, 48-94k triangles, 17-28 materials, 126-180 bones, and 27-64 textures that are mostly 2048 x 2048
## RGBA: 180-240 MB of texture memory uncompressed, which is what a Quest cannot spare. Each body is therefore
## brought inside a budget once (and kept, see BodyCache), most expensive first:
##
##   1. TEXTURES: every image is brought down to the tier's size cap while it is decoded (a GLTFDocumentExtension
##      hook on the image parse, so the full-size copy is never uploaded), then given mipmaps and compressed (ETC2 on
##      a Quest, S3TC on a desktop). Compressing inside that hook does not hold (the importer's materials get an
##      uncompressed copy), so it is done on the textures the materials end up with.
##   2. MORPH TARGETS: a face carries 57 blend shapes on each of its surfaces and her expressions move about 14;
##      the others are dropped (each one is a full vertex buffer, and the GPU blends them every frame).
##   3. TRIANGLES: over the tier's cap the mesh is brought down through Godot's own simplifier (ImporterMesh
##      LODs), finest level that fits; and a LOD chain is kept so the far body is cheaper still.
##
## The tier is `quest` on Android (or when RETROXR_TIER=quest, for tests) and `desktop` otherwise. The numbers are
## starting points: they are measured on a desktop; a headset is what settles them.
extends RefCounted

## Bump it when a step above changes what a body looks like: a cached body of another version is regenerated.
const BUDGET_VERSION := 1

const TIERS := {
	"quest": {"tex_cap": 1024, "tex_format": Image.COMPRESS_ETC2, "max_tris": 35000, "lods": true},
	"desktop": {"tex_cap": 2048, "tex_format": Image.COMPRESS_S3TC, "max_tris": 150000, "lods": true},
}


static func tier_name() -> String:
	var forced := OS.get_environment("RETROXR_TIER")
	if TIERS.has(forced):
		return forced
	return "quest" if OS.has_feature("android") else "desktop"


static func tier() -> Dictionary:
	return TIERS[tier_name()]


## The image step, as a glTF extension: it is given each image's bytes and fills the Image the importer then uploads.
class ImageBudget extends GLTFDocumentExtension:
	func _parse_image_data(_state: GLTFState, image_data: PackedByteArray, mime_type: String, ret_image: Image) -> Error:
		var err := ret_image.load_png_from_buffer(image_data) if mime_type == "image/png" \
			else ret_image.load_jpg_from_buffer(image_data)
		if err != OK:
			return err
		# What the hook did, for the log and the tests (the importer may run it on any thread and may copy this
		# object, so the count lives in a dictionary that is shared).
		var stats: Dictionary = Engine.get_meta("synth_rift_image_stats", {})
		# (The importer works on its own copy of this object, so the size cap travels in the engine's metadata too.)
		var cap: int = Engine.get_meta("synth_rift_image_cap", 2048)
		var big := maxi(ret_image.get_width(), ret_image.get_height())
		# 8 x 8 placeholders and the like are left as they are.
		if big < 64:
			return OK
		if big > cap:
			var k := float(cap) / float(big)
			ret_image.resize(maxi(1, int(ret_image.get_width() * k)), maxi(1, int(ret_image.get_height() * k)),
				Image.INTERPOLATE_BILINEAR)
		stats["images"] = int(stats.get("images", 0)) + 1
		stats["resized"] = int(stats.get("resized", 0)) + (1 if big > cap else 0)
		return OK


## Run `callable` (which parses a glTF) with the image step registered. Returns what it returned.
static func with_image_budget(settings: Dictionary, callable: Callable) -> Variant:
	var hook := ImageBudget.new()
	Engine.set_meta("synth_rift_image_cap", int(settings.get("tex_cap", 2048)))
	Engine.set_meta("synth_rift_image_stats", {})
	GLTFDocument.register_gltf_document_extension(hook, false)
	var result: Variant = callable.call()
	GLTFDocument.unregister_gltf_document_extension(hook)
	return result


## Triangles, vertices, surfaces, blend shapes and texture bytes of everything drawn under `root`.
static func measure(root: Node) -> Dictionary:
	var out := {"tris": 0, "verts": 0, "surfaces": 0, "blend_shapes": 0, "texture_bytes": 0, "texture_max": 0}
	var seen := {}
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (n as MeshInstance3D).mesh
		if mesh == null:
			continue
		out["blend_shapes"] += mesh.get_blend_shape_count() * mesh.get_surface_count()
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			out["surfaces"] += 1
			out["verts"] += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var index: Variant = arrays[Mesh.ARRAY_INDEX]
			out["tris"] += (index as PackedInt32Array).size() / 3 if index is PackedInt32Array else 0
			var material := mesh.surface_get_material(s)
			if material is BaseMaterial3D:
				for slot in BaseMaterial3D.TEXTURE_MAX:
					var tex := (material as BaseMaterial3D).get_texture(slot)
					if tex != null and not seen.has(tex):
						seen[tex] = true
						var bytes := _texture_bytes(tex)
						out["texture_bytes"] += bytes
						out["texture_max"] = maxi(out["texture_max"], maxi(tex.get_width(), tex.get_height()))
	return out


## What a texture holds, from its image when it is a plain ImageTexture (the headless renderer cannot read one back,
## so then it is its size at 4 bytes a pixel, which is an upper bound).
static func _texture_bytes(tex: Texture2D) -> int:
	var image := tex.get_image()
	if image != null and not image.is_empty():
		return image.get_data().size()
	return tex.get_width() * tex.get_height() * 4


## Drop the blend shapes no expression moves, and bring the triangles under the cap. `face` is the VrmFace (the
## blend shape indices it keeps are rewritten). Returns what it did, for the log.
static func reduce_meshes(root: Node, face: RefCounted, settings: Dictionary) -> Dictionary:
	var max_tris := int(settings.get("max_tris", 150000))
	var instances: Array = []
	var total_tris := 0
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh is ArrayMesh:
			instances.append(mi)
			total_tris += _tris_of(mi.mesh)
	# The finest LOD level at which the whole body fits (0 = the file's own).
	var level := 0
	if total_tris > max_tris:
		level = _level_for(instances, max_tris)
	var dropped := 0
	for mi: MeshInstance3D in instances:
		var mesh := mi.mesh as ArrayMesh
		var keep: Array = face.call("blend_shapes_used", mi) if face != null else range(mesh.get_blend_shape_count())
		dropped += (mesh.get_blend_shape_count() - keep.size()) * mesh.get_surface_count()
		var rebuilt := _rebuild(mesh, keep, level, bool(settings.get("lods", true)))
		if rebuilt == null:
			continue
		var map := {}
		for i in keep.size():
			map[int(keep[i])] = i
		mi.mesh = rebuilt
		if face != null:
			face.call("remap_blend_shapes", mi, map)
	return {"lod_level": level, "tris_before": total_tris, "morph_dropped": dropped}


static func _tris_of(mesh: Mesh) -> int:
	var tris := 0
	for s in mesh.get_surface_count():
		var index: Variant = mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
		tris += (index as PackedInt32Array).size() / 3 if index is PackedInt32Array else 0
	return tris


## Lowest LOD level (1 = about half, 2 = a quarter ...) where the summed triangles are within `cap`.
static func _level_for(instances: Array, cap: int) -> int:
	var levels := {}
	for mi: MeshInstance3D in instances:
		var importer := _importer_of(mi.mesh as ArrayMesh, [], 0)
		importer.generate_lods(25.0, 60.0, [])
		for s in importer.get_surface_count():
			var base := (importer.get_surface_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			levels[0] = int(levels.get(0, 0)) + base
			var count := importer.get_surface_lod_count(s)
			for l in count:
				levels[l + 1] = int(levels.get(l + 1, 0)) + importer.get_surface_lod_indices(s, l).size() / 3
			# A surface with fewer levels stays at its coarsest for the rest.
			for l in range(count, 12):
				levels[l + 1] = int(levels.get(l + 1, 0)) + (importer.get_surface_lod_indices(s, count - 1).size() / 3 if count > 0 else base)
	for l in range(0, 13):
		if int(levels.get(l, 1 << 30)) <= cap:
			return l
	return 12


## An ImporterMesh of `mesh` with only the blend shapes `keep`, its triangles at LOD `level`.
static func _importer_of(mesh: ArrayMesh, keep: Array, level: int) -> ImporterMesh:
	var importer := ImporterMesh.new()
	for k in keep:
		importer.add_blend_shape(mesh.get_blend_shape_name(int(k)))
	importer.set_blend_shape_mode(mesh.blend_shape_mode)
	var coarse: ImporterMesh = null
	if level > 0:
		coarse = _importer_of(mesh, [], 0)
		coarse.generate_lods(25.0, 60.0, [])
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var shapes: Array = []
		if not keep.is_empty():
			var all_shapes := mesh.surface_get_blend_shape_arrays(s)
			for k in keep:
				shapes.append(all_shapes[int(k)])
		if coarse != null and coarse.get_surface_lod_count(s) > 0:
			var pick := mini(level - 1, coarse.get_surface_lod_count(s) - 1)
			arrays[Mesh.ARRAY_INDEX] = coarse.get_surface_lod_indices(s, pick)
		var flags := mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		importer.add_surface(mesh.surface_get_primitive_type(s), arrays, shapes, {}, mesh.surface_get_material(s),
			mesh.surface_get_name(s), flags)
	return importer


static func _rebuild(mesh: ArrayMesh, keep: Array, level: int, lods: bool) -> ArrayMesh:
	var importer := _importer_of(mesh, keep, level)
	if lods:
		importer.generate_lods(25.0, 60.0, [])
	return importer.get_mesh()


## What the image step did in the last parse: {images, bytes_before, bytes_after} (bytes uncompressed at full size
## against what was kept).
static func last_image_stats() -> Dictionary:
	return Engine.get_meta("synth_rift_image_stats", {})


## Mipmap and compress (to the tier's format) every texture the materials of `root` use. Returns
## {textures, bytes_before, bytes_after, errors}; bytes are what the pixels take, mipmaps included.
static func compress_textures(root: Node, settings: Dictionary) -> Dictionary:
	var format := int(settings.get("tex_format", -1))
	var out := {"textures": 0, "bytes_before": 0, "bytes_after": 0, "errors": 0}
	if format < 0:
		return out
	# old texture -> what replaces it (a texture shared by several slots or materials is replaced by ONE).
	var replaced := {}
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (n as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var material := mesh.surface_get_material(s)
			if not (material is BaseMaterial3D):
				continue
			for slot in BaseMaterial3D.TEXTURE_MAX:
				var tex := (material as BaseMaterial3D).get_texture(slot)
				if tex == null or not (tex is ImageTexture):
					continue
				# A texture the material never samples is let go: emission and normal in a material that has no lighting
				# (the VRM ones are unlit: the engine does not even save those slots, and the picture is the same).
				var base := material as BaseMaterial3D
				if (slot == BaseMaterial3D.TEXTURE_EMISSION and not base.emission_enabled) \
						or (slot == BaseMaterial3D.TEXTURE_NORMAL and not base.normal_enabled) \
						or ((slot == BaseMaterial3D.TEXTURE_EMISSION or slot == BaseMaterial3D.TEXTURE_NORMAL) \
							and base.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED):
					base.set_texture(slot, null)
					out["unused"] = int(out.get("unused", 0)) + 1
					continue
				if not replaced.has(tex):
					replaced[tex] = _compressed_copy(tex as ImageTexture, slot, format, out)
				if replaced[tex] != null:
					(material as BaseMaterial3D).set_texture(slot, replaced[tex])
	return out


## A compressed, mipmapped copy of `tex` as a new ImageTexture; null when it is left as it is (tiny, already
## compressed, or it would not compress).
static func _compressed_copy(tex: ImageTexture, slot: int, format: int, out: Dictionary) -> ImageTexture:
	var image := tex.get_image()
	if image == null or image.is_empty() or image.is_compressed() or maxi(image.get_width(), image.get_height()) < 64:
		return null
	var source := Image.COMPRESS_SOURCE_GENERIC
	if slot == BaseMaterial3D.TEXTURE_ALBEDO or slot == BaseMaterial3D.TEXTURE_EMISSION:
		source = Image.COMPRESS_SOURCE_SRGB
	elif slot == BaseMaterial3D.TEXTURE_NORMAL:
		source = Image.COMPRESS_SOURCE_NORMAL
	out["bytes_before"] += image.get_data().size()
	var packed := image.duplicate() as Image
	packed.generate_mipmaps()
	if packed.compress(format, source) != OK:
		out["errors"] += 1
		out["bytes_after"] += image.get_data().size()
		return null
	out["textures"] += 1
	out["bytes_after"] += packed.get_data().size()
	return ImageTexture.create_from_image(packed)

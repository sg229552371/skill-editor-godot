extends GutTest

const BrickCatalog = preload("res://skill_core/catalog/brick_catalog.gd")
const CATALOG_PATH := "res://data/bricks/brick_catalog.json"
const TEMP_INVALID_PATH := "user://brick_catalog_invalid_carrier.json"

func test_catalog_loads_all_registered_entries() -> void:
	var catalog := BrickCatalog.new()
	var result := catalog.load_from(CATALOG_PATH)
	assert_true(result.ok, "the catalog should load from the runtime data path")
	assert_eq(catalog.count(), 28, "the catalog contains all 28 source entries")
	assert_eq(catalog.list_by_status("已登记").size(), 25, "25 entries are registered")
	assert_eq(catalog.list_by_status("候选").size(), 3, "3 entries are candidates")

func test_catalog_lookup_and_exportability() -> void:
	var catalog := BrickCatalog.new()
	assert_true(catalog.load_from(CATALOG_PATH).ok)
	var projectile := catalog.get_brick("projectile_bolt")
	assert_eq(projectile.get("carrier"), "independent", "lookup preserves the carrier")
	assert_false(catalog.is_exportable("wall_reflection_candidate"), "candidate entries are not exportable")
	assert_true(catalog.is_exportable("projectile_bolt"), "registered entries are exportable")
	assert_eq(catalog.get_brick("unknown_brick_id"), {}, "unknown IDs return an empty dictionary")

func test_catalog_filters_by_carrier() -> void:
	var catalog := BrickCatalog.new()
	assert_true(catalog.load_from(CATALOG_PATH).ok)
	assert_eq(catalog.list_by_carrier("independent").size(), 15, "independent entries are filterable")
	assert_eq(catalog.list_by_carrier("attached").size(), 6, "attached entries are filterable")
	assert_eq(catalog.list_by_carrier("none").size(), 6, "none entries are filterable")
	assert_eq(catalog.list_by_carrier("self").size(), 1, "the annotated self entry is normalized")

func test_catalog_rejects_invalid_carrier_with_diagnostic() -> void:
	var invalid_json := '[{"brick_id":"temporary_invalid_carrier","name":"临时测试","carrier":"unsupported","status":"已登记","source":"test"}]'
	var file := FileAccess.open(TEMP_INVALID_PATH, FileAccess.WRITE)
	assert_not_null(file, "the temporary catalog should be writable")
	if file == null:
		return
	file.store_string(invalid_json)
	file.close()

	var catalog := BrickCatalog.new()
	var result := catalog.load_from(TEMP_INVALID_PATH)
	assert_false(result.ok, "an unsupported carrier must reject the catalog")
	assert_true(result.diagnostics.size() > 0, "rejection includes diagnostics")
	assert_true(str(result.diagnostics[0]).contains("temporary_invalid_carrier"), "diagnostic identifies the invalid brick_id")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_INVALID_PATH))

#include <reframework/API.hpp>
#if REFRAMEWORK_PLUGIN_VERSION_MAJOR != 1 || REFRAMEWORK_PLUGIN_VERSION_MINOR != 15
#error "BossSelect must be built against the upstream REFramework 1.15 compatibility SDK"
#endif

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <mutex>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

using reframework::API;
using reframework::InvokeRet;

namespace {
constexpr std::array<uint32_t, 3> SIRN_IDS{101u, 102u, 103u};
constexpr uint32_t TRAINING_GAME_MODE = 2u;
constexpr int BOOT_MIN_SCENE_ID = 3;
constexpr uint32_t GRID_COLUMNS = 4u;
constexpr uint32_t GRID_ROWS = 9u;
constexpr double FRAME_HEIGHT = 910.0;
constexpr double FRAME_RECT_HEIGHT = 928.0;
bool g_installed = false;
bool g_install_tried = false;
API::Field* g_game_mode_field = nullptr;
API::Field* g_ui_flow_handles_field = nullptr;
API::Method* g_get_texture_data_method = nullptr;
bool g_training_character_select_active = false;

std::mutex g_settle_mutex{};
API::ManagedObject* g_settle_widget = nullptr;
std::mutex g_sirn_names_mutex{};
std::vector<std::pair<uint32_t, std::string>> g_sirn_item_names{};
std::vector<API::ManagedObject*> g_sirn_items{};
struct SirnTextureState {
    bool ok = false;
    bool attempted = false;
    uint32_t last_attempt_tick = 0;
    void* last_holder = nullptr;
};
std::unordered_map<uint32_t, void*> g_configured_tiles{};
std::unordered_map<uint32_t, SirnTextureState> g_texture_state{};
uint32_t g_settle_tick = 0;

bool is_training_character_select();
thread_local std::vector<API::ManagedObject*> tls_cursor_widgets{};
thread_local std::vector<API::ManagedObject*> tls_selected_items{};
thread_local bool tls_selection_guard = false;

thread_local std::vector<bool> tls_available_force{};
thread_local std::vector<API::ManagedObject*> tls_construct_widgets{};
thread_local std::vector<bool> tls_inventory_force{};
thread_local std::vector<bool> tls_dlc_force{};
thread_local std::vector<bool> tls_rental_force{};

API& api() {
    return *API::get();
}

void log_info(const char* message) {
    api().log_info("[sirn_select] %s", message);
}

void log_warn(const char* message) {
    api().log_warn("[sirn_select] %s", message);
}

template <typename... Args>
void log_infof(const char* format, Args... args) {
    api().log_info(format, args...);
}

template <typename... Args>
void log_warnf(const char* format, Args... args) {
    api().log_warn(format, args...);
}

bool is_sirn_id(uint32_t fighter_id) {
    return std::find(SIRN_IDS.begin(), SIRN_IDS.end(), fighter_id) != SIRN_IDS.end();
}

void* arg_u32(uint32_t value) {
    return reinterpret_cast<void*>(static_cast<uintptr_t>(value));
}

void* arg_i32(int32_t value) {
    return reinterpret_cast<void*>(static_cast<uintptr_t>(static_cast<uint32_t>(value)));
}

void* arg_bool(bool value) {
    return reinterpret_cast<void*>(static_cast<uintptr_t>(value ? 1u : 0u));
}

bool invoke_bool(const InvokeRet& ret) {
    return ret.qword != 0;
}

API::Method* find_method(API::TypeDefinition* type, std::string_view requested, int fallback_param_count = -1) {
    if (type == nullptr) {
        return nullptr;
    }

    if (auto* exact = type->find_method(requested); exact != nullptr) {
        return exact;
    }

    const auto paren = requested.find('(');
    const auto bare = requested.substr(0, paren);

    for (auto* method : type->get_methods()) {
        if (method == nullptr || method->get_name() == nullptr) {
            continue;
        }
        if (bare != method->get_name()) {
            continue;
        }
        if (fallback_param_count >= 0 && static_cast<int>(method->get_num_params()) != fallback_param_count) {
            continue;
        }
        return method;
    }

    return nullptr;
}

API::Method* find_method(API::ManagedObject* object, std::string_view requested, int fallback_param_count = -1) {
    return object != nullptr ? find_method(object->get_type_definition(), requested, fallback_param_count) : nullptr;
}

API::Method* find_method_exact(API::TypeDefinition* type, std::string_view signature) {
    return type != nullptr ? type->find_method(signature) : nullptr;
}

InvokeRet invoke(API::ManagedObject* object, std::string_view method_name, std::vector<void*> args = {}) {
    if (object == nullptr) {
        return {};
    }

    auto* method = find_method(object, method_name, static_cast<int>(args.size()));
    if (method == nullptr) {
        return {};
    }

    return method->invoke(object, args);
}

API::ManagedObject* invoke_object(API::ManagedObject* object, std::string_view method_name, std::vector<void*> args = {}) {
    auto ret = invoke(object, method_name, std::move(args));
    if (ret.exception_thrown) {
        return nullptr;
    }
    return reinterpret_cast<API::ManagedObject*>(ret.ptr);
}

bool invoke_visible(API::ManagedObject* object, bool& value) {
    if (object == nullptr) {
        return false;
    }
    auto* method = find_method(object, "get_Visible", 0);
    if (method == nullptr) {
        return false;
    }
    auto ret = method->invoke(object, std::vector<void*>{});
    if (ret.exception_thrown) {
        return false;
    }
    value = invoke_bool(ret);
    return true;
}

bool set_visible(API::ManagedObject* object, bool value) {
    if (object == nullptr) {
        return false;
    }
    auto* method = find_method(object, "set_Visible(System.Boolean)", 1);
    if (method == nullptr) {
        return false;
    }
    std::vector<void*> args{arg_bool(value)};
    auto ret = method->invoke(object, args);
    return !ret.exception_thrown;
}

API::ManagedObject* get_object_field(API::ManagedObject* object, std::string_view field_name) {
    if (object == nullptr) {
        return nullptr;
    }

    auto* type = object->get_type_definition();
    auto* field = type != nullptr ? type->find_field(field_name) : nullptr;
    if (field == nullptr) {
        return nullptr;
    }

    auto* storage = field->get_data_raw(object, false);
    if (storage == nullptr) {
        return nullptr;
    }

    return *reinterpret_cast<API::ManagedObject**>(storage);
}

std::string type_name(API::Field* field) {
    if (field == nullptr || field->get_type() == nullptr) {
        return {};
    }
    return field->get_type()->get_full_name();
}

bool read_number(API::Field* field, void* object, bool is_value_type, double& out) {
    if (field == nullptr) {
        return false;
    }
    void* raw = field->get_data_raw(object, is_value_type);
    if (raw == nullptr) {
        return false;
    }

    const auto name = type_name(field);
    if (name == "System.Single") { out = *reinterpret_cast<float*>(raw); return true; }
    if (name == "System.Double") { out = *reinterpret_cast<double*>(raw); return true; }
    if (name == "System.SByte") { out = *reinterpret_cast<int8_t*>(raw); return true; }
    if (name == "System.Byte") { out = *reinterpret_cast<uint8_t*>(raw); return true; }
    if (name == "System.Int16") { out = *reinterpret_cast<int16_t*>(raw); return true; }
    if (name == "System.UInt16") { out = *reinterpret_cast<uint16_t*>(raw); return true; }
    if (name == "System.Int32") { out = *reinterpret_cast<int32_t*>(raw); return true; }
    if (name == "System.UInt32") { out = *reinterpret_cast<uint32_t*>(raw); return true; }
    if (name == "System.Int64") { out = static_cast<double>(*reinterpret_cast<int64_t*>(raw)); return true; }
    if (name == "System.UInt64") { out = static_cast<double>(*reinterpret_cast<uint64_t*>(raw)); return true; }

    // Enum fields use their underlying primitive type, but some REFramework builds
    // report only the enum name here. SF6's enum storage is 32-bit in this path.
    if (auto* t = field->get_type(); t != nullptr && t->is_enum()) {
        out = *reinterpret_cast<int32_t*>(raw);
        return true;
    }

    return false;
}

bool write_number(API::Field* field, void* object, bool is_value_type, double value) {
    if (field == nullptr) {
        return false;
    }
    void* raw = field->get_data_raw(object, is_value_type);
    if (raw == nullptr) {
        return false;
    }

    const auto name = type_name(field);
    if (name == "System.Single") { *reinterpret_cast<float*>(raw) = static_cast<float>(value); return true; }
    if (name == "System.Double") { *reinterpret_cast<double*>(raw) = value; return true; }
    if (name == "System.SByte") { *reinterpret_cast<int8_t*>(raw) = static_cast<int8_t>(value); return true; }
    if (name == "System.Byte") { *reinterpret_cast<uint8_t*>(raw) = static_cast<uint8_t>(value); return true; }
    if (name == "System.Int16") { *reinterpret_cast<int16_t*>(raw) = static_cast<int16_t>(value); return true; }
    if (name == "System.UInt16") { *reinterpret_cast<uint16_t*>(raw) = static_cast<uint16_t>(value); return true; }
    if (name == "System.Int32") { *reinterpret_cast<int32_t*>(raw) = static_cast<int32_t>(value); return true; }
    if (name == "System.UInt32") { *reinterpret_cast<uint32_t*>(raw) = static_cast<uint32_t>(value); return true; }
    if (name == "System.Int64") { *reinterpret_cast<int64_t*>(raw) = static_cast<int64_t>(value); return true; }
    if (name == "System.UInt64") { *reinterpret_cast<uint64_t*>(raw) = static_cast<uint64_t>(value); return true; }

    if (auto* t = field->get_type(); t != nullptr && t->is_enum()) {
        *reinterpret_cast<int32_t*>(raw) = static_cast<int32_t>(value);
        return true;
    }

    return false;
}

InvokeRet invoke_with_value_type(API::ManagedObject* object, API::Method* method, const void* value_data, size_t value_size) {
    if (object == nullptr || method == nullptr || value_data == nullptr) {
        return {};
    }

    // The native invoke bridge expects value-type arguments by address. Primitive
    // arguments use encoded pointer-sized values, but structs must remain intact.
    (void)value_size;
    std::vector<void*> args{const_cast<void*>(value_data)};
    return method->invoke(object, args);
}

class ManagedStringCache {
public:
    API::ManagedObject* get(std::string_view text) {
        std::lock_guard lock{mutex_};
        const std::string key{text};
        if (auto it = values_.find(key); it != values_.end()) {
            return it->second;
        }
        auto* created = api().create_managed_string_normal(key.c_str());
        if (created != nullptr) {
            created->add_ref();
            values_.emplace(key, created);
        }
        return created;
    }

private:
    std::mutex mutex_{};
    std::unordered_map<std::string, API::ManagedObject*> values_{};
};

ManagedStringCache g_string_cache{};

API::Method* string_equality_method() {
    static API::Method* cached = nullptr;
    static bool searched = false;
    if (searched) {
        return cached;
    }
    searched = true;

    auto* string_type = api().tdb()->find_type("System.String");
    if (string_type == nullptr) {
        return nullptr;
    }

    if ((cached = string_type->find_method("op_Equality(System.String,System.String)")); cached != nullptr) {
        return cached;
    }

    for (auto* method : string_type->get_methods()) {
        if (method == nullptr || method->get_name() == nullptr) {
            continue;
        }
        if (std::string_view{method->get_name()} != "op_Equality" || method->get_num_params() != 2) {
            continue;
        }
        auto params = method->get_params();
        if (params.size() != 2) {
            continue;
        }
        auto* p0 = reinterpret_cast<API::TypeDefinition*>(params[0].t);
        auto* p1 = reinterpret_cast<API::TypeDefinition*>(params[1].t);
        if (p0 != nullptr && p1 != nullptr && p0->get_full_name() == "System.String" && p1->get_full_name() == "System.String") {
            cached = method;
            break;
        }
    }
    return cached;
}

bool managed_string_equals(API::ManagedObject* value, std::string_view wanted) {
    if (value == nullptr) {
        return false;
    }
    auto* wanted_string = g_string_cache.get(wanted);
    auto* equals = string_equality_method();
    if (wanted_string == nullptr || equals == nullptr) {
        return false;
    }
    std::vector<void*> args{value, wanted_string};
    auto ret = equals->invoke(nullptr, args);
    return !ret.exception_thrown && invoke_bool(ret);
}

API::Method* string_contains_method() {
    static API::Method* cached = nullptr;
    static bool searched = false;
    if (searched) {
        return cached;
    }
    searched = true;

    auto* string_type = api().tdb()->find_type("System.String");
    if (string_type == nullptr) {
        return nullptr;
    }
    cached = find_method(string_type, "Contains(System.String)", 1);
    return cached;
}

bool managed_string_contains(API::ManagedObject* value, std::string_view wanted) {
    if (value == nullptr) {
        return false;
    }
    auto* wanted_string = g_string_cache.get(wanted);
    auto* contains = string_contains_method();
    if (wanted_string == nullptr || contains == nullptr) {
        return false;
    }
    std::vector<void*> args{wanted_string};
    auto ret = contains->invoke(value, args);
    return !ret.exception_thrown && invoke_bool(ret);
}

API::ManagedObject* object_name(API::ManagedObject* object) {
    return invoke_object(object, "get_Name");
}

bool object_name_is(API::ManagedObject* object, std::string_view wanted) {
    return managed_string_equals(object_name(object), wanted);
}

bool object_name_contains(API::ManagedObject* object, std::string_view wanted) {
    return managed_string_contains(object_name(object), wanted);
}

API::ManagedObject* direct_child(API::ManagedObject* parent, std::string_view wanted_name) {
    if (parent == nullptr) {
        return nullptr;
    }

    auto* child = invoke_object(parent, "get_Child");
    int visited = 0;
    while (child != nullptr && visited < 64) {
        if (object_name_is(child, wanted_name)) {
            return child;
        }
        child = invoke_object(child, "get_Next");
        ++visited;
    }
    return nullptr;
}

API::ManagedObject* find_descendant(API::ManagedObject* parent, std::string_view wanted, int depth) {
    if (parent == nullptr || depth <= 0) {
        return nullptr;
    }

    auto* child = invoke_object(parent, "get_Child");
    int visited = 0;
    while (child != nullptr && visited < 64) {
        if (object_name_is(child, wanted)) {
            return child;
        }
        if (auto* nested = find_descendant(child, wanted, depth - 1); nested != nullptr) {
            return nested;
        }
        child = invoke_object(child, "get_Next");
        ++visited;
    }
    return nullptr;
}

void collect_thumbnail_textures(API::ManagedObject* parent, int depth, std::vector<API::ManagedObject*>& result) {
    if (parent == nullptr || depth <= 0) {
        return;
    }

    auto* child = invoke_object(parent, "get_Child");
    int visited = 0;
    while (child != nullptr && visited < 64) {
        if (object_name_is(child, "e_texture_thumb") || object_name_contains(child, "texture_thumb")) {
            result.push_back(child);
        }

        collect_thumbnail_textures(child, depth - 1, result);
        child = invoke_object(child, "get_Next");
        ++visited;
    }
}

API::ManagedObject* grid_from_widget(API::ManagedObject* widget) {
    return get_object_field(widget, "mCtrlScrollGrid");
}

API::ManagedObject* find_main_panel(API::ManagedObject* grid) {
    auto* current = grid;
    for (int i = 0; i < 6 && current != nullptr; ++i) {
        auto* parent = invoke_object(current, "get_Parent");
        if (parent == nullptr) {
            return nullptr;
        }
        if (object_name_is(parent, "c_main")) {
            return parent;
        }
        current = parent;
    }
    return nullptr;
}

void resize_height(API::ManagedObject* element, double minimum_height) {
    if (element == nullptr) {
        return;
    }

    auto* get_size = find_method(element, "get_Size", 0);
    if (get_size == nullptr) {
        return;
    }
    auto size_ret = get_size->invoke(element, std::vector<void*>{});
    if (size_ret.exception_thrown) {
        return;
    }

    auto* size_type = get_size->get_return_type();
    auto* h_field = size_type != nullptr ? size_type->find_field("h") : nullptr;
    if (h_field == nullptr) {
        return;
    }

    double height = 0.0;
    if (!read_number(h_field, size_ret.bytes.data(), true, height) || height >= minimum_height) {
        return;
    }
    if (!write_number(h_field, size_ret.bytes.data(), true, minimum_height)) {
        return;
    }

    auto* set_size = find_method(element, "set_Size(via.Size)", 1);
    if (set_size == nullptr) {
        return;
    }
    const auto value_size = size_type != nullptr ? size_type->get_valuetype_size() : sizeof(uint64_t);
    invoke_with_value_type(element, set_size, size_ret.bytes.data(), value_size);
}

API::ManagedObject* configure_layout(API::ManagedObject* widget) {
    auto* grid = grid_from_widget(widget);
    if (grid == nullptr) {
        return nullptr;
    }

    auto* get_item_count = find_method(grid, "get_ItemCount", 0);
    if (get_item_count != nullptr) {
        auto item_count = get_item_count->invoke(grid, std::vector<void*>{});
        if (!item_count.exception_thrown) {
            auto* count_type = get_item_count->get_return_type();
            auto* x_field = count_type != nullptr ? count_type->find_field("x") : nullptr;
            auto* y_field = count_type != nullptr ? count_type->find_field("y") : nullptr;
            double rows = 0.0;
            if (x_field != nullptr && y_field != nullptr && read_number(y_field, item_count.bytes.data(), true, rows) && rows < GRID_ROWS) {
                write_number(x_field, item_count.bytes.data(), true, GRID_COLUMNS);
                write_number(y_field, item_count.bytes.data(), true, GRID_ROWS);
                if (auto* set_item_count = find_method(grid, "set_ItemCount(via.Uint2)", 1); set_item_count != nullptr) {
                    const auto value_size = count_type != nullptr ? count_type->get_valuetype_size() : sizeof(uint64_t);
                    invoke_with_value_type(grid, set_item_count, item_count.bytes.data(), value_size);
                }
            }
        }
    }

    auto* main_panel = find_main_panel(grid);
    auto* window = direct_child(main_panel, "c_WindowBG");
    resize_height(direct_child(window, "e_tex_base"), FRAME_HEIGHT);
    resize_height(direct_child(window, "e_rect_base"), FRAME_RECT_HEIGHT);
    return grid;
}

API::Method* texture_data_method() {
    if (g_get_texture_data_method != nullptr) {
        return g_get_texture_data_method;
    }
    auto* type = api().tdb()->find_type("app.FighterTextureCatalogUserDataHolder");
    g_get_texture_data_method = find_method(type, "GetTextureData(app.CHARA_ID)", 1);
    return g_get_texture_data_method;
}

std::vector<std::pair<uint32_t, std::string>> sirn_item_names(API::ManagedObject* widget) {
    std::vector<std::pair<uint32_t, std::string>> result{};
    auto* list = get_object_field(widget, "mListPlayerType");
    if (list == nullptr) {
        return {};
    }

    auto* get_count = find_method(list, "get_Count", 0);
    if (get_count == nullptr) {
        return {};
    }
    auto count_ret = get_count->invoke(list, std::vector<void*>{});
    if (count_ret.exception_thrown) {
        return {};
    }
    const auto count = static_cast<int32_t>(count_ret.dword);
    if (count <= 0 || count > 256) {
        return {};
    }

    std::unordered_map<uint32_t, std::string> names{};
    auto* get_item = find_method(list, "get_Item(System.Int32)", 1);
    if (get_item == nullptr) {
        return {};
    }

    for (int32_t index = 0; index < count; ++index) {
        std::vector<void*> args{arg_i32(index)};
        auto item_ret = get_item->invoke(list, args);
        if (item_ret.exception_thrown) {
            continue;
        }
        const auto fighter_id = item_ret.dword;
        if (is_sirn_id(fighter_id)) {
            names[fighter_id] = "item" + std::to_string(index);
        }
    }

    for (auto fighter_id : SIRN_IDS) {
        auto it = names.find(fighter_id);
        if (it == names.end()) {
            return {};
        }
        result.emplace_back(fighter_id, it->second);
    }
    return result;
}



void* configured_ptr_for(uint32_t fighter_id) {
    std::lock_guard lock{g_sirn_names_mutex};
    auto it = g_configured_tiles.find(fighter_id);
    return it != g_configured_tiles.end() ? it->second : nullptr;
}

void record_configured(uint32_t fighter_id, API::ManagedObject* item) {
    std::lock_guard lock{g_sirn_names_mutex};
    g_configured_tiles[fighter_id] = reinterpret_cast<void*>(item);
}

bool texture_ok_for(uint32_t fighter_id) {
    std::lock_guard lock{g_sirn_names_mutex};
    auto it = g_texture_state.find(fighter_id);
    return it != g_texture_state.end() && it->second.ok;
}

uint32_t texture_last_attempt(uint32_t fighter_id) {
    std::lock_guard lock{g_sirn_names_mutex};
    auto it = g_texture_state.find(fighter_id);
    return it != g_texture_state.end() ? it->second.last_attempt_tick : 0;
}

// The hover-illumination effect on character tiles is driven by native per-thumb
// draw state that the game establishes when IT binds a thumbnail (runtime probe
// 2026-08-26: game-bound thumbs carry a live animation tick at +0x64 and a
// texture descriptor of one native class at +0xF8; thumbs bound via a raw
// setTexture call carry a frozen tick and a different descriptor class). The
// game's own cell binder runs at grid construction - including for the SiRN
// cells, whose catalog holders resolve through GetSmallFaceThumbnailTex - so
// rebinding an already-correct texture from here DESTROYS that setup and the
// tile loses hover illumination. Bind only when the bound texture actually
// differs from the holder's inner texture.
// Layout notes (runtime-observed, this build): via.gui.Texture holds its bound
// via.render.Texture pointer at +0x18; via.render.TextureResourceHolder holds
// the inner texture pointer at +0x10.
static bool thumb_already_bound(API::ManagedObject* thumb, const void* expected_inner) {
    if (thumb == nullptr || expected_inner == nullptr) {
        return false;
    }
    // API::ManagedObject wraps the raw object pointer; the object IS the address.
    const uintptr_t thumb_addr = reinterpret_cast<uintptr_t>(thumb);
    const void* bound = *reinterpret_cast<void* const*>(thumb_addr + 0x18);
    return bound == expected_inner;
}

static const void* holder_inner_texture(const void* holder) {
    if (holder == nullptr) {
        return nullptr;
    }
    return *reinterpret_cast<void* const*>(reinterpret_cast<uintptr_t>(holder) + 0x10);
}

void install_sirn_texture_guard(const std::vector<API::ManagedObject*>& thumbs);
bool apply_sirn_texture(API::ManagedObject* item, uint32_t fighter_id) {
    if (item == nullptr) {
        log_warnf("[sirn_select] texture: no item for %u", fighter_id);
        return false;
    }

    std::vector<API::ManagedObject*> thumbs{};
    collect_thumbnail_textures(item, 8, thumbs);
    if (thumbs.empty()) {
        log_warnf("[sirn_select] texture: no thumbnail texture for %u", fighter_id);
        return false;
    }

    auto* method = texture_data_method();
    if (method == nullptr) {
        log_warn("texture: no GetTextureData method");
        return false;
    }

    std::vector<void*> args{arg_u32(fighter_id)};
    auto data_ret = method->invoke(nullptr, args);
    auto* data = !data_ret.exception_thrown ? reinterpret_cast<API::ManagedObject*>(data_ret.ptr) : nullptr;
    if (data == nullptr) {
        log_warnf("[sirn_select] texture: GetTextureData(%u) failed", fighter_id);
        return false;
    }

    auto* data_type = data->get_type_definition();
    auto* holder_field = data_type != nullptr ? data_type->find_field("FaceThumbnail_S") : nullptr;
    if (holder_field == nullptr) {
        log_warnf("[sirn_select] texture: no FaceThumbnail_S for %u", fighter_id);
        return false;
    }

    void* holder_raw = holder_field->get_data_raw(data, false);
    auto* holder_type = holder_field->get_type();
    if (holder_raw == nullptr || holder_type == nullptr) {
        log_warnf("[sirn_select] texture: invalid FaceThumbnail_S for %u", fighter_id);
        return false;
    }

    const void* holder_identity = nullptr;
    if (!holder_type->is_valuetype()) {
        holder_identity = *reinterpret_cast<void* const*>(holder_raw);
    }
    log_infof("[sirn_select] texture: binding id=%u holder=%p thumbs=%d",
              fighter_id, holder_identity, static_cast<int>(thumbs.size()));
    bool applied = false;
    const void* expected_inner = holder_type->is_valuetype()
        ? nullptr
        : holder_inner_texture(holder_identity);
    for (auto* thumb : thumbs) {
        auto* set_texture = find_method(thumb, "setTexture", 1);
        if (set_texture == nullptr) {
            continue;
        }

        if (!holder_type->is_valuetype() && thumb_already_bound(thumb, expected_inner)) {
            // Already correct: do NOT touch the thumb. Re-invoking setTexture
            // here would replace the game-established draw state and kill the
            // hover illumination (see comment above).
            applied = true;
            log_infof("[sirn_select] texture: skip id=%u already bound (inner=%p)",
                      fighter_id, expected_inner);
            continue;
        }

        if (holder_type->is_valuetype()) {
            auto ret = invoke_with_value_type(thumb, set_texture, holder_raw, holder_type->get_valuetype_size());
            applied = applied || !ret.exception_thrown;
        } else {
            auto* holder = *reinterpret_cast<API::ManagedObject**>(holder_raw);
            if (holder != nullptr) {
                std::vector<void*> tex_args{holder};
                auto ret = set_texture->invoke(thumb, tex_args);
                applied = applied || !ret.exception_thrown;
            }
        }
    }
    if (applied) {
        std::lock_guard lock{g_sirn_names_mutex};
        g_texture_state[fighter_id].last_holder = const_cast<void*>(holder_identity);
        install_sirn_texture_guard(thumbs);
    }
    if (applied && !thumbs.empty()) {
        auto* get_texture = find_method(thumbs.front(), "getTexture", 0);
        if (get_texture != nullptr) {
            auto ret = get_texture->invoke(thumbs.front(), std::vector<void*>{});
            log_infof("[sirn_select] texture: readback id=%u getTexture=%p",
                      fighter_id, !ret.exception_thrown ? ret.ptr : nullptr);
        }
    }
    return applied;
}

bool configure_sirn_item(API::ManagedObject* item, uint32_t fighter_id, bool force_texture) {
    if (item == nullptr) {
        return false;
    }

    // Texture binding: explicit paths (construct, cursor, selection) always
    // re-apply so a stale early bind - the catalog may not have resolved the
    // SiRN holders at construct time - is corrected as soon as the user
    // focuses the tile. The background watchdog keeps a 60-tick retry floor
    // so an unresolvable catalog entry cannot churn.
    bool texture_ok = true;
    bool attempt_texture = false;
    {
        std::lock_guard lock{g_sirn_names_mutex};
        auto& state = g_texture_state[fighter_id];
        texture_ok = state.ok;
        if (force_texture ||
            (!state.ok && (!state.attempted || g_settle_tick - state.last_attempt_tick >= 60))) {
            attempt_texture = true;
            state.attempted = true;
            state.last_attempt_tick = g_settle_tick;
        }
    }
    if (attempt_texture) {
        texture_ok = apply_sirn_texture(item, fighter_id);
        std::lock_guard lock{g_sirn_names_mutex};
        g_texture_state[fighter_id].ok = texture_ok;
    }
    set_visible(direct_child(item, "c_bg_m"), true);
    set_visible(direct_child(item, "e_texture_random"), false);

    // Name label: ONLY Ingrid (103) lacks a name message record, so her tile
    // would inherit the template "Ryu" text forever; hide it (the proven-safe
    // mutation - set_Message("") crashes). IDs 101/102 receive their real names
    // from the game at cell spawn ("SiRN Akuma"/"SiRN Bison") and must stay
    // untouched.
    if (fighter_id == 103u) {
        set_visible(find_descendant(item, "e_text_name", 8), false);
    }

    record_configured(fighter_id, item);
    return texture_ok;
}

void remember_sirn_item_names(const std::vector<std::pair<uint32_t, std::string>>& names) {
    std::lock_guard lock{g_sirn_names_mutex};
    g_sirn_item_names = names;
}

void remember_sirn_items(API::ManagedObject* grid,
                         const std::vector<std::pair<uint32_t, std::string>>& names) {
    std::lock_guard lock{g_sirn_names_mutex};
    g_sirn_items.clear();
    for (const auto& [fighter_id, item_name] : names) {
        (void)fighter_id;
        if (auto* item = direct_child(grid, item_name); item != nullptr) {
            g_sirn_items.push_back(item);
        }
    }
}

bool is_current_sirn_item(API::ManagedObject* item) {
    if (item == nullptr) {
        return false;
    }
    std::lock_guard lock{g_sirn_names_mutex};
    return std::find(g_sirn_items.begin(), g_sirn_items.end(), item) != g_sirn_items.end();
}

bool sirn_item_fighter_id(API::ManagedObject* item, uint32_t& fighter_id) {
    std::lock_guard lock{g_sirn_names_mutex};
    for (const auto& [candidate_id, item_name] : g_sirn_item_names) {
        if (object_name_is(item, item_name)) {
            fighter_id = candidate_id;
            return true;
        }
    }
    return false;
}

bool is_sirn_random_icon(API::ManagedObject* object) {
    if (object == nullptr || !object_name_is(object, "e_texture_random")) {
        return false;
    }

    auto* current = invoke_object(object, "get_Parent");
    for (int depth = 0; current != nullptr && depth < 8; ++depth) {
        uint32_t fighter_id = 0;
        if (sirn_item_fighter_id(current, fighter_id)) {
            return is_sirn_id(fighter_id);
        }
        current = invoke_object(current, "get_Parent");
    }
    return false;
}

int pre_sirn_texture_bind(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    if (!is_training_character_select() || argc < 3 || argv == nullptr) {
        return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    }
    {
        std::lock_guard lock{g_sirn_names_mutex};
        if (g_sirn_item_names.empty()) {
            return REFRAMEWORK_HOOK_CALL_ORIGINAL;
        }
    }
    auto* object = reinterpret_cast<API::ManagedObject*>(argv[1]);
    if (object == nullptr || !object_name_is(object, "e_texture_thumb")) {
        return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    }

    auto* current = invoke_object(object, "get_Parent");
    for (int depth = 0; current != nullptr && depth < 8; ++depth) {
        uint32_t fighter_id = 0;
        if (sirn_item_fighter_id(current, fighter_id) && is_sirn_id(fighter_id)) {
            std::lock_guard lock{g_sirn_names_mutex};
            auto it = g_texture_state.find(fighter_id);
            if (it != g_texture_state.end() && it->second.last_holder != nullptr) {
                // The game resets unassigned SiRN cells to default art on
                // (re)materialization and focus; substitute the correct SiRN
                // holder so the placeholder never reaches a draw.
                argv[2] = it->second.last_holder;
            }
            break;
        }
        current = invoke_object(current, "get_Parent");
    }
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

void install_sirn_texture_guard(const std::vector<API::ManagedObject*>& thumbs) {
    static bool installed = false;
    if (installed || thumbs.empty()) {
        return;
    }
    auto* set_texture = find_method(thumbs.front(), "setTexture", 1);
    if (set_texture == nullptr) {
        return;
    }
    installed = true;
    set_texture->add_hook(pre_sirn_texture_bind, nullptr, false);
    log_info("[sirn_select] texture guard hook installed");
}

// True when the object is Ingrid's (103) name label under a registered SiRN
// item. Her tile has no name message record, so any game-side re-show would
// render the inherited template "Ryu" text.
bool is_sirn_ingrid_label(API::ManagedObject* object) {
    if (object == nullptr || !object_name_is(object, "e_text_name")) {
        return false;
    }

    auto* current = invoke_object(object, "get_Parent");
    for (int depth = 0; current != nullptr && depth < 8; ++depth) {
        uint32_t fighter_id = 0;
        if (sirn_item_fighter_id(current, fighter_id)) {
            return fighter_id == 103u;
        }
        current = invoke_object(current, "get_Parent");
    }
    return false;
}

// True when the object is a SiRN tile's portrait plate. The game's focus
// refresh hides this plate for 1-2 frames (the visible "?" is the tile base
// layer behind it); force-TRUE blocks that hide on the managed path.
bool is_sirn_portrait_plate(API::ManagedObject* object) {
    if (object == nullptr || !object_name_is(object, "c_bg_m")) {
        return false;
    }

    auto* current = invoke_object(object, "get_Parent");
    for (int depth = 0; current != nullptr && depth < 8; ++depth) {
        uint32_t fighter_id = 0;
        if (sirn_item_fighter_id(current, fighter_id)) {
            return is_sirn_id(fighter_id);
        }
        current = invoke_object(current, "get_Parent");
    }
    return false;
}

int pre_sirn_random_visibility(int argc,
                               void** argv,
                               REFrameworkTypeDefinitionHandle*,
                               unsigned long long) {
    if (is_training_character_select() && argc > 2 && argv != nullptr) {
        auto* object = reinterpret_cast<API::ManagedObject*>(argv[1]);
        if (is_sirn_random_icon(object)) {
            // The SiRN tiles reuse the random-select marker object. Block the
            // original visibility write, including delayed writes after focus.
            argv[2] = arg_bool(false);
        } else if (is_sirn_portrait_plate(object)) {
            // Block the focus-refresh hide of the portrait plate. One-shot
            // logging: every managed write on a registered plate is recorded
            // (capped) so the post-fix log read-out can confirm whether the
            // native writer ever rides this path.
            static uint32_t plate_log = 0;
            if (plate_log < 60) {
                ++plate_log;
                bool wanted = true;
                void* raw = argv[2];
                wanted = raw != nullptr && (reinterpret_cast<uintptr_t>(raw) & 1u) != 0;
                log_infof("[sirn_select] vis: c_bg_m set_Visible(%d) blocked->true",
                          wanted ? 1 : 0);
            }
            argv[2] = arg_bool(true);
        } else if (is_sirn_ingrid_label(object)) {
            // Block re-shows of Ingrid's inherited template label at the
            // source so hover/focus never flashes "Ryu" for a frame.
            static uint32_t label_log = 0;
            if (label_log < 60) {
                ++label_log;
                log_info("[sirn_select] vis: ingrid label set_Visible blocked->false");
            }
            argv[2] = arg_bool(false);
        }
    }
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

// Frame-phase correction (the operative fix): the game's native refresh resets
// SiRN tile state through writes that managed hooks do not reliably intercept,
// during the GUI-update phase. on_imgui_frame is dispatched by APIProxy::on_frame
// from the same Mods::on_frame pass as the ScriptRunner's Lua re.on_frame
// (APIProxy registered immediately before ScriptRunner), so this callback runs in
// the proven winning window: after the native write, before the draw — the same
// vantage that made the Lua companion flash-free. The correction content is
// companion-exact (full reveal on any violation; see reassert_sirn_tiles).
void reveal_sirn_portraits(API::ManagedObject* widget, API::ManagedObject* grid, bool force_texture);
void reassert_sirn_tiles(API::ManagedObject* widget);
void on_imgui_frame_reassert(REFImGuiFrameCbData*) {
    API::ManagedObject* widget = nullptr;
    {
        std::lock_guard lock{g_settle_mutex};
        widget = g_settle_widget;
        if (widget != nullptr) {
            widget->add_ref();
        }
    }
    if (widget == nullptr) {
        return;
    }
    reassert_sirn_tiles(widget);
    widget->release();
}
// Shared correction core: companion-exact per-pass reveal. The game's native
// refresh resets tile state through paths managed hooks do not reliably see
// (plate hide, random-icon show, thumb placeholder, Ingrid label show); ANY
// violation on ANY tile triggers a full reveal of ALL tiles — texture re-bind
// unconditional, random icon hidden, plate shown, Ingrid label hidden — exactly
// mirroring the proven Lua companion. Name-derived tile scope per pass, so
// re-created cells are never skipped. Caller owns any add_ref/release.
void reassert_sirn_tiles(API::ManagedObject* widget) {
    if (widget == nullptr || !g_installed || !is_training_character_select()) {
        return;
    }

    std::vector<std::pair<uint32_t, std::string>> names;
    {
        std::lock_guard lock{g_sirn_names_mutex};
        names = g_sirn_item_names;
    }
    if (names.size() != SIRN_IDS.size()) {
        return;
    }
    auto* grid = grid_from_widget(widget);
    if (grid == nullptr) {
        return;
    }

    bool needs_refresh = false;
    for (const auto& [fighter_id, item_name] : names) {
        auto* item = direct_child(grid, item_name);
        if (item == nullptr) {
            continue;
        }
        auto* portrait = direct_child(item, "c_bg_m");
        auto* random_icon = direct_child(item, "e_texture_random");
        bool portrait_visible = false;
        bool random_visible = false;
        const bool portrait_ok = invoke_visible(portrait, portrait_visible);
        const bool random_ok = invoke_visible(random_icon, random_visible);
        if (!portrait_ok || !portrait_visible || !random_ok || random_visible) {
            needs_refresh = true;
            break;
        }
        if (fighter_id == 103u) {
            auto* label = find_descendant(item, "e_text_name", 8);
            bool label_visible = false;
            if (invoke_visible(label, label_visible) && label_visible) {
                needs_refresh = true;
                break;
            }
        }
    }

    if (needs_refresh) {
        reveal_sirn_portraits(widget, grid, /*force_texture=*/true);
    }
}

void reveal_sirn_portraits(API::ManagedObject* widget, API::ManagedObject* grid, bool force_texture) {
    if (widget == nullptr || grid == nullptr) {
        return;
    }

    const auto names = sirn_item_names(widget);
    if (names.size() != SIRN_IDS.size()) {
        static uint32_t incomplete_streak = 0;
        ++incomplete_streak;
        if (incomplete_streak % 300 == 1) {
            log_warnf("[sirn_select] reveal: roster mapping incomplete (%d/3)",
                      static_cast<int>(names.size()));
        }
        return;
    }
    remember_sirn_item_names(names);
    remember_sirn_items(grid, names);
    int configured = 0;
    bool any_texture_pending = false;
    for (const auto& [fighter_id, item_name] : names) {
        if (configure_sirn_item(direct_child(grid, item_name), fighter_id, force_texture)) {
            ++configured;
        } else {
            any_texture_pending = true;
        }
    }
    static int last_configured = -1;
    static bool last_pending = false;
    static uint32_t reveal_calls = 0;
    ++reveal_calls;
    if (configured != last_configured || any_texture_pending != last_pending ||
        reveal_calls % 900 == 1) {
        log_infof("[sirn_select] reveal: %d/3 configured, %d tiles registered%s",
                  configured, static_cast<int>(g_sirn_items.size()),
                  any_texture_pending ? " (texture retry pending)" : "");
        last_configured = configured;
        last_pending = any_texture_pending;
    }
}
void reconcile_sirn_item(API::ManagedObject* item, uint32_t fighter_id, bool force_texture = true) {
    if (item == nullptr) {
        return;
    }

    bool selected = false;
    if (auto* get_selected = find_method(item, "get_Selected", 0); get_selected != nullptr) {
        const auto selected_ret = get_selected->invoke(item, std::vector<void*>{});
        selected = !selected_ret.exception_thrown && invoke_bool(selected_ret);
    }

    configure_sirn_item(item, fighter_id, force_texture);

    if (selected) {
        if (auto* set_selected = find_method(item, "setSelected(System.Boolean,System.Boolean)", 2);
            set_selected != nullptr) {
            std::vector<void*> args{arg_bool(true), arg_bool(true)};
            tls_selection_guard = true;
            set_selected->invoke(item, args);
            tls_selection_guard = false;
        }
    }

}

void reconcile_sirn_focus(API::ManagedObject* widget, API::ManagedObject* grid) {
    if (widget == nullptr || grid == nullptr) {
        return;
    }

    const auto names = sirn_item_names(widget);
    if (names.size() != SIRN_IDS.size()) {
        return;
    }
    remember_sirn_item_names(names);
    remember_sirn_items(grid, names);
    for (const auto& [fighter_id, item_name] : names) {
        reconcile_sirn_item(direct_child(grid, item_name), fighter_id);
    }
}

void hide_sirn_name(API::ManagedObject* item, uint32_t fighter_id) {
    if (fighter_id == 103u) {
        set_visible(find_descendant(item, "e_text_name", 8), false);
    }
}

int pre_sirn_selection(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    API::ManagedObject* item = nullptr;
    if (argc > 1 && argv != nullptr) {
        item = reinterpret_cast<API::ManagedObject*>(argv[1]);
    }
    tls_selected_items.push_back(item);

    if (!is_current_sirn_item(item)) {
        return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    }

    if (!tls_selection_guard && item != nullptr && is_training_character_select()) {
        uint32_t fighter_id = 0;
        if (sirn_item_fighter_id(item, fighter_id)) {
            configure_sirn_item(item, fighter_id, true);
            hide_sirn_name(item, fighter_id);
        }
    }
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

void post_sirn_selection(void**, REFrameworkTypeDefinitionHandle, unsigned long long) {
    API::ManagedObject* item = nullptr;
    if (!tls_selected_items.empty()) {
        item = tls_selected_items.back();
        tls_selected_items.pop_back();
    }
    if (tls_selection_guard || !is_current_sirn_item(item) || !is_training_character_select()) {
        return;
    }

    uint32_t fighter_id = 0;
    if (!sirn_item_fighter_id(item, fighter_id)) {
        return;
    }

    reconcile_sirn_item(item, fighter_id);
    hide_sirn_name(item, fighter_id);
}

void clear_portrait_settle() {
    std::lock_guard lock{g_settle_mutex};
    if (g_settle_widget != nullptr) {
        g_settle_widget->release();
        g_settle_widget = nullptr;
    }
}

void schedule_portrait_settle(API::ManagedObject* widget) {
    if (widget == nullptr) {
        return;
    }
    std::lock_guard lock{g_settle_mutex};
    if (g_settle_widget != widget) {
        if (g_settle_widget != nullptr) {
            g_settle_widget->release();
        }
        g_settle_widget = widget;
        g_settle_widget->add_ref();
    }
}


int current_scene_id() {
    auto* flow = api().get_managed_singleton("app.bFlowManager");
    if (flow == nullptr) {
        return -1;
    }
    auto* method = find_method(flow, "get_MainFlowID", 0);
    if (method == nullptr) {
        return -1;
    }
    auto ret = method->invoke(flow, std::vector<void*>{});
    return ret.exception_thrown ? -1 : static_cast<int>(ret.dword);
}

bool get_game_mode(uint32_t& mode) {
    if (g_game_mode_field == nullptr) {
        auto* battle = api().tdb()->find_type("gBattle");
        g_game_mode_field = battle != nullptr ? battle->find_field("Config") : nullptr;
    }
    if (g_game_mode_field == nullptr) {
        return false;
    }

    auto* config_type = g_game_mode_field->get_type();
    if (config_type == nullptr) {
        return false;
    }

    void* config_base = nullptr;
    bool config_is_value = config_type->is_valuetype();
    if (config_is_value) {
        config_base = g_game_mode_field->get_data_raw(nullptr, false);
    } else {
        auto* storage = g_game_mode_field->get_data_raw(nullptr, false);
        config_base = storage != nullptr ? *reinterpret_cast<void**>(storage) : nullptr;
    }
    if (config_base == nullptr) {
        return false;
    }

    auto* mode_field = config_type->find_field("_GameMode");
    if (mode_field == nullptr) {
        return false;
    }
    double numeric = 0.0;
    if (!read_number(mode_field, config_base, config_is_value, numeric)) {
        return false;
    }
    mode = static_cast<uint32_t>(numeric);
    return true;
}

bool is_training() {
    uint32_t mode = 0;
    return get_game_mode(mode) && mode == TRAINING_GAME_MODE;
}

bool has_active_training_character_flow() {
    auto* manager = api().get_managed_singleton("app.UIFlowManager");
    if (manager == nullptr) {
        return false;
    }

    if (g_ui_flow_handles_field == nullptr) {
        auto* manager_type = manager->get_type_definition();
        g_ui_flow_handles_field = manager_type != nullptr
            ? manager_type->find_field("_Handles")
            : nullptr;
    }
    if (g_ui_flow_handles_field == nullptr) {
        return false;
    }

    auto* handles_storage = g_ui_flow_handles_field->get_data_raw(manager, false);
    auto* handles = handles_storage != nullptr
        ? *reinterpret_cast<API::ManagedObject**>(handles_storage)
        : nullptr;
    if (handles == nullptr) {
        return false;
    }

    auto* get_count = find_method(handles, "get_Count", 0);
    auto* get_item = find_method(handles, "get_Item(System.Int32)", 1);
    if (get_count == nullptr || get_item == nullptr) {
        return false;
    }

    const auto count_ret = get_count->invoke(handles, std::vector<void*>{});
    const auto count = !count_ret.exception_thrown ? static_cast<int32_t>(count_ret.dword) : 0;
    if (count <= 0 || count > 256) {
        return false;
    }

    for (int32_t index = 0; index < count; ++index) {
        std::vector<void*> args{arg_i32(index)};
        const auto handle_ret = get_item->invoke(handles, args);
        auto* handle = !handle_ret.exception_thrown
            ? reinterpret_cast<API::ManagedObject*>(handle_ret.ptr)
            : nullptr;
        auto* param = invoke_object(handle, "GetParam");
        auto* param_type = param != nullptr ? param->get_type_definition() : nullptr;
        if (param_type != nullptr &&
            param_type->get_full_name() == "app.UIFlowGenericCharacterSetting.Param") {
            return true;
        }
    }
    return false;
}

bool refresh_training_character_select_scope() {
    g_training_character_select_active =
        is_training() && has_active_training_character_flow();
    return g_training_character_select_active;
}

// The matching-settings flow temporarily leaves GuiManager.mIsMatchingSetting
// false while it builds its fighter grid, so that flag is too late to scope the
// shared hGUI hooks. The actual Training selector has its own active flow param;
// require that identity and cache it for the hot visibility/focus hooks.
bool is_training_character_select() {
    return g_training_character_select_active;
}

void append_unique(API::ManagedObject* list, uint32_t fighter_id) {
    if (list == nullptr) {
        return;
    }

    auto* contains = find_method(list, "Contains(System.UInt32)", 1);
    if (contains != nullptr) {
        std::vector<void*> args{arg_u32(fighter_id)};
        auto ret = contains->invoke(list, args);
        if (!ret.exception_thrown && invoke_bool(ret)) {
            return;
        }
    }

    if (auto* add = find_method(list, "Add(System.UInt32)", 1); add != nullptr) {
        std::vector<void*> args{arg_u32(fighter_id)};
        auto ret = add->invoke(list, args);
        if (!ret.exception_thrown) {
            return;
        }
    }

    if (auto* add = find_method(list, "Add", 1); add != nullptr) {
        std::vector<void*> args{arg_u32(fighter_id)};
        add->invoke(list, args);
    }
}

void remove_sirn_ids(API::ManagedObject* list) {
    if (list == nullptr) {
        return;
    }

    auto* remove = find_method(list, "Remove(System.UInt32)", 1);
    if (remove == nullptr) {
        remove = find_method(list, "Remove", 1);
    }
    if (remove == nullptr) {
        return;
    }

    for (auto fighter_id : SIRN_IDS) {
        std::vector<void*> args{arg_u32(fighter_id)};
        remove->invoke(list, args);
    }
}

void on_frame_settle() {
    API::ManagedObject* widget = nullptr;
    {
        std::lock_guard lock{g_settle_mutex};
        if (g_settle_widget == nullptr) {
            return;
        }
        widget = g_settle_widget;
        widget->add_ref();
    }

    const auto release_widget = [&]() {
        if (widget != nullptr) {
            widget->release();
            widget = nullptr;
        }
    };

    if (!is_training_character_select()) {
        release_widget();
        clear_portrait_settle();
        return;
    }

    auto* grid = grid_from_widget(widget);
    if (grid == nullptr) {
        release_widget();
        clear_portrait_settle();
        return;
    }

    ++g_settle_tick;
    bool needs_refresh = false;
    const char* reason = "";
    bool saw_missing = false;
    bool all_missing = true;
    const auto names = sirn_item_names(widget);
    if (names.size() == SIRN_IDS.size()) {
        for (const auto& [fighter_id, item_name] : names) {
            auto* item = direct_child(grid, item_name);
            if (item == nullptr) {
                // Expansion cells materialize lazily after Construct returns;
                // there is nothing to patch until the game creates the tile.
                saw_missing = true;
                continue;
            }
            all_missing = false;
            if (configured_ptr_for(fighter_id) != reinterpret_cast<void*>(item)) {
                needs_refresh = true;
                reason = "cell (re)materialized";
                break;
            }
            if (fighter_id == 103u) {
                auto* label = find_descendant(item, "e_text_name", 8);
                bool label_visible = false;
                if (invoke_visible(label, label_visible) && label_visible) {
                    needs_refresh = true;
                    reason = "Ingrid label visible";
                    break;
                }
            }

            auto* portrait = direct_child(item, "c_bg_m");
            auto* random_icon = direct_child(item, "e_texture_random");

            bool portrait_visible = false;
            bool random_visible = false;
            const bool portrait_ok = invoke_visible(portrait, portrait_visible);
            const bool random_ok = invoke_visible(random_icon, random_visible);
            if (!portrait_ok || !portrait_visible) {
                needs_refresh = true;
                reason = "portrait not visible";
                break;
            }
            if (!random_ok || random_visible) {
                needs_refresh = true;
                reason = "random icon visible";
                break;
            }
            if (!texture_ok_for(fighter_id) &&
                g_settle_tick - texture_last_attempt(fighter_id) >= 60) {
                needs_refresh = true;
                reason = "texture retry due";
                break;
            }
        }
    }

    // Retire the watchdog when the select surface is gone for good (every tile
    // destroyed); a retained widget would otherwise churn forever off-screen.
    static uint32_t all_missing_streak = 0;
    all_missing_streak = all_missing ? all_missing_streak + 1 : 0;
    if (all_missing_streak >= 600) {
        log_info("[sirn_select] settle: retiring widget; select surface is gone");
        release_widget();
        clear_portrait_settle();
        return;
    }

    static bool settle_refresh_active = false;
    if (needs_refresh && !settle_refresh_active) {
        log_infof("[sirn_select] settle: refresh triggered (%s%s)",
                  reason, saw_missing ? "; tiles materializing" : "");
    }
    settle_refresh_active = needs_refresh;

    if (needs_refresh) {
        reveal_sirn_portraits(widget, grid, /*force_texture=*/false);
    }

    release_widget();
}

int pre_is_available(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    bool force = false;
    if (argc > 1 && argv != nullptr) {
        const auto fighter_id = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(argv[1]));
        force = is_training_character_select() && is_sirn_id(fighter_id);
    }
    tls_available_force.push_back(force);
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

void post_is_available(void** ret_val, REFrameworkTypeDefinitionHandle, unsigned long long) {
    bool force = false;
    if (!tls_available_force.empty()) {
        force = tls_available_force.back();
        tls_available_force.pop_back();
    }
    if (force && ret_val != nullptr) {
        *ret_val = reinterpret_cast<void*>(static_cast<uintptr_t>(1));
    }
}

void post_get_fighter_id_list(void** ret_val, REFrameworkTypeDefinitionHandle, unsigned long long) {
    if (ret_val == nullptr || *ret_val == nullptr) {
        return;
    }

    auto* list = reinterpret_cast<API::ManagedObject*>(*ret_val);
    if (refresh_training_character_select_scope()) {
        for (auto fighter_id : SIRN_IDS) {
            append_unique(list, fighter_id);
        }
    } else {
        // GetFighterIdList is shared and callers may retain its mutable result.
        // Scrub prior injections whenever the actual Training flow is absent.
        remove_sirn_ids(list);
    }
}

int pre_construct(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    API::ManagedObject* widget = nullptr;
    if (argc > 1 && argv != nullptr) {
        widget = reinterpret_cast<API::ManagedObject*>(argv[1]);
        if (refresh_training_character_select_scope()) {
            configure_layout(widget);
        }
    }
    tls_construct_widgets.push_back(widget);
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

void post_construct(void**, REFrameworkTypeDefinitionHandle, unsigned long long) {
    API::ManagedObject* widget = nullptr;
    if (!tls_construct_widgets.empty()) {
        widget = tls_construct_widgets.back();
        tls_construct_widgets.pop_back();
    }
    if (widget == nullptr) {
        return;
    }
    if (!refresh_training_character_select_scope()) {
        remove_sirn_ids(get_object_field(widget, "mListPlayerType"));
        return;
    }

    auto* grid = configure_layout(widget);
    reveal_sirn_portraits(widget, grid, /*force_texture=*/true);
    reconcile_sirn_focus(widget, grid);
    schedule_portrait_settle(widget);
}

int pre_cursor_change(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    API::ManagedObject* widget = nullptr;
    if (argc > 1 && argv != nullptr) {
        widget = reinterpret_cast<API::ManagedObject*>(argv[1]);
        if (is_training_character_select()) {
            schedule_portrait_settle(widget);
        }
    }
    tls_cursor_widgets.push_back(widget);
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

void post_cursor_change(void**, REFrameworkTypeDefinitionHandle, unsigned long long) {
    API::ManagedObject* widget = nullptr;
    if (!tls_cursor_widgets.empty()) {
        widget = tls_cursor_widgets.back();
        tls_cursor_widgets.pop_back();
    }
    if (widget == nullptr || !is_training_character_select()) {
        return;
    }
    reconcile_sirn_focus(widget, grid_from_widget(widget));
}

void push_force(std::vector<bool>& stack, bool value) {
    stack.push_back(value);
}

bool pop_force(std::vector<bool>& stack) {
    if (stack.empty()) {
        return false;
    }
    const bool value = stack.back();
    stack.pop_back();
    return value;
}

int pre_inventory_ownership(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    bool force = false;
    if (argc > 2 && argv != nullptr) {
        const auto fighter_id = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(argv[2]));
        force = is_training_character_select() && is_sirn_id(fighter_id);
    }
    push_force(tls_inventory_force, force);
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

void post_inventory_ownership(void** ret_val, REFrameworkTypeDefinitionHandle, unsigned long long) {
    if (pop_force(tls_inventory_force) && ret_val != nullptr) {
        *ret_val = reinterpret_cast<void*>(static_cast<uintptr_t>(1));
    }
}

int pre_dlc_item_ownership(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    bool force = false;
    if (argc > 3 && argv != nullptr) {
        const auto fighter_id = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(argv[3]));
        force = is_training_character_select() && is_sirn_id(fighter_id);
    }
    push_force(tls_dlc_force, force);
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

void post_dlc_item_ownership(void** ret_val, REFrameworkTypeDefinitionHandle, unsigned long long) {
    if (pop_force(tls_dlc_force) && ret_val != nullptr) {
        *ret_val = reinterpret_cast<void*>(static_cast<uintptr_t>(1));
    }
}

int pre_rental_ownership(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    bool force = false;
    if (argc > 2 && argv != nullptr) {
        const auto fighter_id = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(argv[2]));
        force = is_training_character_select() && is_sirn_id(fighter_id);
    }
    push_force(tls_rental_force, force);
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

void post_rental_ownership(void** ret_val, REFrameworkTypeDefinitionHandle, unsigned long long) {
    if (pop_force(tls_rental_force) && ret_val != nullptr) {
        *ret_val = reinterpret_cast<void*>(static_cast<uintptr_t>(1));
    }
}

bool hook_if_present(API::TypeDefinition* type, std::string_view signature, REFPreHookFn pre, REFPostHookFn post) {
    auto* method = find_method_exact(type, signature);
    if (method == nullptr) {
        return false;
    }
    method->add_hook(pre, post, false);
    return true;
}

void install_ownership_hooks() {
    int hooked = 0;
    auto* inventory = api().tdb()->find_type("app.InventoryManager.CharacterInventory");
    for (const auto signature : {
        "Contains(System.UInt32,System.UInt32,System.String)",
        "ContainsIgnoreRental(System.UInt32)",
        "IsValidItem(System.UInt32)"}) {
        if (hook_if_present(inventory, signature, pre_inventory_ownership, post_inventory_ownership)) {
            ++hooked;
        }
    }

    auto* dlc = api().tdb()->find_type("app.DlcManager");
    if (hook_if_present(dlc,
                        "IsValidDlcItem(app.network.api.Enum.ItemCategory,System.UInt32)",
                        pre_dlc_item_ownership,
                        post_dlc_item_ownership)) {
        ++hooked;
    }

    auto* rental = api().tdb()->find_type("app.CharacterRentalManager");
    if (hook_if_present(rental,
                        "IsRentalCharacter(System.UInt32)",
                        pre_rental_ownership,
                        post_rental_ownership)) {
        ++hooked;
    }

    log_infof("[sirn_select] ownership hooks installed: %d", hooked);
}

bool install_hooks(std::string& error) {
    auto* hgui = api().tdb()->find_type("app.helper.hGUI");
    if (hgui == nullptr) {
        error = "missing type app.helper.hGUI";
        return false;
    }

    auto* list_method = find_method_exact(hgui, "GetFighterIdList(System.Boolean)");
    auto* available_method = find_method_exact(hgui, "IsAvailableFighter(System.UInt32)");
    if (list_method == nullptr || available_method == nullptr) {
        error = "missing hGUI roster/availability getter";
        return false;
    }

    auto* select_type = api().tdb()->find_type("app.UIPartsFighterSelectSimple");
    auto* construct_method = find_method_exact(select_type, "Construct(System.Collections.Generic.List`1<System.String>)");
    auto* cursor_index_method = find_method_exact(select_type, "SetCursorIndex(System.Int32)");
    auto* cursor_fighter_method = find_method_exact(select_type, "SetCursorFighterId(System.UInt32)");
    if (construct_method == nullptr || cursor_index_method == nullptr || cursor_fighter_method == nullptr) {
        error = "missing fighter-select construct/cursor method";
        return false;
    }
    int visibility_hooks = 0;
    auto* play_object_type = api().tdb()->find_type("via.gui.PlayObject");
    if (hook_if_present(play_object_type,
                        "set_Visible(System.Boolean)",
                        pre_sirn_random_visibility,
                        nullptr)) {
        ++visibility_hooks;
    }
    log_infof("[sirn_select] visibility hooks installed: %d", visibility_hooks);

    install_ownership_hooks();
    list_method->add_hook(nullptr, post_get_fighter_id_list, false);
    available_method->add_hook(pre_is_available, post_is_available, false);
    construct_method->add_hook(pre_construct, post_construct, false);
    cursor_index_method->add_hook(pre_cursor_change, post_cursor_change, false);
    cursor_fighter_method->add_hook(pre_cursor_change, post_cursor_change, false);

    int focus_hooks = 0;
    auto* select_item_type = api().tdb()->find_type("via.gui.SelectItem");
    auto* selected_method = find_method(select_item_type, "setSelected", 2);
    if (selected_method != nullptr) {
        selected_method->add_hook(pre_sirn_selection, post_sirn_selection, false);
        ++focus_hooks;
    }
    if (hook_if_present(select_item_type,
                        "setSelectedSkipFocus(System.Boolean)",
                        pre_sirn_selection,
                        post_sirn_selection)) {
        ++focus_hooks;
    }
    log_infof("[sirn_select] focus hooks installed: %d", focus_hooks);
    return true;
}

void try_install() {
    if (g_installed || g_install_tried) {
        return;
    }

    const int scene_id = current_scene_id();
    if (scene_id < BOOT_MIN_SCENE_ID) {
        return;
    }

    g_install_tried = true;
    std::string error{};
    g_installed = install_hooks(error);
    if (g_installed) {
        log_infof("[sirn_select] hooks installed (scene %d)", scene_id);
    } else {
        log_warnf("[sirn_select] hook install failed: %s", error.c_str());
    }
}

void on_update_behavior() {
    try_install();
    if (g_installed) {
        on_frame_settle();
    }
}
} // namespace

extern "C" __declspec(dllexport) void reframework_plugin_required_version(REFrameworkPluginVersion* version) {
    if (version == nullptr) {
        return;
    }

    // Keep the published requirement at the upstream baseline. BossSelect only
    // consumes API fields that existed in 1.15, so the same DLL is accepted by
    // both upstream 1.15 and the fork's backward-compatible 1.16 loader.
    version->major = 1;
    version->minor = 15;
    version->patch = 0;
    version->game_name = nullptr;
}

extern "C" __declspec(dllexport) bool reframework_plugin_initialize(const REFrameworkPluginInitializeParam* param) {
    if (param == nullptr || param->functions == nullptr) {
        return false;
    }

    try {
        API::initialize(param);
    } catch (...) {
        return false;
    }

    if (param->functions->on_pre_application_entry == nullptr) {
        return false;
    }

    if (param->functions->on_imgui_frame != nullptr) {
        param->functions->on_imgui_frame(on_imgui_frame_reassert);
        log_info("[sirn_select] imgui-frame re-assert registered");
    }

    param->functions->on_pre_application_entry("UpdateBehavior", on_update_behavior);
    log_info("native plugin loaded; waiting for SF6 flow initialization");
    try_install();
    return true;
}

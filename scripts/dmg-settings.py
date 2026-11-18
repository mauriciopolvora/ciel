# dmgbuild settings for bash scripts/dmg.sh --layout, which passes every value as a -D define.
width = int(defines["width"])
icon_y = int(defines["icon_y"])

format = "UDZO"
files = [defines["app"]]
symlinks = {"Applications": "/Applications"}
background = defines["background"]
window_rect = ((200, 200), (width, int(defines["window_height"])))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
label_pos = "bottom"
text_size = int(defines["text_size"])
icon_size = int(defines["icon_size"])
icon_locations = {
    "Ciel.app": (int(defines["app_x"]), icon_y),
    "Applications": (int(defines["applications_x"]), icon_y),
}

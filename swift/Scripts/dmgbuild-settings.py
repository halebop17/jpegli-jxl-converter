"""dmgbuild settings for JPG Master.

Driven entirely by -D <key>=<value> arguments — dmgbuild execs this
file with `defines` populated from the CLI, and __file__ is not
available in that context. The caller is responsible for passing
absolute paths.

Required defines:
    -D app=<absolute path to JPG Master.app>
    -D icon=<absolute path to app.icns>
    -D background=<absolute path to dmg-background.png>
"""
app = defines.get("app")  # noqa: F821 — provided by dmgbuild
icon_path = defines.get("icon")  # noqa: F821
background_path = defines.get("background")  # noqa: F821
for key, value in {"app": app, "icon": icon_path, "background": background_path}.items():
    if not value:
        raise SystemExit(f"dmgbuild settings: -D {key}=<path> is required")

appname = "JPG Master"
filesystem = "HFS+"
format = "UDZO"
size = None

files = [app]
symlinks = {"Applications": "/Applications"}

icon = icon_path
badge_icon = None

icon_locations = {
    "JPG Master.app": (135, 190),
    "Applications":   (405, 190),
}

background = background_path

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

window_rect = ((200, 120), (540, 380))
default_view = "icon-view"

show_icon_preview = True
include_icon_view_settings = "auto"
include_list_view_settings = "auto"

arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 12
icon_size = 128

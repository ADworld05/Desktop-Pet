extends RefCounted
## Appearance only: the same eight item IDs/callbacks/disabled states.
const ICONS := [
	"M4 4h12v9H9l-4 3v-3H4z",
	"M7 3h6l-1 5 3 3H5l3-3z M10 11v6",
	"M13 3a7 7 0 1 0 4 10 6 6 0 0 1-4-10z",
	"M10 3v2 M10 15v2 M3 10h2 M15 10h2 M5 5l2 2 M13 13l2 2 M5 15l2-2 M13 7l2-2 M6 10a4 4 0 1 0 8 0a4 4 0 1 0-8 0",
	"M6 6h8v8H6z M8 3v3 M12 3v3 M8 14v3 M12 14v3 M3 8h3 M3 12h3 M14 8h3 M14 12h3",
	"M4 8a7 7 0 1 1 0 5 M4 4v4h4 M10 6v4l3 2",
	"M3 3l14 14 M3 10c4-6 10-6 14 0c-2 3-4 4-7 4 M7 10a3 3 0 0 0 3 3",
	"M10 2v7 M6 5a7 7 0 1 0 8 0"
]
static func apply(popup: PopupMenu) -> void:
	popup.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;popup.content_scale_size=Vector2i.ZERO;popup.content_scale_factor=1.0
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names=PackedStringArray(["Segoe UI"])
	font.font_weight=500
	theme.set_font("font","PopupMenu",font)
	theme.set_font_size("font_size","PopupMenu",14)
	for entry in [["font_color","#20364e"],["font_hover_color","#142b40"],["font_disabled_color","#66798a"],["font_accelerator_color","#546c80"]]: theme.set_color(entry[0],"PopupMenu",Color(entry[1]))
	theme.set_constant("v_separation","PopupMenu",4)
	theme.set_constant("h_separation","PopupMenu",12)
	theme.set_constant("outline_size","PopupMenu",0)
	var panel := StyleBoxFlat.new()
	panel.bg_color=Color(.94,.97,1,.68)
	panel.border_color=Color("#c6d9e8")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(12)
	panel.corner_detail=8
	panel.content_margin_left=8; panel.content_margin_right=10
	panel.content_margin_top=6; panel.content_margin_bottom=6
	theme.set_stylebox("panel","PopupMenu",panel)
	var hover := StyleBoxFlat.new()
	hover.bg_color=Color("#d6e7f4")
	hover.set_corner_radius_all(7)
	hover.border_color=Color("#7aa8c9"); hover.border_width_left=3
	theme.set_stylebox("hover","PopupMenu",hover)
	popup.theme=theme
	popup.transparent_bg=true; popup.transparent=true
	for index in ICONS.size():
		var image := Image.new()
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 20 20"><path d="%s" fill="none" stroke="#3e6785" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>'%ICONS[index]
		if image.load_svg_from_string(svg)==OK: popup.set_item_icon(index,ImageTexture.create_from_image(image))

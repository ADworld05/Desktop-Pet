extends RefCounted

static func configure(dialog:FileDialog) -> void:
	# Let Windows provide its own readable, accessible open/folder dialog.
	# A complete default theme prevents mixed light-text/dark-panel inheritance
	# if the platform cannot provide a native dialog.
	dialog.use_native_dialog=true
	dialog.theme=ThemeDB.get_default_theme().duplicate(true)

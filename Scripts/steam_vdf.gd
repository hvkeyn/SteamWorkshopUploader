class_name SteamVdf
extends RefCounted

## Minimal Valve Data Format parser for Steam config files.


static func parse_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	return parse(text)


static func parse(text: String) -> Dictionary:
	var parser := _Parser.new(text)
	return parser.parse()


class _Parser:
	var _text: String
	var _pos: int = 0

	func _init(text: String) -> void:
		_text = text

	func parse() -> Dictionary:
		_skip_ws()
		if _pos >= _text.length() or _text[_pos] != '"':
			return {}
		var key := _read_quoted_string()
		_skip_ws()
		if _pos < _text.length() and _text[_pos] == "{":
			_pos += 1
			return {key: _parse_block()}
		var value := _read_quoted_string()
		return {key: value}

	func _parse_block() -> Dictionary:
		var block: Dictionary = {}
		while _pos < _text.length():
			_skip_ws()
			if _pos >= _text.length():
				break
			if _text[_pos] == "}":
				_pos += 1
				return block
			var key := _read_quoted_string()
			if key.is_empty():
				break
			_skip_ws()
			if _pos < _text.length() and _text[_pos] == "{":
				_pos += 1
				block[key] = _parse_block()
			else:
				block[key] = _read_quoted_string()
		return block

	func _read_quoted_string() -> String:
		_skip_ws()
		if _pos >= _text.length() or _text[_pos] != '"':
			return ""
		_pos += 1
		var start := _pos
		while _pos < _text.length():
			if _text[_pos] == '"':
				var value := _text.substr(start, _pos - start)
				_pos += 1
				return value
			_pos += 1
		return ""

	func _skip_ws() -> void:
		while _pos < _text.length() and _text[_pos] in " \t\r\n":
			_pos += 1

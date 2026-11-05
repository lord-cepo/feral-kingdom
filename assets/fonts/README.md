# Game fonts

Jersey 10 by Sarah Cadigan-Fried is the current GUI and hex information font.
Source: https://github.com/google/fonts/tree/main/ofl/jersey10
`Jersey10-Regular.ttf` is bundled unchanged under `Jersey10-OFL.txt`.

`project.godot` sets Jersey 10 as the default GUI font for buttons, labels and
card text. `hex_info_font.tres` wraps the same regular font for hex stats, bomb
labels and Bash information through existing HexCell overrides. `game_theme.tres` sets the default text size to 20 (previously 16); HUD size
overrides are enlarged by approximately 20%, and hex information uses 31
(previously 26). Symbol fallback remains managed by Godot.

Pixelify Sans by Stefie Justprince remains bundled for easy comparison:
https://github.com/google/fonts/tree/main/ofl/pixelifysans
`PixelifySans.ttf` is the original variable font (weights 400–700), distributed
under `PixelifySans-OFL.txt`.

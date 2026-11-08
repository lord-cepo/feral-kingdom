# Army builder

The application starts at `scenes/army_menu.tscn`. Host and Join currently show
availability messages; Build opens the army editor with a short fade.

Choose 8, 12 or 16 distinct catalogue units, enter an army name and save.
Saving an existing name replaces that deck. Saved armies can be loaded for editing.
Local decks live in Godot's `user://armies.json`, using catalogue UUIDs without
player suffixes. They do not yet configure hosted or joined matches.

Caller map: scene entry `_ready` loads local records and builds the landing menu;
navigation calls `_navigate`, which loads the catalogue and calls `_build_editor`
only on the first Build entry (the landing menu does not load unit textures).
Size and unit controls call `_resize_army` and
`_toggle_unit`, which update `_refresh_selection`. Save calls `_save_deck` and
`_refresh_saved`; Load calls `_load_deck` and refreshes selection. No gameplay
state or effect definitions are changed. Duplicate copies are not offered because
this editor selects a subset; additional army composition rules remain undecided.

Catalogue rows show the shared pixel sprite portrait. Hover or keyboard-focus a
row to immediately inspect its type, life, deployment regions and the same rule
descriptions used by board hover cards. The inspector is fixed 20px from the
bottom-right corner, without a tooltip delay or appearance fade. It retains the
last inspected card so you can scroll longer rules. Searching or leaving Build
dismisses it. Default Walk is included, without adding units to Match.

The deployment bar is on the left of the card. Starting uses dark red and
Intermediate light red for the user; enemy-side-only deployments use dark/light
blue instead. Front stays grey, matching the roster's region convention. Regions
stack top to bottom in Starting, Intermediate, Front order. These indicate printed
deployment regions, not current board availability. The builder assumes player 1
(red), with player 2 (blue) as the enemy, including rule-text ownership colors.

Search accepts partial names and rule keywords, ignoring case. Each word must
match: `rat fire` finds rats with Fire; `walk`, `bow`, and `reset` also work when
an action is displayed as an icon. Clear the field to show the full catalogue.
Filtering never removes selected units or changes the saved deck.

Additional callers: `_build_editor` prepares `_searchable_rules` once per card
and connects search `text_changed` to `_filter_units`. `_ready` creates the shared
inspector through `_build_info_panel`; root `resized` calls `_layout_info_panel`.
Row `mouse_entered` and `focus_entered` call `_inspect_unit`, which installs
`army_unit_choice.gd::make_info_card` content and resets scrolling immediately.
The card decorates rules with `RuleGuide.decorate`; metadata hover signals call
`_show_rule_guide` / `_hide_rule_guide`, using shared `RuleGuide.description`
entries. `_fade_rule_guide` blends an explanation below the rules on ordinary
hover, without Ctrl. Hover Disable or Ember to read its meaning, or hover the
Fire icon for its attack explanation.
`_navigate` and `_filter_units` dismiss the inspector. For example, inspecting
Dormouse Rogue shows a blue Intermediate stripe and an Enemy side label;
ordinary Starting units show a red stripe.

Cursor presentation: both `army_menu.gd::_ready` and `game.gd::_ready` call
`game_cursors.gd::install`, so direct scene launches share the same pixel hand.
Text fields use a parchment I-beam. Godot's native drag/drop shapes use a closed
hand while dragging, a hand/check for accepted drops and a red blocked symbol for
rejected drops. The game's Ctrl-movable inspection panel shows an open hand
before dragging and a closed hand during movement; `_input` and
`_sync_hover_target_input` restore ordinary cursors on release. Cursor art lives
under `assets/ui/*-cursor.svg`, with explicit hotspots in the shared installer.
For example, hover the army name/search field for the I-beam, or drag selected
text within a text field for the native drag/drop feedback. Army rows still use
checkbox selection; cursor styling does not add a new deck drag/drop operation.

Local play: after entering a name, choose **Local game** to play offline with
both starter armies under your control. Take each side's actions on its turn;
trigger acknowledgements use the existing successive local-player prompts.
No relay connection is required. Leave any occupied online lobby first.
Caller map: the navigation button calls `_navigate("Local game")`, which calls
`_start_local_game`; that opens `game.tscn` with NetworkSession.online disabled.
`local_match_controller.gd::_ready` uses its existing offline starter-army path.
